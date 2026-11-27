import Foundation
import XCTest
@testable import iChart

/// This assertion runs in ordinary CI as well as the separate paid build.
final class ProductionPaidBuildScopeTests: XCTestCase {
    func testCurrentPolicyMatchesTheCompiledProductScope() {
        #if ICHART_PAID_SUBSCRIPTION
        XCTAssertEqual(IChartProductAccessPolicy.current, .paidSubscription)
        #else
        XCTAssertEqual(IChartProductAccessPolicy.current, .freeAllFeatures)
        XCTAssertFalse(IChartProductAccessPolicy.current.offersPaidPurchases)
        #endif
        #if ICHART_PRODUCTION_PAID_VALIDATION
        XCTAssertEqual(IChartProductAccessPolicy.current, .paidSubscription,
                       "The app target, not only the test bundle, must use paid policy")
        #endif
        #if ICHART_STAGING_STOREKIT_PRODUCTS || ICHART_INTERNAL_STAGING || ICHART_LOCAL_PLAN_QA || ICHART_LOCAL_QA_PLAN_PREVIEW
        XCTFail("Production paid validation must not use staging or local plan overrides")
        #endif
        XCTAssertEqual(IChartStoreKitProductCatalog.proProductIDs,
                       ["com.ichart.app.pro.monthly", "com.ichart.app.pro.annual"])
        XCTAssertEqual(IChartStoreKitProductCatalog.targetMonthlyPriceCents, 699)
        XCTAssertEqual(IChartStoreKitProductCatalog.targetAnnualPriceCents, 6_000)
    }
}

#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit

/// These cases deliberately use AppEntitlements' default policy. Merely passing
/// an explicit `.paidSubscription` in a free binary cannot certify this lane.
@MainActor
final class ProductionPaidAccessPolicyTests: XCTestCase {
    override func setUpWithError() throws {
        #if !ICHART_PRODUCTION_PAID_VALIDATION
        throw XCTSkip("Run the separate production-paid validation project for paid-default assertions")
        #endif
        XCTAssertEqual(IChartProductAccessPolicy.current, .paidSubscription)
    }

    func testDefaultBasicExpiredAndUnavailableKeepCoreWritingAndLimitOnlyNewCreation() {
        for billing in [IChartSubscriptionEntitlement.basic, .proExpired(), .unavailable] {
            let access = AppEntitlements(subscription: billing)
            XCTAssertEqual(access.accessPolicy, .paidSubscription)
            XCTAssertEqual(access.subscription, billing)
            XCTAssertEqual(access.localChartLimit, 3)
            XCTAssertTrue(access.canCreateChart(currentChartCount: 2))
            XCTAssertFalse(access.canCreateChart(currentChartCount: 3))
            XCTAssertFalse(access.canCreateChart(currentChartCount: 30))
            for core in [EntitledFeature.pdfExport, .documentTransposition,
                         .roadmapNotationTools, .advancedRhythmEditing] {
                XCTAssertTrue(access.includes(core), "\(billing.status): \(core)")
            }
            XCTAssertFalse(access.canUsePremiumFonts)
            XCTAssertFalse(access.canConvertPDFToEditableChart)
            XCTAssertFalse(access.includes(.projects))
            XCTAssertFalse(access.includes(.cloudBackup))
            XCTAssertFalse(access.includes(.forums))
            XCTAssertFalse(access.canSyncPDFSetlists)
        }
    }

    func testVerifiedProAndCancellationThroughPaidThroughKeepAllProAccess() {
        let billing = IChartSubscriptionEntitlement.activePro(
            accessEndsAt: Date(timeIntervalSince1970: 1_900_000_000), willAutoRenew: false)
        let access = AppEntitlements(subscription: billing)
        XCTAssertEqual(access.accessPolicy, .paidSubscription)
        XCTAssertEqual(access.subscription.willAutoRenew, false)
        XCTAssertNil(access.localChartLimit)
        XCTAssertTrue(access.canCreateChart(currentChartCount: 30))
        for feature in EntitledFeature.allCases { XCTAssertTrue(access.includes(feature), "\(feature)") }
        XCTAssertTrue(access.canUsePremiumFonts)
        XCTAssertTrue(access.canConvertPDFToEditableChart)
        XCTAssertTrue(access.canSyncPDFSetlists)
    }

