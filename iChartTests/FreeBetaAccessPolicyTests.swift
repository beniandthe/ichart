import Foundation
import XCTest
@testable import iChart

@MainActor
final class FreeBetaAccessPolicyTests: XCTestCase {
    func testBothBetaChoicesAreFreeAndDoNotOfferPaidPurchases() {
        XCTAssertEqual(IChartProductAccessPolicy.current, .freeAllFeatures)
        for policy in [IChartProductAccessPolicy.freeAllFeatures, .betaBasic] {
            XCTAssertTrue(policy.isFreeBeta)
            XCTAssertFalse(policy.offersPaidPurchases)
        }
        XCTAssertTrue(IChartProductAccessPolicy.freeAllFeatures.includesAllFeatures)
        XCTAssertFalse(IChartProductAccessPolicy.betaBasic.includesAllFeatures)
        XCTAssertFalse(IChartProductAccessPolicy.paidSubscription.isFreeBeta)
        XCTAssertTrue(IChartProductAccessPolicy.paidSubscription.offersPaidPurchases)
    }

    func testVoluntaryBasicUsesBasicFeaturesEvenWhenAppleBillingIsActive() {
        let basicReference = AppEntitlements(subscription: .basic, accessPolicy: .paidSubscription)
        for status in IChartSubscriptionStatus.allCases {
            let billing = billingEvidence(status)
            let entitlements = AppEntitlements(subscription: billing, accessPolicy: .betaBasic)

            XCTAssertEqual(entitlements.subscription, billing)
            XCTAssertEqual(entitlements.activePlan, billing.effectivePlan, "Billing evidence remains separate from access")
            XCTAssertEqual(entitlements.localChartLimit, 3)
            XCTAssertTrue(entitlements.canCreateChart(currentChartCount: 2))
            XCTAssertFalse(entitlements.canCreateChart(currentChartCount: 3))
            XCTAssertFalse(entitlements.canCreateChart(currentChartCount: 20))
            XCTAssertEqual(entitlements.remainingLocalChartSlots(currentChartCount: 20), 0)
            for feature in EntitledFeature.allCases {
                XCTAssertEqual(entitlements.includes(feature), basicReference.includes(feature), "\(status), \(feature)")
            }
        }
    }

    func testBillingRefreshCannotSilentlyRejoinProFromVoluntaryBasic() {
        var entitlements = AppEntitlements(subscription: .basic, accessPolicy: .betaBasic)
        for status in IChartSubscriptionStatus.allCases {
            let billing = billingEvidence(status)
            entitlements.applySubscription(billing)

            XCTAssertEqual(entitlements.accessPolicy, .betaBasic)
            XCTAssertEqual(entitlements.subscription, billing)
            XCTAssertEqual(entitlements.localChartLimit, 3)
            XCTAssertFalse(entitlements.includes(.cloudBackup))
            XCTAssertFalse(entitlements.includes(.forums))
            XCTAssertFalse(entitlements.includes(.projects))
            XCTAssertTrue(entitlements.includes(.pdfExport))
        }
    }

    func testLeavingAndRejoiningProPreservesOverCapChartsProjectsSelectionAndBilling() throws {
        let billing = billingEvidence(.proActive)
        let charts = (1...6).map { Chart.blank(title: "Existing Chart \($0)") }
        let project = ChartProject(title: "Existing Project", chartIDs: charts.map(\.id))
        let tombstone = ChartDeletionTombstone(chartID: UUID(), deletedAt: Date(timeIntervalSinceReferenceDate: 1))
        let metadata = ChartCloudMetadata(ownerID: UUID(), lastSyncAt: Date(timeIntervalSinceReferenceDate: 2))
        let store = ChartLibraryStore(
            charts: charts,
            entitlements: AppEntitlements(subscription: billing),
            selectedChartID: charts[4].id,
            deletionTombstones: [tombstone],
            cloudMetadata: metadata,
            projects: [project]
        )

        store.applyAccessPolicy(.betaBasic)

        XCTAssertEqual(store.entitlements.subscription, billing)
        XCTAssertEqual(store.entitlements.activePlan, .studioSubscription)
        XCTAssertEqual(store.localChartLimit, 3)
        XCTAssertEqual(store.localChartOverflowCount, 3)
        XCTAssertFalse(store.canCreateChart)
        XCTAssertFalse(store.createBlankChart())
        XCTAssertNil(store.duplicateChart(id: charts[0].id))
        XCTAssertFalse(store.requiresLocalChartPruningForCurrentPlan)
        XCTAssertFalse(store.isChartEditingLockedByCurrentPlan)
        XCTAssertTrue(store.canOpenChartsForEditing)
        XCTAssertFalse(store.pruneLocalChartForCurrentPlan(id: charts[4].id))
        XCTAssertEqual(store.charts, charts)
        XCTAssertEqual(store.charts(in: project), charts)
        XCTAssertEqual(store.projects, [project])
        XCTAssertEqual(store.selectedChartID, charts[4].id)
        XCTAssertEqual(store.deletionTombstones, [tombstone])
        XCTAssertEqual(store.cloudMetadata, metadata)
        XCTAssertFalse(store.canUse(.cloudBackup))
        XCTAssertFalse(store.canUse(.forums))
        XCTAssertFalse(store.canUse(.projects))
        XCTAssertTrue(store.renameChart(id: charts[4].id, to: "Still Editable"))

        let retainedCharts = store.charts
        store.applyAccessPolicy(.freeAllFeatures)

        XCTAssertEqual(store.entitlements.subscription, billing)
        XCTAssertEqual(store.charts, retainedCharts)
        XCTAssertEqual(store.projects, [project])
        XCTAssertEqual(store.selectedChartID, charts[4].id)
        XCTAssertEqual(store.deletionTombstones, [tombstone])
        XCTAssertEqual(store.cloudMetadata, metadata)
        XCTAssertNil(store.localChartLimit)
        XCTAssertTrue(store.canCreateChart)
        XCTAssertTrue(store.canUse(.cloudBackup))
        XCTAssertTrue(store.canUse(.forums))
        XCTAssertTrue(store.canUse(.projects))
        XCTAssertTrue(store.createBlankChart())
        XCTAssertEqual(store.charts.count, 7)
    }

