import XCTest
@testable import iChart

final class ChordInkLearnedRouterPolicyTests: XCTestCase {
    private let policy = ChordInkLearnedRouterPolicy()

    func testLegacyProductionDoesNotExecuteOrAuthorizeLearnedOutput() {
        let decision = policy.decision(
            requestedMode: .legacyProduction,
            manifest: ChordInkLearnedTestFactory.manifest(),
            calibrationArtifact: ChordInkLearnedTestFactory.calibration(),
            sealedGateReceipt: ChordInkLearnedTestFactory.receipt()
        )

        XCTAssertEqual(decision.effectiveMode, .legacyProduction)
        XCTAssertFalse(decision.shouldExecuteLearnedRuntime)
        XCTAssertFalse(decision.learnedMayAffectUI)
        XCTAssertFalse(decision.learnedMayAffectPersistence)
        XCTAssertEqual(decision.authority, .legacy)
    }

    func testLearnedShadowIsStrictlyObservational() {
        let decision = policy.decision(
            requestedMode: .learnedShadow,
            manifest: ChordInkLearnedTestFactory.manifest(),
            calibrationArtifact: ChordInkLearnedTestFactory.calibration(),
            sealedGateReceipt: ChordInkLearnedTestFactory.receipt()
        )

        XCTAssertEqual(decision.effectiveMode, .learnedShadow)
        XCTAssertTrue(decision.shouldExecuteLearnedRuntime)
        XCTAssertFalse(decision.learnedMayAffectUI)
        XCTAssertFalse(decision.learnedMayAffectPersistence)
        XCTAssertEqual(decision.authority, .legacy)
    }

    func testCandidateWithoutCalibrationFallsBackToObservation() {
        let decision = policy.decision(
            requestedMode: .learnedCandidate,
            manifest: ChordInkLearnedTestFactory.manifest(),
            calibrationArtifact: nil,
            sealedGateReceipt: ChordInkLearnedTestFactory.receipt()
        )

        XCTAssertEqual(decision.effectiveMode, .learnedShadow)
        XCTAssertTrue(decision.shouldExecuteLearnedRuntime)
        XCTAssertFalse(decision.learnedMayAffectUI)
        XCTAssertFalse(decision.learnedMayAffectPersistence)
        XCTAssertEqual(decision.denialReason, .missingCalibration)
        XCTAssertEqual(decision.authority, .legacy)
    }

    func testCandidateWithoutSealedGateReceiptFallsBackToObservation() {
        let decision = policy.decision(
            requestedMode: .learnedCandidate,
            manifest: ChordInkLearnedTestFactory.manifest(),
            calibrationArtifact: ChordInkLearnedTestFactory.calibration(),
            sealedGateReceipt: nil
        )

        XCTAssertEqual(decision.effectiveMode, .learnedShadow)
        XCTAssertFalse(decision.learnedMayAffectUI)
        XCTAssertFalse(decision.learnedMayAffectPersistence)
        XCTAssertEqual(decision.denialReason, .missingSealedGateReceipt)
        XCTAssertEqual(decision.authority, .legacy)
    }

    func testCandidateWithFailedGateReceiptFallsBackToObservation() {
        let decision = policy.decision(
            requestedMode: .learnedCandidate,
            manifest: ChordInkLearnedTestFactory.manifest(),
            calibrationArtifact: ChordInkLearnedTestFactory.calibration(),
            sealedGateReceipt: ChordInkLearnedTestFactory.receipt(passed: false)
        )

        XCTAssertEqual(decision.effectiveMode, .learnedShadow)
        XCTAssertFalse(decision.learnedMayAffectUI)
        XCTAssertFalse(decision.learnedMayAffectPersistence)
        XCTAssertEqual(decision.denialReason, .invalidSealedGateReceipt)
        XCTAssertEqual(decision.authority, .legacy)
    }

    func testOnlyBoundPassingSealedReceiptAuthorizesLearnedUIAndPersistence() {
        let decision = policy.decision(
            requestedMode: .learnedCandidate,
            manifest: ChordInkLearnedTestFactory.manifest(),
            calibrationArtifact: ChordInkLearnedTestFactory.calibration(),
            sealedGateReceipt: ChordInkLearnedTestFactory.receipt()
        )

        XCTAssertEqual(decision.effectiveMode, .learnedCandidate)
        XCTAssertTrue(decision.shouldExecuteLearnedRuntime)
        XCTAssertTrue(decision.learnedMayAffectUI)
        XCTAssertTrue(decision.learnedMayAffectPersistence)
        XCTAssertNil(decision.denialReason)
        guard case .learnedCandidate(let receipt) = decision.authority else {
            return XCTFail("Expected learned-candidate authority")
        }
        XCTAssertEqual(receipt.receipt, ChordInkLearnedTestFactory.receipt())
    }

    func testReceiptBoundToDifferentModelCannotAuthorizeCandidate() {
        let differentDigest = String(repeating: "f", count: 64)
        let decision = policy.decision(
            requestedMode: .learnedCandidate,
            manifest: ChordInkLearnedTestFactory.manifest(),
            calibrationArtifact: ChordInkLearnedTestFactory.calibration(),
            sealedGateReceipt: ChordInkLearnedTestFactory.receipt(modelDigest: differentDigest)
        )

        XCTAssertFalse(decision.learnedMayAffectUI)
        XCTAssertFalse(decision.learnedMayAffectPersistence)
        XCTAssertEqual(decision.denialReason, .invalidSealedGateReceipt)
        XCTAssertEqual(decision.authority, .legacy)
    }
}