    func testDowngradeAndReupgradePreserveSavedSourceFontsConvertedChartsAndProjects() throws {
        for inactive in [IChartSubscriptionEntitlement.basic, .proExpired(), .unavailable] {
            let repository = RoundTripRepository()
            let charts = try [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet].flatMap { style in
                try (1...2).map { try savedChart(style: style, ordinal: $0) }
            }
            let project = ChartProject(title: "Retained project", chartIDs: charts.map(\.id))
            let store = ChartLibraryStore(charts: charts, entitlements: AppEntitlements(subscription: .activePro()),
                selectedChartID: charts.last?.id, projects: [project], repository: repository)

            store.applySubscriptionState(inactive)

            XCTAssertEqual(store.charts, charts)
            XCTAssertEqual(store.projects, [project])
            XCTAssertEqual(store.selectedChartID, charts.last?.id)
            XCTAssertFalse(store.canCreateChart)
            XCTAssertFalse(store.createBlankChart())
            XCTAssertNil(store.duplicateChart(id: charts[0].id))
            XCTAssertNil(store.createProject(title: "Blocked new project"))
            XCTAssertFalse(store.renameProject(id: project.id, to: "Blocked rename"))
            XCTAssertFalse(store.deleteProject(id: project.id))
            XCTAssertTrue(store.canUse(.pdfExport))
            for original in charts {
                let binding = try XCTUnwrap(store.editorBinding(for: original.id))
                var edited = binding.wrappedValue
                edited.title += " edited"
                binding.wrappedValue = edited
                let retained = try XCTUnwrap(store.charts.first { $0.id == original.id })
                XCTAssertEqual(retained.pageHandwrittenChordData, original.pageHandwrittenChordData)
                XCTAssertEqual(retained.pageHandwrittenHeaderData, original.pageHandwrittenHeaderData)
                XCTAssertEqual(retained.pageHandwrittenNotationData, original.pageHandwrittenNotationData)
                XCTAssertEqual(retained.measures, original.measures)
                XCTAssertEqual(retained.sourcePDFLibraryItemID, original.sourcePDFLibraryItemID)
                XCTAssertEqual(retained.typography, original.typography)
                XCTAssertEqual(retained.notationFont, original.notationFont)
            }
            let reopened = try XCTUnwrap(repository.loadSnapshot())
            XCTAssertEqual(reopened.charts, store.charts)
            XCTAssertEqual(reopened.projects, [project])
            XCTAssertEqual(reopened.entitlements.accessPolicy, .paidSubscription)
            let retained = store.charts
            store.applySubscriptionState(.activePro())
            XCTAssertEqual(store.charts, retained)
            XCTAssertEqual(store.projects, [project])
            XCTAssertTrue(store.canCreateChart)
            XCTAssertTrue(store.canUse(.projects))
        }
    }

    func testDefaultPaidBillingTransitionsKeepSavedPDFBytesAndSetlistReferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Source.pdf")
        let bytes = Data("%PDF-1.7\n% Dedicated local preservation fixture\n".utf8)
        try bytes.write(to: source)
        let library = root.appendingPathComponent("PDFs")
        let setlists = root.appendingPathComponent("Setlists")
        let pdfStore = IChartPDFLibraryStore(baseDirectory: library)
        let exported = ExportedPDF(url: source, chartTitle: "Saved PDF", layoutStyle: .simpleChordSheet,
            transpositionView: .concert, chordTranspositionSemitones: 0, pageCount: 1,
            fileSizeBytes: bytes.count, exportedAt: Date(timeIntervalSinceReferenceDate: 10))
        let downloaded = try pdfStore.save(exported, source: .forumDownload)
        let original = try pdfStore.save(exported, source: .chartExport)
        let savedItems = pdfStore.items
        let setlistStore = IChartPDFSetlistStore(baseDirectory: setlists)
        let setlist = try setlistStore.create(name: "Saved gig", pdfItems: savedItems)
        let savedSetlists = setlistStore.setlists
        let store = ChartLibraryStore(charts: [], entitlements: AppEntitlements(subscription: .activePro()))
        for state in [IChartSubscriptionEntitlement.basic, .proExpired(), .unavailable, .activePro()] {
            store.applySubscriptionState(state)
            XCTAssertEqual(store.entitlements.accessPolicy, .paidSubscription)
            let reopenedPDFs = IChartPDFLibraryStore(baseDirectory: library)
            let reopenedSetlists = IChartPDFSetlistStore(baseDirectory: setlists)
            XCTAssertEqual(reopenedPDFs.items, savedItems)
            XCTAssertEqual(reopenedSetlists.setlists, savedSetlists)
            XCTAssertEqual(reopenedSetlists.setlist(id: setlist.id)?.resolvedEntries(in: reopenedPDFs.items)
                .compactMap(\.pdfItem?.id), savedItems.map(\.id))
            XCTAssertEqual(try Data(contentsOf: downloaded.url), bytes)
            XCTAssertEqual(try Data(contentsOf: original.url), bytes)
        }
    }

    private func savedChart(style: ChartLayoutStyle, ordinal: Int) throws -> Chart {
        var chart = Chart.blank(title: "Saved \(style.rawValue) \(ordinal)", measureCount: 2, layoutStyle: style)
        let ink = drawingData()
        chart.pageHandwrittenChordData = ink
        chart.pageHandwrittenHeaderData = ink
        chart.pageHandwrittenNotationData = ink
        chart.sourcePDFLibraryItemID = UUID()
        chart.notationFont = .petaluma
        chart.typography = ChartTypographySettings(matchedSet: .finaleJazz,
            chordOverride: .museJazz, headerOverride: .petaluma, textOverride: .finaleJazz)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        chart.appendRecognizedChord(try ChordSymbolParser.parse("G/B"), rawInput: "G/B",
            to: measureID, atFraction: 0.05, sourceInkData: ink, sourceCandidateSignature: ["G/B"])
        XCTAssertEqual(try PKDrawing(data: ink).strokes.count, 1)
        XCTAssertNotNil(chart.measures.first?.chordEvents.first?.sourceInkData)
        return chart
    }

    private func drawingData() -> Data {
        let points = [CGPoint(x: 10, y: 20), CGPoint(x: 20, y: 10), CGPoint(x: 30, y: 20)]
            .enumerated().map { index, location in
                PKStrokePoint(location: location, timeOffset: Double(index) * 0.05,
                    size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
        let stroke = PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 10)))
        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }

    private final class RoundTripRepository: ChartRepository {
        private var data: Data?
        func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws { data = try JSONEncoder().encode(snapshot) }
        func loadSnapshot() throws -> ChartLibrarySnapshot? {
            try data.map { try JSONDecoder().decode(ChartLibrarySnapshot.self, from: $0) }
        }
    }
}
#endif