    func testVoluntaryBasicAllowsCreationUpToThreeWithoutPruning() {
        let charts = (1...2).map { Chart.blank(title: "Chart \($0)") }
        let store = ChartLibraryStore(charts: charts, entitlements: AppEntitlements(subscription: .basic))
        store.applyAccessPolicy(.betaBasic)

        XCTAssertTrue(store.createBlankChart())
        XCTAssertEqual(store.charts.count, 3)
        XCTAssertFalse(store.createBlankChart())
        XCTAssertFalse(store.requiresLocalChartPruningForCurrentPlan)
        XCTAssertTrue(store.canOpenChartsForEditing)
        XCTAssertEqual(store.entitlements.subscription, .basic)
    }

    func testStaleProjectTargetCannotCreateOrDuplicateVariantAfterLeavingPro() {
        let chart = Chart.blank(title: "Existing Project Chart")
        let project = ChartProject(title: "Existing Project", chartIDs: [chart.id])
        let store = ChartLibraryStore(charts: [chart], entitlements: AppEntitlements(subscription: .activePro()),
            selectedChartID: chart.id, projects: [project])
        store.applyAccessPolicy(.betaBasic)
        let before = store.snapshot

        XCTAssertFalse(store.createBlankChart(projectID: project.id))
        XCTAssertNil(store.duplicateChart(id: chart.id, projectID: project.id))
        XCTAssertEqual(store.snapshot, before)
        XCTAssertEqual(store.charts(in: project), [chart])
        XCTAssertTrue(store.canOpenChartsForEditing)
        XCTAssertTrue(store.createBlankChart(), "Plain Basic chart creation remains available under the cap")
        XCTAssertNotNil(store.duplicateChart(id: chart.id), "Plain duplication remains available under the cap")
        XCTAssertEqual(store.charts.count, 3)
        XCTAssertEqual(store.projects, [project])
    }

    func testSavedLibraryDoesNotPersistOrAcceptRuntimeBetaPolicy() throws {
        let billing = billingEvidence(.proActive)
        let entitlements = AppEntitlements(subscription: billing, accessPolicy: .betaBasic)
        let data = try JSONEncoder().encode(entitlements)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(payload.keys), Set(["activePlan", "subscription"]))
        payload["accessPolicy"] = "betaBasic"
        let decoded = try JSONDecoder().decode(AppEntitlements.self, from: JSONSerialization.data(withJSONObject: payload))

