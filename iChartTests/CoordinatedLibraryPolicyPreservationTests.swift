import Foundation
import Combine
import XCTest
@testable import iChart

@MainActor
final class CoordinatedLibraryPolicyPreservationTests: XCTestCase {
    private let policies: [IChartProductAccessPolicy] = [.freeAllFeatures, .betaBasic, .paidSubscription]

    func testPhaseOnlyChangesPublishWithoutWritesUploadsOrTombstonesButRealChangesPersist() throws {
        let charts = try savedCharts()
        let repository = RecordingRepository()
        let store = ChartLibraryStore(charts: charts,
            entitlements: AppEntitlements(subscription: .basic, accessPolicy: .freeAllFeatures),
            selectedChartID: charts[0].id, repository: repository)
        var notifications = 0
        var publishedPolicies: [IChartProductAccessPolicy] = []
        store.onSnapshotSaved = { _ in notifications += 1 }
        let observation = store.$entitlements.dropFirst().sink { publishedPolicies.append($0.accessPolicy) }
        defer { observation.cancel() }

        store.applyAccessPolicy(.betaBasic)
        store.applyAccessPolicy(.paidSubscription)
        store.applyAccessPolicy(.freeAllFeatures)
        XCTAssertEqual(publishedPolicies, [.betaBasic, .paidSubscription, .freeAllFeatures])
        XCTAssertTrue(repository.saved.isEmpty)
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(store.charts, charts)
        XCTAssertTrue(store.deletionTombstones.isEmpty)

        XCTAssertTrue(store.renameChart(id: charts[0].id, to: "Real saved edit"))
        XCTAssertEqual(repository.saved.count, 1)
        XCTAssertEqual(notifications, 1)
        store.applySubscriptionState(.activePro())
        XCTAssertEqual(repository.saved.count, 2)
        XCTAssertEqual(notifications, 2)
        XCTAssertEqual(repository.saved.last?.charts, store.charts)
        XCTAssertEqual(repository.saved.last?.entitlements.subscription, .activePro())
        XCTAssertTrue(store.deletionTombstones.isEmpty)
    }

    func testEveryRuntimePolicySurvivesIncomingPolicyAndBillingSnapshotMatrix() throws {
        let charts = try savedCharts()
        let project = ChartProject(title: "Saved project", chartIDs: charts.map(\.id))
        let tombstone = ChartDeletionTombstone(chartID: UUID(), deletedAt: Date(timeIntervalSince1970: 100))
        let metadata = ChartCloudMetadata(ownerID: UUID(), lastSyncAt: Date(timeIntervalSince1970: 200))
        for resolved in policies {
            for incomingPolicy in policies {
                for status in IChartSubscriptionStatus.allCases {
                    let billing = IChartSubscriptionEntitlement(status: status,
                        graceEndsAt: Date(timeIntervalSince1970: 300),
                        accessEndsAt: Date(timeIntervalSince1970: 400), willAutoRenew: false,
                        lastVerifiedAt: Date(timeIntervalSince1970: 200))
                    let incoming = ChartLibrarySnapshot(charts: charts, selectedChartID: charts.last?.id,
                        entitlements: AppEntitlements(subscription: billing, accessPolicy: incomingPolicy),
                        deletionTombstones: [tombstone], cloudMetadata: metadata, projects: [project])
                    let store = ChartLibraryStore(charts: [],
                        entitlements: AppEntitlements(subscription: .basic, accessPolicy: resolved))
                    store.applySyncedSnapshot(incoming)

                    XCTAssertEqual(store.entitlements.accessPolicy, resolved)
                    let expectedBilling: IChartSubscriptionEntitlement = IChartProductAccessPolicy.usesCoordinatedActivation
                        ? .basic : billing
                    XCTAssertEqual(store.entitlements.subscription, expectedBilling)
                    XCTAssertEqual(store.entitlements, AppEntitlements(subscription: expectedBilling, accessPolicy: resolved))
                    XCTAssertEqual(store.charts, charts)
                    XCTAssertEqual(store.projects, [project])
                    XCTAssertEqual(store.selectedChartID, charts.last?.id)
                    XCTAssertEqual(store.deletionTombstones, [tombstone])
                    XCTAssertEqual(store.cloudMetadata, metadata)
                    XCTAssertTrue(store.canUse(.pdfExport))
                    for chart in charts { XCTAssertNotNil(store.editorBinding(for: chart.id)) }
                }
            }
        }
    }

    func testGuardedCloudApplyPreservesResolvedPolicyAndRejectsNewerLocalEdits() throws {
        let charts = try savedCharts()
        for resolved in policies {
            let store = ChartLibraryStore(charts: charts,
                entitlements: AppEntitlements(subscription: .basic, accessPolicy: resolved),
                selectedChartID: charts[0].id)
            let expected = store.snapshot
            let incoming = ChartLibrarySnapshot(charts: charts, selectedChartID: charts.last?.id,
                entitlements: AppEntitlements(subscription: .activePro(), accessPolicy: .freeAllFeatures))
            XCTAssertTrue(store.applySyncedSnapshot(incoming, ifUnchangedFrom: expected))
            XCTAssertEqual(store.entitlements.accessPolicy, resolved)
            XCTAssertEqual(store.entitlements.subscription,
                           IChartProductAccessPolicy.usesCoordinatedActivation ? .basic : .activePro())
            let beforeEdit = store.snapshot
            XCTAssertTrue(store.renameChart(id: charts[0].id, to: "Newer saved local title"))
            let local = store.snapshot
            XCTAssertFalse(store.applySyncedSnapshot(incoming, ifUnchangedFrom: beforeEdit))
            XCTAssertEqual(store.snapshot, local)
        }
    }

