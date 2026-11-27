import Foundation
import XCTest
@testable import iChart

@MainActor
final class CoordinatedProductAccessStoreTests: XCTestCase {
    func testFreshOwnerConfirmedBasicReplacesPriorProButTheSameObservationCannotAuthorizeAnotherAccount() throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        let charts = try accountBoundaryCharts(sourcePDFID: UUID())
        let priorPro = IChartSubscriptionEntitlement.activePro(accessEndsAt: Date().addingTimeInterval(3_600), verifiedAt: Date())
        for owner in [fixture.ownerA, fixture.ownerB] {
            let library = ChartLibraryStore(charts: charts,
                entitlements: AppEntitlements(subscription: priorPro, accessPolicy: .paidSubscription))
            let observation = IChartProductAccessResolver.billingForLibrary(
                subscription: .basic, verifiedOwnerID: fixture.ownerA, currentOwnerID: owner,
                currentLibraryEntitlement: library.subscriptionState)
            XCTAssertEqual(observation, owner == fixture.ownerA ? .basic : .unavailable)
            library.applySubscriptionState(observation)
            XCTAssertEqual(library.subscriptionState.status, owner == fixture.ownerA ? .basic : .unavailable)
            XCTAssertEqual(library.localChartLimit, 3)
            XCTAssertFalse(library.canCreateChart)
            XCTAssertFalse(library.canUse(.cloudBackup))
            XCTAssertFalse(library.canUse(.projects))
            XCTAssertTrue(library.canUse(.pdfExport))
            XCTAssertEqual(library.charts, charts)
        }
        XCTAssertEqual(priorPro.status, .proActive, "Applying a current observation cannot mutate prior billing evidence")
    }

    func testOfflineProcessRestartWithoutBillingOwnerProofLimitsNewCreationButKeepsSavedContentEditable() throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CoordinatedRestartContent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pdfBytes = Data("%PDF-1.7\n% synthetic offline restart fixture\n".utf8)
        let sourcePDF = root.appendingPathComponent("Saved Restart.pdf")
        try pdfBytes.write(to: sourcePDF)
        let pdfStore = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("pdf-library", isDirectory: true))
        let savedPDF = try pdfStore.save(ExportedPDF(url: sourcePDF, chartTitle: "Saved Restart",
            layoutStyle: .rhythmSectionSheet, transpositionView: .concert, chordTranspositionSemitones: 0,
            pageCount: 1, fileSizeBytes: pdfBytes.count, exportedAt: Date()), source: .personalImport)
        let savedPDFItems = pdfStore.items
        let pdfID = try XCTUnwrap(savedPDFItems.first?.id)
        var charts = try accountBoundaryCharts(sourcePDFID: pdfID)
        for index in charts.indices {
            charts[index].setNotationFont(.petaluma)
            charts[index].typography = ChartTypographySettings(matchedSet: .finaleJazz,
                chordOverride: .museJazz, headerOverride: .petaluma, textOverride: .finaleJazz)
        }
        let reopenedCharts = try JSONDecoder().decode([Chart].self, from: JSONEncoder().encode(charts))
        let ownerlessSavedBilling = IChartSubscriptionEntitlement.activePro(accessEndsAt: Date().addingTimeInterval(3_600), verifiedAt: Date())
        let library = ChartLibraryStore(charts: reopenedCharts,
            entitlements: AppEntitlements(subscription: ownerlessSavedBilling, accessPolicy: .paidSubscription))
        let resolved = IChartProductAccessResolver.billingForLibrary(subscription: .basic,
            verifiedOwnerID: nil, currentOwnerID: fixture.ownerA,
            currentLibraryEntitlement: library.subscriptionState)
        XCTAssertEqual(resolved, .unavailable, "A saved active row without current owner proof is not an offline billing grant")
        library.applySubscriptionState(resolved)
        XCTAssertEqual(library.localChartLimit, 3)
        XCTAssertFalse(library.canCreateChart)
        XCTAssertFalse(library.canUse(.projects))
        XCTAssertFalse(library.canUse(.cloudBackup))
        XCTAssertTrue(library.canUse(.pdfExport))
        XCTAssertFalse(library.entitlements.canUsePremiumFonts, "New premium font selection requires verified access")
        XCTAssertEqual(library.charts, charts)
        for original in charts {
            let binding = try XCTUnwrap(library.editorBinding(for: original.id))
            var edited = binding.wrappedValue
            edited.title += " still editable"
            binding.wrappedValue = edited
            let saved = try XCTUnwrap(library.charts.first { $0.id == original.id })
            XCTAssertEqual(saved.title, edited.title)
            XCTAssertEqual(saved.typography, original.typography)
            XCTAssertEqual(saved.notationFont, original.notationFont)
            XCTAssertEqual(saved.pageHandwrittenChordData, original.pageHandwrittenChordData)
            XCTAssertEqual(saved.measures.flatMap(\.chordEvents).map(\.sourceInkData), original.measures.flatMap(\.chordEvents).map(\.sourceInkData))
            XCTAssertEqual(saved.sourcePDFLibraryItemID, pdfID)
        }
        XCTAssertEqual(pdfStore.items, savedPDFItems)
        XCTAssertEqual(try Data(contentsOf: savedPDF.url), pdfBytes)
        XCTAssertTrue(library.deletionTombstones.isEmpty)
    }

    func testAccountSwitchClearsAPaidBillingBeforeHeldBPhaseAndNeverRestoresItOnBBillingFailure() async throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CoordinatedAccountContent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pdfBytes = Data("%PDF-1.7\n% synthetic account-boundary preservation fixture\n".utf8)
        let sourcePDF = root.appendingPathComponent("Account Boundary.pdf")
        try pdfBytes.write(to: sourcePDF)
        let pdfStore = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("pdf-library", isDirectory: true))
        let savedPDF = try pdfStore.save(ExportedPDF(url: sourcePDF, chartTitle: "Account Boundary",
            layoutStyle: .simpleChordSheet, transpositionView: .concert, chordTranspositionSemitones: 0,
            pageCount: 1, fileSizeBytes: pdfBytes.count, exportedAt: Date()), source: .personalImport)
        let pdfID = try XCTUnwrap(pdfStore.items.first?.id)
        let savedPDFItems = pdfStore.items
        let charts = try accountBoundaryCharts(sourcePDFID: pdfID)
        let project = ChartProject(title: "Saved account-boundary group", chartIDs: charts.map(\.id))
        let aBilling = IChartSubscriptionEntitlement.activePro(accessEndsAt: Date().addingTimeInterval(3_600), verifiedAt: Date())
        let library = ChartLibraryStore(charts: charts,
            entitlements: AppEntitlements(subscription: aBilling, accessPolicy: .paidSubscription),
            selectedChartID: charts.first?.id, projects: [project])
        XCTAssertTrue(library.canUse(.projects))
        XCTAssertTrue(library.canUse(.cloudBackup))
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        await fixture.store.refresh()

        fixture.store.authStateChanged(ownerID: fixture.ownerB)
        // This ordering matches the production auth callback: clear foreign
        // billing synchronously before applying B's cached or pending phase.
        library.applySubscriptionState(IChartProductAccessResolver.billingForLibrary(
            subscription: aBilling, verifiedOwnerID: fixture.ownerA, currentOwnerID: fixture.ownerB,
            currentLibraryEntitlement: library.subscriptionState))
        library.applyAccessPolicy(fixture.store.resolvedAccessPolicy)
        XCTAssertEqual(library.subscriptionState.status, .unavailable)
        XCTAssertFalse(library.canUse(.projects))
        XCTAssertFalse(library.canUse(.cloudBackup))
        XCTAssertEqual(library.localChartLimit, 3)
        let started = expectation(description: "B's phase is held while B's billing remains unresolved")
        var held: CheckedContinuation<IChartProductAccessStatus, Never>?
        fixture.service.onProductFetch = { _ in
            started.fulfill()
            return await withCheckedContinuation { held = $0 }
        }
        let bPhaseRead = Task { await fixture.store.refresh() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertFalse(library.canUse(.projects))
        XCTAssertFalse(library.canUse(.cloudBackup))
        held?.resume(returning: CoordinatedAccessTestFixture.status(owner: fixture.ownerB, phase: .paid, revision: 4))
        await bPhaseRead.value
        library.applyAccessPolicy(fixture.store.resolvedAccessPolicy)
        XCTAssertEqual(library.entitlements.accessPolicy, .paidSubscription)
        XCTAssertFalse(library.canUse(.projects), "B's fresh paid phase is not A's paid entitlement")
        XCTAssertFalse(library.canUse(.cloudBackup))
        XCTAssertEqual(library.localChartLimit, 3)
        library.applySubscriptionState(IChartProductAccessResolver.billingForLibrary(
            subscription: .unavailable, verifiedOwnerID: fixture.ownerB, currentOwnerID: fixture.ownerB,
            currentLibraryEntitlement: library.subscriptionState))
        XCTAssertFalse(library.canUse(.projects))
        XCTAssertFalse(library.canUse(.cloudBackup))
        XCTAssertEqual(library.localChartLimit, 3)
        XCTAssertFalse(library.canCreateChart)
        XCTAssertTrue(library.canUse(.pdfExport))
        XCTAssertEqual(library.charts, charts, "Auth and billing transitions must not rewrite chart/source bytes")
        XCTAssertEqual(library.projects, [project])
        XCTAssertTrue(library.deletionTombstones.isEmpty)
        for chart in charts { XCTAssertEqual(try XCTUnwrap(library.editorBinding(for: chart.id)).wrappedValue, chart) }
        XCTAssertEqual(pdfStore.items, savedPDFItems)
        XCTAssertEqual(try Data(contentsOf: savedPDF.url), pdfBytes)
        XCTAssertEqual(aBilling.status, .proActive, "Clearing account A from B's UI cannot rewrite A's billing evidence")
    }

    func testSameOwnerOfflineKeepsOwnedBillingAndSavedChartsWithoutAdmittingCheckout() async throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        await fixture.store.refresh()
        let charts = try accountBoundaryCharts(sourcePDFID: UUID())
        let ownedBilling = IChartSubscriptionEntitlement.activePro(accessEndsAt: Date().addingTimeInterval(3_600), verifiedAt: Date())
        let library = ChartLibraryStore(charts: charts,
            entitlements: AppEntitlements(subscription: ownedBilling, accessPolicy: .paidSubscription))
        fixture.store.authStateChanged(ownerID: fixture.ownerA, isOffline: true)
        library.applySubscriptionState(IChartProductAccessResolver.billingForLibrary(
            subscription: ownedBilling, verifiedOwnerID: fixture.ownerA, currentOwnerID: fixture.ownerA,
            currentLibraryEntitlement: library.subscriptionState))
        library.applyAccessPolicy(fixture.store.resolvedAccessPolicy)
        XCTAssertEqual(library.subscriptionState, ownedBilling)
        XCTAssertTrue(library.canUse(.projects))
        XCTAssertTrue(library.canUse(.cloudBackup), "Local entitlement display is retained; no offline cloud request is made")
        XCTAssertNil(library.localChartLimit)
        XCTAssertEqual(library.charts, charts)
        let admitted = await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA)
        XCTAssertFalse(admitted)
        XCTAssertFalse(fixture.store.hasFreshProductAccess)
    }

    func testForeignOrUnavailableBillingCannotRemoveDeviceLegacyLocalRightOrGrantCloudAccess() throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        let charts = try accountBoundaryCharts(sourcePDFID: UUID())
        let library = ChartLibraryStore(charts: charts,
            entitlements: AppEntitlements(subscription: .legacyLocalPro, accessPolicy: .paidSubscription))
        let aBilling = IChartSubscriptionEntitlement.activePro(accessEndsAt: Date().addingTimeInterval(3_600), verifiedAt: Date())
        for currentOwner in [Optional(fixture.ownerB), nil] {
            for candidate in [aBilling, .unavailable, .basic] {
                library.applySubscriptionState(IChartProductAccessResolver.billingForLibrary(
                    subscription: candidate, verifiedOwnerID: fixture.ownerA, currentOwnerID: currentOwner,
                    currentLibraryEntitlement: library.subscriptionState))
                XCTAssertEqual(library.subscriptionState, .legacyLocalPro)
                XCTAssertNil(library.localChartLimit)
                XCTAssertFalse(library.canUse(.cloudBackup))
                XCTAssertFalse(library.canUse(.projects))
                XCTAssertTrue(library.canUse(.documentTransposition))
                XCTAssertEqual(library.charts, charts)
            }
        }
        XCTAssertEqual(aBilling.status, .proActive)
    }

    private func accountBoundaryCharts(sourcePDFID: UUID) throws -> [Chart] {
        try [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet].flatMap { style in
            try (1...2).map { index in
                var chart = Chart.blank(title: "Account boundary \(style.rawValue) \(index)", layoutStyle: style)
                chart.sourcePDFLibraryItemID = sourcePDFID
                chart.pageHandwrittenChordData = Data("synthetic pending chord source \(index)".utf8)
                let measureID = try XCTUnwrap(chart.measures.first?.id)
                chart.appendRecognizedChord(try ChordSymbolParser.parse("Cmaj7"), rawInput: "Cmaj7",
                    to: measureID, atFraction: 0.05,
                    sourceInkData: Data("synthetic committed chord source \(index)".utf8),
                    sourceCandidateSignature: ["Cmaj7"])
                return chart
            }
        }
    }

    func testActualDefaultBuildScopeSelectsItsOwnRPCAndCannotImportAnotherLanesActivation() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        let defaultStore = IChartBetaProStore(service: fixture.service, defaults: fixture.defaults)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        defaultStore.authStateChanged(ownerID: fixture.ownerA)
        await defaultStore.refresh()

        #if ICHART_PAID_SUBSCRIPTION && !ICHART_STAGING_STOREKIT_PRODUCTS && !ICHART_LOCAL_PLAN_QA && !ICHART_LOCAL_QA_PLAN_PREVIEW
        XCTAssertTrue(defaultStore.isCoordinatedActivation)
        XCTAssertEqual(fixture.service.productRequests, [fixture.ownerA])
        XCTAssertTrue(fixture.service.legacyRequests.isEmpty)
        XCTAssertEqual(defaultStore.productAccessStatus?.phase, .paid)
        XCTAssertEqual(defaultStore.resolvedAccessPolicy, .paidSubscription)
        XCTAssertTrue(defaultStore.hasFreshProductAccess)
        #elseif ICHART_PAID_SUBSCRIPTION
        XCTAssertFalse(defaultStore.isCoordinatedActivation, "Historic staging and local QA stay in their fixed paid scope")
        XCTAssertTrue(fixture.service.productRequests.isEmpty)
        XCTAssertEqual(fixture.service.legacyRequests, [fixture.ownerA])
        XCTAssertNil(defaultStore.productAccessStatus)
        XCTAssertEqual(defaultStore.resolvedAccessPolicy, .paidSubscription)
        #else
        XCTAssertFalse(defaultStore.isCoordinatedActivation, "The ordinary free package cannot become paid through v2 data")
        XCTAssertTrue(fixture.service.productRequests.isEmpty)
        XCTAssertEqual(fixture.service.legacyRequests, [fixture.ownerA])
        XCTAssertNil(defaultStore.productAccessStatus)
        XCTAssertEqual(defaultStore.resolvedAccessPolicy, .freeAllFeatures)
        #endif
    }

    func testFixedPolicyInitialStateMatchesItsActualSignedOutAccessEvenWhenAuthIsANoOp() {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        let fixedStore = IChartBetaProStore(service: fixture.service, defaults: fixture.defaults,
                                           isCoordinatedActivation: false)
        let expected: IChartProductAccessPolicy = IChartProductAccessPolicy.current.isFreeBeta ? .betaBasic : .current
        XCTAssertFalse(fixedStore.freeProAccess)
        XCTAssertFalse(fixedStore.isAccessChecking)
        XCTAssertEqual(fixedStore.resolvedAccessPolicy, expected)
        fixedStore.authStateChanged(ownerID: nil)
        XCTAssertNil(fixedStore.ownerID)
        XCTAssertFalse(fixedStore.freeProAccess)
        XCTAssertEqual(fixedStore.resolvedAccessPolicy, expected,
                       "The initial nil-to-nil auth notification cannot correct a mismatched initializer")
    }

    func testColdAccountChecksAccessWithoutAssumingFreeOrPaidPhase() {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)

        XCTAssertTrue(fixture.store.isAccessChecking)
        XCTAssertFalse(fixture.store.hasFreshProductAccess)
        XCTAssertNil(fixture.store.productAccessStatus)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .betaBasic)
        XCTAssertTrue(fixture.service.productRequests.isEmpty)
    }

    func testFreePhaseRemainsFreeRegardlessOfExistingPaidBillingHistory() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 4)
        }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        await fixture.store.refresh()

        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
        XCTAssertEqual(fixture.store.productAccessStatus?.phase, .freeBeta)
        XCTAssertTrue(fixture.store.hasFreshProductAccess)
        XCTAssertFalse(fixture.store.isAccessChecking)
        XCTAssertEqual(fixture.service.productRequests, [fixture.ownerA])
        XCTAssertTrue(fixture.service.legacyRequests.isEmpty, "A coordinated read uses the versioned status contract")
        for billing in [IChartSubscriptionEntitlement.basic, .activePro(), .proExpired(), .unavailable] {
            let entitlements = AppEntitlements(subscription: billing, accessPolicy: fixture.store.resolvedAccessPolicy)
            XCTAssertTrue(entitlements.includes(.cloudBackup))
            XCTAssertNil(entitlements.localChartLimit)
            XCTAssertEqual(entitlements.subscription, billing, "Phase access cannot invent or replace Apple billing truth")
        }
    }

    func testVoluntaryBasicInFreePhaseKeepsSavedBillingSeparate() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 4,
                                                participating: false)
        }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        await fixture.store.refresh()

        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .betaBasic)
        let paidBilling = IChartSubscriptionEntitlement.activePro()
        let entitlements = AppEntitlements(subscription: paidBilling, accessPolicy: fixture.store.resolvedAccessPolicy)
        XCTAssertFalse(entitlements.includes(.cloudBackup))
        XCTAssertEqual(entitlements.localChartLimit, 3)
        XCTAssertEqual(entitlements.subscription, paidBilling)
    }

    func testRecognizedPaidPhaseUsesPaidPolicyWithoutMintingAnEntitlement() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 5)
        }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        await fixture.store.refresh()

        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .paidSubscription)
        XCTAssertTrue(fixture.store.hasFreshProductAccess)
        let basic = AppEntitlements(subscription: .basic, accessPolicy: fixture.store.resolvedAccessPolicy)
        XCTAssertEqual(basic.subscription, .basic)
        XCTAssertFalse(basic.includes(.cloudBackup))
        XCTAssertEqual(basic.localChartLimit, 3)
    }

    func testHigherRevisionRollbackReturnsToFreePhase() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 5)
        }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        await fixture.store.refresh()
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 6)
        }
        await fixture.store.refresh()

        XCTAssertEqual(fixture.store.productAccessStatus?.policyRevision, 6)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
        XCTAssertTrue(fixture.store.hasFreshProductAccess)
    }

    func testOlderPaidReadCannotUndoFreshHigherRevisionRollback() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        let oldReadStarted = expectation(description: "Older paid status is in flight")
        var held: CheckedContinuation<IChartProductAccessStatus, Never>?
        fixture.service.onProductFetch = { owner in
            if fixture.service.productRequests.count == 1 {
                oldReadStarted.fulfill()
                return await withCheckedContinuation { held = $0 }
            }
            return CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 11)
        }
        let olderRead = Task { await fixture.store.refresh() }
        await fulfillment(of: [oldReadStarted], timeout: 2)
        let admitted = await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA)
        XCTAssertFalse(admitted, "A fresh rollback denies checkout")
        held?.resume(returning: CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .paid, revision: 10))
        await olderRead.value

        XCTAssertEqual(fixture.service.productRequests.count, 2, "Checkout must make its own fresh read")
        XCTAssertEqual(fixture.store.productAccessStatus?.policyRevision, 11)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
        XCTAssertTrue(fixture.store.hasFreshProductAccess, "An obsolete response cannot invalidate the newer confirmed rollback")
    }

    func testOlderForegroundNetworkFailureCannotInvalidateFreshCheckoutRollbackResponse() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        let started = expectation(description: "Foreground read is held before its network failure")
        var held: CheckedContinuation<IChartProductAccessStatus, Error>?
        fixture.service.onProductFetch = { owner in
            if fixture.service.productRequests.count == 1 {
                started.fulfill()
                return try await withCheckedThrowingContinuation { held = $0 }
            }
            return CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 11)
        }
        let foreground = Task { await fixture.store.refresh() }
        await fulfillment(of: [started], timeout: 2)
        let admitted = await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA)
        XCTAssertFalse(admitted)
        held?.resume(throwing: CoordinatedAccessNetworkFailure.unavailable)
        await foreground.value

        XCTAssertEqual(fixture.service.productRequests.count, 2)
        XCTAssertEqual(fixture.store.productAccessStatus?.policyRevision, 11)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
        XCTAssertTrue(fixture.store.hasFreshProductAccess, "An older failed request cannot invalidate an intervening authenticated success")
        XCTAssertFalse(fixture.store.isAccessChecking)
        XCTAssertNil(fixture.store.accessStatusMessage)
        XCTAssertNil(fixture.store.errorMessage)
    }

    func testOlderCheckoutNetworkFailureCannotInvalidateFreshForegroundResponseOrAdmitPurchase() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        let started = expectation(description: "Checkout read is held before its network failure")
        var held: CheckedContinuation<IChartProductAccessStatus, Error>?
        fixture.service.onProductFetch = { owner in
            if fixture.service.productRequests.count == 1 {
                started.fulfill()
                return try await withCheckedThrowingContinuation { held = $0 }
            }
            return CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 11)
        }
        let admission = Task { await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA) }
        await fulfillment(of: [started], timeout: 2)
        await fixture.store.refresh()
        held?.resume(throwing: CoordinatedAccessNetworkFailure.unavailable)
        let admitted = await admission.value

        XCTAssertFalse(admitted)
        XCTAssertEqual(fixture.service.productRequests.count, 2)
        XCTAssertEqual(fixture.store.productAccessStatus?.policyRevision, 11)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
        XCTAssertTrue(fixture.store.hasFreshProductAccess)
        XCTAssertFalse(fixture.store.isAccessChecking)
        XCTAssertNil(fixture.store.accessStatusMessage)
        XCTAssertNil(fixture.store.errorMessage)
    }

    func testAToBToAAccountCycleRejectsAnObsoleteResponse() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        let started = expectation(description: "A status request started")
        var held: CheckedContinuation<IChartProductAccessStatus, Never>?
        fixture.service.onProductFetch = { _ in
            started.fulfill()
            return await withCheckedContinuation { held = $0 }
        }
        let request = Task { await fixture.store.refresh() }
        await fulfillment(of: [started], timeout: 2)
        fixture.store.authStateChanged(ownerID: fixture.ownerB)
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        held?.resume(returning: CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .paid, revision: 8))
        await request.value

        XCTAssertEqual(fixture.store.ownerID, fixture.ownerA)
        XCTAssertNil(fixture.store.productAccessStatus)
        XCTAssertFalse(fixture.store.hasFreshProductAccess)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .betaBasic)
        XCTAssertTrue(fixture.store.isAccessChecking)
    }

    func testWrongOwnerResponseCannotApplyOrPopulateAnotherOwnersCache() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { _ in
            CoordinatedAccessTestFixture.status(owner: fixture.ownerB, phase: .paid, revision: 8)
        }
        await fixture.store.refresh()

        XCTAssertNil(fixture.store.productAccessStatus)
        XCTAssertFalse(fixture.store.hasFreshProductAccess)
        let reopened = fixture.reopenedStore()
        reopened.authStateChanged(ownerID: fixture.ownerA, isOffline: true)
        XCTAssertNil(reopened.productAccessStatus)
        XCTAssertEqual(reopened.resolvedAccessPolicy, .betaBasic)
    }

    func testUnsupportedSchemaAndUnknownPhaseCannotReplaceLastConfirmedLocalRights() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 4)
        }
        await fixture.store.refresh()
        for unsupported in [
            CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .paid, revision: 5, schemaVersion: 2),
            CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .unsupported("future-phase"), revision: 6),
            CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .paid, revision: 7,
                                                policyID: "unexpected-policy-v1")
        ] {
            fixture.service.onProductFetch = { _ in unsupported }
            await fixture.store.refresh()
            XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
            XCTAssertFalse(fixture.store.hasFreshProductAccess)
            XCTAssertNotNil(fixture.store.accessStatusMessage)
        }
    }

    func testFreeBetaPhaseWithoutBetaAvailabilityCannotReplaceConfirmedLocalRights() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        await fixture.store.refresh()
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
        let now = Date()
        let misleading = IChartProductAccessStatus(
            schemaVersion: 1, ownerID: fixture.ownerA, policyID: "ichart-product-access-v1",
            phase: .freeBeta, policyRevision: 2, serverNow: now,
            policyUpdatedAt: now.addingTimeInterval(-60), betaAvailable: false,
            eligible: true, participating: true, freeProAccess: false)
        XCTAssertTrue(misleading.betaStatus.hasConsistentAccess, "The old beta formula alone cannot identify this contradictory phase")
        XCTAssertFalse(misleading.isRecognizedAndConsistent)
        fixture.service.onProductFetch = { _ in misleading }
        await fixture.store.refresh()

        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
        XCTAssertEqual(fixture.store.productAccessStatus?.policyRevision, 1)
        XCTAssertFalse(fixture.store.hasFreshProductAccess)
        XCTAssertNotNil(fixture.store.accessStatusMessage)
    }

    func testOfflineAndRestartRetainAccountScopedLocalRightsWithoutCheckoutFreshness() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 8)
        }
        await fixture.store.refresh()
        fixture.store.authStateChanged(ownerID: fixture.ownerA, isOffline: true)
        let requestsBefore = fixture.service.productRequests.count
        await fixture.store.refresh()
        let admitted = await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA)

        XCTAssertFalse(admitted)
        XCTAssertEqual(fixture.service.productRequests.count, requestsBefore)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .paidSubscription)
        XCTAssertFalse(fixture.store.hasFreshProductAccess)
        let reopened = fixture.reopenedStore()
        reopened.authStateChanged(ownerID: fixture.ownerA, isOffline: true)
        XCTAssertEqual(reopened.resolvedAccessPolicy, .paidSubscription)
        XCTAssertFalse(reopened.hasFreshProductAccess)
        reopened.authStateChanged(ownerID: fixture.ownerB, isOffline: true)
        XCTAssertNil(reopened.productAccessStatus)
        XCTAssertEqual(reopened.resolvedAccessPolicy, .betaBasic)
    }

    func testOfflineUpgradeRetainsOnlySameOwnerLegacyLocalRightsWithoutFabricatingAVersionedPhase() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        let legacy = IChartBetaProStore(service: fixture.service, defaults: fixture.defaults,
                                       isCoordinatedActivation: false)
        legacy.authStateChanged(ownerID: fixture.ownerA)
        await legacy.refresh()
        XCTAssertTrue(legacy.freeProAccess)
        let upgraded = fixture.reopenedStore()
        upgraded.authStateChanged(ownerID: fixture.ownerA, isOffline: true)
        XCTAssertEqual(upgraded.resolvedAccessPolicy, .freeAllFeatures)
        XCTAssertNil(upgraded.productAccessStatus, "A legacy local choice is not a versioned server phase")
        XCTAssertFalse(upgraded.hasFreshProductAccess)
        XCTAssertTrue(upgraded.isAccessChecking)
        XCTAssertFalse(upgraded.freeProAccess, "The v2 free grant has not been established")
        let productRequestsBefore = fixture.service.productRequests.count
        let admitted = await upgraded.authorizePaidCheckout(expectedOwnerID: fixture.ownerA)
        XCTAssertFalse(admitted)
        XCTAssertEqual(fixture.service.productRequests.count, productRequestsBefore)
        upgraded.authStateChanged(ownerID: fixture.ownerB, isOffline: true)
        XCTAssertEqual(upgraded.resolvedAccessPolicy, .betaBasic)
        XCTAssertNil(upgraded.productAccessStatus)
        upgraded.authStateChanged(ownerID: fixture.ownerA, isOffline: true)
        XCTAssertEqual(upgraded.resolvedAccessPolicy, .freeAllFeatures)
        let left = await legacy.setParticipating(false)
        XCTAssertTrue(left)
        let upgradedBasic = fixture.reopenedStore()
        upgradedBasic.authStateChanged(ownerID: fixture.ownerA, isOffline: true)
        XCTAssertEqual(upgradedBasic.resolvedAccessPolicy, .betaBasic, "A's confirmed voluntary Basic choice remains scoped to A")
        XCTAssertNil(upgradedBasic.productAccessStatus)
        XCTAssertFalse(upgradedBasic.hasFreshProductAccess)
    }

    func testCachedRevisionCannotSuppressFreshLowerRevisionServerPolicy() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 99_999)
        }
        await fixture.store.refresh()
        let reopened = fixture.reopenedStore()
        reopened.authStateChanged(ownerID: fixture.ownerA)
        XCTAssertEqual(reopened.resolvedAccessPolicy, .paidSubscription)
        XCTAssertFalse(reopened.hasFreshProductAccess, "A local cache is not authenticated freshness")
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 2)
        }
        await reopened.refresh()

        XCTAssertEqual(reopened.productAccessStatus?.policyRevision, 2)
        XCTAssertEqual(reopened.resolvedAccessPolicy, .freeAllFeatures)
        XCTAssertTrue(reopened.hasFreshProductAccess)
    }

    func testCapturedBackendContractsDecodePostgresTimestampsAcrossActivationAndRollback() throws {
        // Local synthetic PostgreSQL receipts from coordinated_paid_activation_compat.
        // Captured source-file hashes are retained here; no external file is read.
        // wire-free_beta.json SHA-256 acfccd6d76880c863867bb010afe9cad961a7c5b3b08cd2c441899dc96adaa37
        // wire-paid.json SHA-256 e2107477717343627e85cde71efe6658b58ab8349662e3d099470e78f4df9743
        // wire-rollback.json SHA-256 49159f22b7e0f33f40715ab4b43afde8b2890da4391fdf881882ca53ac608b52
        let payloads = [
            """
            {
              "phase": "free_beta",
              "eligible": true,
              "owner_id": "c1210000-0000-4000-8000-000000000001",
              "notice_id": null,
              "policy_id": "ichart-product-access-v1",
              "server_now": "2026-11-27T18:54:48.63183+00:00",
              "notice_body": null,
              "notice_title": null,
              "participating": true,
              "beta_available": true,
              "beta_ending_at": null,
              "schema_version": 1,
              "free_pro_access": true,
              "policy_revision": 1,
              "policy_updated_at": "2026-11-27T18:54:48.396572+00:00"
            }
            """,
            """
            {
              "phase": "paid",
              "eligible": true,
              "owner_id": "c1210000-0000-4000-8000-000000000001",
              "notice_id": null,
              "policy_id": "ichart-product-access-v1",
              "server_now": "2026-11-27T18:54:48.809149+00:00",
              "notice_body": null,
              "notice_title": null,
              "participating": true,
              "beta_available": false,
              "beta_ending_at": null,
              "schema_version": 1,
              "free_pro_access": false,
              "policy_revision": 2,
              "policy_updated_at": "2026-11-27T18:54:48.713138+00:00"
            }
            """,
            """
            {
              "phase": "free_beta",
              "eligible": true,
              "owner_id": "c1210000-0000-4000-8000-000000000001",
              "notice_id": null,
              "policy_id": "ichart-product-access-v1",
              "server_now": "2026-11-27T18:54:49.065044+00:00",
              "notice_body": null,
              "notice_title": null,
              "participating": true,
              "beta_available": true,
              "beta_ending_at": null,
              "schema_version": 1,
              "free_pro_access": true,
              "policy_revision": 3,
              "policy_updated_at": "2026-11-27T18:54:48.984085+00:00"
            }
            """
        ]
        let expectedServerTimes: [TimeInterval] = [1795805688.631830, 1795805688.809149, 1795805689.065044]
        for (index, payload) in payloads.enumerated() {
            let decoded = try JSONDecoder().decode(IChartProductAccessStatus.self, from: Data(payload.utf8))
            XCTAssertEqual(decoded.ownerID.uuidString.lowercased(), "c1210000-0000-4000-8000-000000000001")
            XCTAssertEqual(decoded.policyID, "ichart-product-access-v1")
            XCTAssertEqual(decoded.phase, index == 1 ? .paid : .freeBeta)
            XCTAssertEqual(decoded.policyRevision, Int64(index + 1))
            XCTAssertTrue(decoded.isRecognizedAndConsistent)
            // Foundation may keep millisecond precision, but must accept the
            // actual PostgreSQL five/six fractional digits and numeric timezone.
            XCTAssertEqual(decoded.serverNow.timeIntervalSince1970, expectedServerTimes[index], accuracy: 0.001)
            XCTAssertLessThanOrEqual(decoded.policyUpdatedAt, decoded.serverNow)
            XCTAssertEqual(IChartProductAccessResolver.resolve(status: decoded, fallback: .betaBasic),
                           index == 1 ? .paidSubscription : .freeAllFeatures)
        }
    }

    func testStatusDecodesServerISOTimestampsAndRejectsMalformedOrMissingTimes() throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        let original = CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .paid, revision: 3)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IChartProductAccessStatus.self, from: encoded)
        XCTAssertEqual(decoded.ownerID, original.ownerID)
        XCTAssertEqual(decoded.phase, original.phase)
        XCTAssertEqual(decoded.policyRevision, original.policyRevision)
        XCTAssertTrue(decoded.isRecognizedAndConsistent)
        XCTAssertLessThan(abs(decoded.serverNow.timeIntervalSince(original.serverNow)), 0.002)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for field in ["server_now", "policy_updated_at"] {
            for invalid in [NSNull(), "not-an-ISO-time", "Infinity", 1_800_000_000] as [Any] {
                var malformed = object
                malformed[field] = invalid
                XCTAssertThrowsError(try JSONDecoder().decode(IChartProductAccessStatus.self,
                    from: JSONSerialization.data(withJSONObject: malformed)))
            }
            var missing = object
            missing.removeValue(forKey: field)
            XCTAssertThrowsError(try JSONDecoder().decode(IChartProductAccessStatus.self,
                from: JSONSerialization.data(withJSONObject: missing)))
        }
        object["policy_updated_at"] = "2999-01-01T00:00:00Z"
        let impossibleOrder = try JSONDecoder().decode(IChartProductAccessStatus.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(impossibleOrder.isRecognizedAndConsistent)
    }

    func testCorruptedOrUnsupportedCachedStatusNeverAdmitsCheckout() async throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 8)
        }
        await fixture.store.refresh()
        let cacheKeys = fixture.defaults.persistentDomain(forName: fixture.suite)?.compactMap { entry in
            entry.value is Data ? entry.key : nil
        } ?? []
        XCTAssertEqual(cacheKeys.count, 1, "The isolated suite should contain one account status archive")
        let key = try XCTUnwrap(cacheKeys.first)
        let unsupported = try JSONEncoder().encode(CoordinatedAccessTestFixture.status(
            owner: fixture.ownerA, phase: .paid, revision: 9, schemaVersion: 2))
        let wrongOwner = try JSONEncoder().encode(CoordinatedAccessTestFixture.status(
            owner: fixture.ownerB, phase: .paid, revision: 10))
        for invalidCache in [Data("not-json".utf8), Data(repeating: 0x61, count: 65_537), unsupported, wrongOwner] {
            fixture.defaults.set(invalidCache, forKey: key)
            let reopened = fixture.reopenedStore()
            reopened.authStateChanged(ownerID: fixture.ownerA, isOffline: true)
            XCTAssertNil(reopened.productAccessStatus)
            XCTAssertEqual(reopened.resolvedAccessPolicy, .betaBasic)
            XCTAssertFalse(reopened.hasFreshProductAccess)
            let admitted = await reopened.authorizePaidCheckout(expectedOwnerID: fixture.ownerA)
            XCTAssertFalse(admitted)
        }
    }
}