        XCTAssertEqual(decoded.subscription, billing)
        XCTAssertEqual(decoded.accessPolicy, .current, "Account membership must be restored separately, not trusted from chart JSON")
        XCTAssertNil(decoded.localChartLimit)
    }

    func testApplyingSyncedSnapshotPreservesRuntimeBasicWhileUpdatingBillingAndContent() {
        let store = ChartLibraryStore(charts: [], entitlements: AppEntitlements(subscription: .basic, accessPolicy: .betaBasic))
        let chart = Chart.blank(title: "Restored Chart")
        let project = ChartProject(title: "Restored Project", chartIDs: [chart.id])
        let updatedBilling = billingEvidence(.proActive)
        let snapshot = ChartLibrarySnapshot(
            charts: [chart],
            selectedChartID: chart.id,
            entitlements: AppEntitlements(subscription: updatedBilling),
            projects: [project]
        )

        store.applySyncedSnapshot(snapshot)

        XCTAssertEqual(store.entitlements.accessPolicy, .betaBasic)
        XCTAssertEqual(store.entitlements.subscription, updatedBilling)
        XCTAssertEqual(store.charts, [chart])
        XCTAssertEqual(store.projects, [project])
        XCTAssertEqual(store.selectedChartID, chart.id)
        XCTAssertEqual(store.localChartLimit, 3)
        XCTAssertFalse(store.canUse(.forums))
        XCTAssertTrue(store.canOpenChartsForEditing)
    }

    func testBothBetaModesPreserveDownloadedPDFBytesAndSetlistLinksAcrossAllBillingStates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bytes = Data("%PDF-1.7\n% Existing customer document\n".utf8)
        let source = root.appendingPathComponent("Source.pdf")
        try bytes.write(to: source)
        let libraryDirectory = root.appendingPathComponent("PDFs", isDirectory: true)
        let setlistDirectory = root.appendingPathComponent("Setlists", isDirectory: true)
        let pdfStore = IChartPDFLibraryStore(baseDirectory: libraryDirectory)
        let exported = ExportedPDF(
            url: source,
            chartTitle: "Existing PDF",
            layoutStyle: .simpleChordSheet,
            transpositionView: .concert,
            chordTranspositionSemitones: 0,
            pageCount: 1,
            fileSizeBytes: bytes.count,
            exportedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let forumPDF = try pdfStore.save(exported, source: .forumDownload)
        let localPDF = try pdfStore.save(exported, source: .chartExport)
        let forumItem = try XCTUnwrap(pdfStore.items.first { $0.source == .forumDownload })
        let setlistStore = IChartPDFSetlistStore(baseDirectory: setlistDirectory)
        let setlist = try setlistStore.create(name: "Existing Gig")
        let entry = try setlistStore.add(pdfItem: forumItem, to: setlist.id)
        let originalItems = pdfStore.items
        let originalSetlists = setlistStore.setlists

        for policy in [IChartProductAccessPolicy.freeAllFeatures, .betaBasic] {
            for status in IChartSubscriptionStatus.allCases {
                let billing = billingEvidence(status)
                XCTAssertTrue(billing.allowsForumDownloadAccess(accessPolicy: policy))
                XCTAssertFalse(billing.shouldRemoveForumDownloads(accessPolicy: policy))
                XCTAssertEqual(pdfStore.removeForumDownloadsIfInactive(for: billing, accessPolicy: policy), 0)
                XCTAssertEqual(pdfStore.visibleItems(for: billing, accessPolicy: policy), originalItems)
                XCTAssertEqual(pdfStore.items, originalItems)
                let retainedSetlist = try XCTUnwrap(setlistStore.setlist(id: setlist.id))
                let resolvedEntries = retainedSetlist.resolvedEntries(in: pdfStore.visibleItems(for: billing, accessPolicy: policy))
                XCTAssertEqual(resolvedEntries.map(\.id), [entry.id])
                XCTAssertEqual(resolvedEntries.first?.pdfItem?.id, forumItem.id)
                XCTAssertEqual(try Data(contentsOf: forumPDF.url), bytes)
                XCTAssertEqual(try Data(contentsOf: localPDF.url), bytes)
            }
        }

        let reopenedPDFs = IChartPDFLibraryStore(baseDirectory: libraryDirectory)
        XCTAssertEqual(reopenedPDFs.visibleItems(for: .basic, accessPolicy: .betaBasic), originalItems)
        XCTAssertEqual(reopenedPDFs.removeForumDownloadsIfInactive(for: .basic, accessPolicy: .betaBasic), 0)
        XCTAssertEqual(IChartPDFSetlistStore(baseDirectory: setlistDirectory).setlists, originalSetlists)
    }

    func testParkedPaidPolicyKeepsExistingBillingAndPruningContracts() {
        let charts = (1...4).map { Chart.blank(title: "Chart \($0)") }
        let store = ChartLibraryStore(
            charts: charts,
            entitlements: AppEntitlements(subscription: .proExpired(), accessPolicy: .paidSubscription)
        )
        XCTAssertTrue(store.requiresLocalChartPruningForCurrentPlan)
        XCTAssertTrue(store.isChartEditingLockedByCurrentPlan)
        XCTAssertEqual(store.localChartLimit, 3)
        XCTAssertFalse(IChartSubscriptionEntitlement.basic.allowsForumDownloadAccess(accessPolicy: .paidSubscription))
        XCTAssertTrue(IChartSubscriptionEntitlement.basic.shouldRemoveForumDownloads(accessPolicy: .paidSubscription))

        store.applySubscriptionState(.activePro())
        XCTAssertNil(store.localChartLimit)
        XCTAssertFalse(store.requiresLocalChartPruningForCurrentPlan)
        XCTAssertTrue(store.canUse(.cloudBackup))

        let previousPaidSnapshotContract = ChartLibrarySnapshot(
            charts: charts,
            selectedChartID: charts[0].id,
            entitlements: AppEntitlements(subscription: .basic)
        )
        store.applySyncedSnapshot(previousPaidSnapshotContract)
        XCTAssertEqual(store.entitlements, previousPaidSnapshotContract.entitlements)
    }

    private func billingEvidence(_ status: IChartSubscriptionStatus) -> IChartSubscriptionEntitlement {
        IChartSubscriptionEntitlement(
            status: status,
            graceEndsAt: Date(timeIntervalSinceReferenceDate: 100),
            accessEndsAt: Date(timeIntervalSinceReferenceDate: 200),
            willAutoRenew: true,
            lastVerifiedAt: Date(timeIntervalSinceReferenceDate: 50)
        )
    }
}