    func testArchivedProCannotReplaceCurrentOwnerBillingInCoordinatedProduction() throws {
        let charts = try savedCharts()
        for current in [IChartSubscriptionEntitlement.basic, .unavailable, .legacyLocalPro] {
            let store = ChartLibraryStore(charts: charts,
                entitlements: AppEntitlements(subscription: current, accessPolicy: .paidSubscription))
            let archived = ChartLibrarySnapshot(charts: charts, selectedChartID: charts[0].id,
                entitlements: AppEntitlements(subscription: .activePro(), accessPolicy: .freeAllFeatures))
            store.applySyncedSnapshot(archived)
            XCTAssertEqual(store.entitlements.accessPolicy, .paidSubscription)
            XCTAssertEqual(store.entitlements.subscription,
                IChartProductAccessPolicy.usesCoordinatedActivation ? current : .activePro())
            XCTAssertEqual(store.charts, charts)
            XCTAssertTrue(store.canUse(.pdfExport))
            if IChartProductAccessPolicy.usesCoordinatedActivation && current.status != .legacyLocalPro {
                XCTAssertFalse(store.canUse(.cloudBackup))
                XCTAssertFalse(store.canUse(.projects))
                XCTAssertFalse(store.canCreateChart)
            }
        }
    }

    func testBetaPaidExpiryRollbackAndReopenKeepMusicInkFontsAndProjectMembership() throws {
        let charts = try savedCharts()
        let project = ChartProject(title: "Existing variants", chartIDs: charts.map(\.id))
        let store = ChartLibraryStore(charts: charts,
            entitlements: AppEntitlements(subscription: .basic, accessPolicy: .freeAllFeatures),
            selectedChartID: charts.last?.id, projects: [project])
        let transitions: [(IChartProductAccessPolicy, IChartSubscriptionEntitlement)] = [
            (.betaBasic, .basic), (.paidSubscription, .basic), (.paidSubscription, .activePro()),
            (.paidSubscription, .proExpired()), (.paidSubscription, .unavailable),
            (.freeAllFeatures, .proExpired()), (.betaBasic, .activePro())
        ]
        for (policy, billing) in transitions {
            store.applyAccessPolicy(policy)
            store.applySubscriptionState(billing)
            let encoded = try JSONEncoder().encode(store.snapshot)
            let reopened = try JSONDecoder().decode(ChartLibrarySnapshot.self, from: encoded)
            store.applySyncedSnapshot(reopened)
            XCTAssertEqual(store.entitlements.accessPolicy, policy)
            XCTAssertEqual(store.entitlements.subscription, billing)
            XCTAssertEqual(store.charts, charts, "A phase, billing or cache transition cannot rewrite music or ink")
            XCTAssertEqual(store.projects, [project])
            XCTAssertEqual(store.charts(in: project), charts)
            XCTAssertEqual(store.selectedChartID, charts.last?.id)
            XCTAssertTrue(store.canUse(.pdfExport))
            for chart in charts { XCTAssertEqual(try XCTUnwrap(store.editorBinding(for: chart.id)).wrappedValue, chart) }
            if store.localChartLimit != nil {
                XCTAssertFalse(store.canCreateChart)
                XCTAssertFalse(store.createBlankChart())
                XCTAssertNil(store.duplicateChart(id: charts[0].id))
                XCTAssertEqual(store.charts, charts)
            }
        }
    }

    private func savedCharts() throws -> [Chart] {
        try [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet].flatMap { style in
            try (1...2).map { index in
                var chart = Chart.blank(title: "Saved \(style.rawValue) \(index)", measureCount: 2, layoutStyle: style)
                chart.pageHandwrittenChordData = Data("Synthetic pending chord ink".utf8)
                chart.pageHandwrittenNotationData = Data("Synthetic Free Ink".utf8)
                chart.pageHandwrittenHeaderData = Data("Synthetic header ink".utf8)
                chart.sourcePDFLibraryItemID = UUID()
                chart.notationFont = .petaluma
                chart.typography = ChartTypographySettings(matchedSet: .finaleJazz,
                    chordOverride: .museJazz, headerOverride: .petaluma, textOverride: .finaleJazz)
                let measureID = try XCTUnwrap(chart.measures.first?.id)
                chart.appendRecognizedChord(try ChordSymbolParser.parse("G/B"), rawInput: "G/B",
                    to: measureID, atFraction: 0.05, sourceInkData: Data("Synthetic rendered source".utf8),
                    sourceCandidateSignature: ["G/B"])
                return chart
            }
        }
    }

    private final class RecordingRepository: ChartRepository {
        var saved: [ChartLibrarySnapshot] = []
        func loadSnapshot() throws -> ChartLibrarySnapshot? { saved.last }
        func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws { saved.append(snapshot) }
    }
}