private enum CoordinatedAccessNetworkFailure: Error { case unavailable }

@MainActor
final class CoordinatedAccessTestFixture {
    let ownerA = UUID(uuidString: "51111111-1111-4111-8111-111111111111")!
    let ownerB = UUID(uuidString: "52222222-2222-4222-8222-222222222222")!
    let suite: String
    let defaults: UserDefaults
    let service: CoordinatedAccessTestService
    let store: IChartBetaProStore

    init() {
        suite = "CoordinatedProductAccessTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        service = CoordinatedAccessTestService()
        store = IChartBetaProStore(service: service, defaults: defaults, isCoordinatedActivation: true)
    }

    func reopenedStore() -> IChartBetaProStore {
        IChartBetaProStore(service: service, defaults: defaults, isCoordinatedActivation: true)
    }

    func clean() { defaults.removePersistentDomain(forName: suite) }

    static func status(
        owner: UUID,
        phase: IChartProductAccessPhase,
        revision: Int64 = 1,
        schemaVersion: Int = 1,
        eligible: Bool = true,
        participating: Bool = true,
        policyID: String = "ichart-product-access-v1"
    ) -> IChartProductAccessStatus {
        let now = Date()
        let betaAvailable = phase == .freeBeta
        return IChartProductAccessStatus(
            schemaVersion: schemaVersion, ownerID: owner, policyID: policyID,
            phase: phase, policyRevision: revision, serverNow: now,
            policyUpdatedAt: now.addingTimeInterval(-60), betaAvailable: betaAvailable,
            eligible: eligible, participating: participating,
            freeProAccess: betaAvailable && eligible && participating
        )
    }
}

@MainActor
final class CoordinatedAccessTestService: IChartBetaProService {
    var productRequests: [UUID] = []
    var legacyRequests: [UUID] = []
    var onProductFetch: ((UUID) async throws -> IChartProductAccessStatus)?

    func fetchProductAccessStatus(for ownerID: UUID) async throws -> IChartProductAccessStatus {
        productRequests.append(ownerID)
        if let onProductFetch { return try await onProductFetch(ownerID) }
        return CoordinatedAccessTestFixture.status(owner: ownerID, phase: .freeBeta)
    }

    func fetchStatus(for ownerID: UUID) async throws -> IChartBetaProStatus {
        legacyRequests.append(ownerID)
        return IChartBetaProStatus(ownerID: ownerID, policyID: "synthetic-legacy",
                                  betaAvailable: true, eligible: true,
                                  participating: true, freeProAccess: true)
    }

    func setParticipation(_ participating: Bool, for ownerID: UUID) async throws -> IChartBetaProStatus {
        IChartBetaProStatus(ownerID: ownerID, policyID: "synthetic-legacy",
                           betaAvailable: true, eligible: true,
                           participating: participating, freeProAccess: participating)
    }
}
