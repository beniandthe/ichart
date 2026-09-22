import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyOutcomeStoreTests: XCTestCase {
    func testOutcomeRoundTripBindsCaptureAndDeclaresNoCorpusEligibility() throws {
        let capture = try sampleCapture(
            sessionID: uuid("10000000-0000-0000-0000-000000000001"),
            authorizationID: uuid("20000000-0000-0000-0000-000000000001"),
            captureID: uuid("30000000-0000-0000-0000-000000000001"),
            x: 1
        )
        let base = try RecognitionStudyBaseRecognizerOutcome(
            recognizerID: "vision-baseline",
            recognizerVersion: "vision-baseline-v1",
            disposition: .review,
            candidate: "C△7"
        )
        let outcome = try RecognitionStudySemanticOutcomeArtifact(
            packet: capture.packet,
            envelope: capture.envelope,
            promptID: "c-major-seven-natural",
            intendedChord: "C△7",
            writerConfirmationState: .asPrompted,
            baseRecognizerOutcome: base,
            clientRecordedAtUnixMilliseconds: 1_700_000_000_100
        )
        let data = try outcome.canonicalData()
        let decoded = try RecognitionStudySemanticOutcomeArtifact
            .decodeCanonicalData(data)

        XCTAssertEqual(decoded, outcome)
        XCTAssertNoThrow(
            try decoded.validateBindings(
                packet: capture.packet,
                envelope: capture.envelope
            )
        )
        XCTAssertEqual(
            outcome.dataUse,
            .localEngineeringOnlyNotCorpusEligibleV1
        )
        XCTAssertEqual(outcome.consentProvenanceStatus, .notEstablished)
        XCTAssertEqual(outcome.corpusAdjudicationStatus, .notEstablished)
        XCTAssertEqual(outcome.promptOutcome.intendedChord.rawValue, "C△7")
        XCTAssertEqual(
            outcome.promptOutcome.writerConfirmationState,
            .asPrompted
        )
        XCTAssertEqual(
            outcome.baseRecognizerOutcome.canonicalCandidate?.rawValue,
            "C△7"
        )
        XCTAssertEqual(
            outcome.adaptedRecognizerOutcome,
            .disabled
        )

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            [
                "adaptedRecognizerOutcome",
                "artifactKind",
                "authorizationID",
                "baseRecognizerOutcome",
                "captureEnvelopeSHA256",
                "clientRecordedAtUnixMilliseconds",
                "consentProvenanceStatus",
                "corpusAdjudicationStatus",
                "dataUse",
                "localCaptureID",
                "localSessionID",
                "promptOutcome",
                "schemaVersion",
                "trajectoryPacketSHA256"
            ]
        )
    }

    func testContractRejectsInvalidSemanticValuesAndPromptAssistedRepair() throws {
        XCTAssertThrowsError(
            try RecognitionStudyPromptOutcome(
                promptID: "Not Canonical",
                intendedChord: "C",
                writerConfirmationState: .asPrompted
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudyPromptOutcome(
                promptID: "c-major-seven",
                intendedChord: "Cmaj7",
                writerConfirmationState: .asPrompted
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudyBaseRecognizerOutcome(
                recognizerID: "vision-baseline",
                recognizerVersion: "v1",
                disposition: .accepted,
                candidate: "Cmaj7"
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudyBaseRecognizerOutcome(
                recognizerID: "vision-baseline",
                recognizerVersion: "v1",
                disposition: .noRead,
                candidate: "C"
            )
        )

        let review = try RecognitionStudyBaseRecognizerOutcome(
            recognizerID: "vision-baseline",
            recognizerVersion: "v1",
            disposition: .review,
            candidate: "Cmaj7"
        )
        XCTAssertEqual(review.candidate?.rawValue, "Cmaj7")
        XCTAssertNil(review.canonicalCandidate)
    }

    func testCanonicalDecoderRejectsUnknownFieldsAlternateBytesAndTampering() throws {
        let capture = try sampleCapture(
            sessionID: uuid("10000000-0000-0000-0000-000000000002"),
            authorizationID: uuid("20000000-0000-0000-0000-000000000002"),
            captureID: uuid("30000000-0000-0000-0000-00000000000a"),
            x: 2
        )
        let outcome = try sampleOutcome(capture: capture)
        let canonical = String(
            decoding: try outcome.canonicalData(),
            as: UTF8.self
        )

        XCTAssertThrowsError(
            try RecognitionStudySemanticOutcomeArtifact.decodeCanonicalData(
                Data(" \(canonical)".utf8)
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudySemanticOutcomeArtifact.decodeCanonicalData(
                Data((String(canonical.dropLast()) + ",\"unknown\":true}").utf8)
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudySemanticOutcomeArtifact.decodeCanonicalData(
                Data(
                    canonical.replacingOccurrences(
                        of: "disabled-for-study",
                        with: "enabled"
                    ).utf8
                )
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudySemanticOutcomeArtifact.decodeCanonicalData(
                Data(
                    canonical.replacingOccurrences(
                        of: capture.envelope.localCaptureID.rawValue,
                        with: capture.envelope.localCaptureID.rawValue.uppercased()
                    ).utf8
                )
            )
        )
    }

    func testStoreIsSeparateProtectedIdempotentAndReadable() async throws {
        let root = try temporaryRoot()
        let control = OutcomeStoreTestControl()
        let store = try await openStore(root: root, control: control)
        let sessionID = uuid("10000000-0000-0000-0000-000000000003")
        let first = try sampleCapture(
            sessionID: sessionID,
            authorizationID: uuid("20000000-0000-0000-0000-000000000003"),
            captureID: uuid("30000000-0000-0000-0000-000000000003"),
            x: 3
        )
        let second = try sampleCapture(
            sessionID: sessionID,
            authorizationID: uuid("20000000-0000-0000-0000-000000000004"),
            captureID: uuid("30000000-0000-0000-0000-000000000004"),
            x: 4
        )

        let stored = try await storeOutcome(store, capture: first)
        let retry = try await storeOutcome(store, capture: first)
        _ = try await storeOutcome(
            store,
            capture: second,
            recordedAt: 1_700_000_000_200
        )

        XCTAssertEqual(stored, retry)
        let loaded = try await store.outcome(
            authorizationID: first.envelope.authorizationBinding
                .authorizationID.uuid
        )
        let sessionOutcomes = try await store.outcomes(
            localSessionID: sessionID
        )
        let allOutcomes = try await store.allOutcomes()
        XCTAssertEqual(loaded, stored)
        XCTAssertEqual(sessionOutcomes.count, 2)
        XCTAssertEqual(allOutcomes.count, 2)

        let outcomeRoot = root.appendingPathComponent(
            RecognitionStudyLocalOutcomeStore.storeDirectoryName,
            isDirectory: true
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcomeRoot.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    RecognitionStudyLocalCaptureStore.storeDirectoryName,
                    isDirectory: true
                ).path
            )
        )
        let final = finalDirectory(root: root, capture: first)
        XCTAssertEqual(
            try Set(
                FileManager.default.contentsOfDirectory(atPath: final.path)
            ),
            ["commit.json", "outcome.json"]
        )
        XCTAssertTrue(
            control.requests.contains(where: { request in
                guard case let .completeFileProtection(url) = request else {
                    return false
                }
                return url.lastPathComponent == "outcome.json"
            })
        )
        XCTAssertTrue(
            control.requests.contains(where: { request in
                guard case let .excludeFromBackup(url) = request else {
                    return false
                }
                return url.lastPathComponent == "outcome.json"
            })
        )
        XCTAssertTrue(
            control.requests.contains(where: { request in
                guard case let .synchronize(url) = request else {
                    return false
                }
                return url.lastPathComponent == "outcome.json"
            })
        )

        do {
            _ = try await store.storeOutcome(
                packet: first.packet,
                envelope: first.envelope,
                promptID: "different-prompt",
                intendedChord: "D-7",
                writerConfirmationState: .executionError,
                baseRecognizerOutcome: try sampleBase(),
                clientRecordedAtUnixMilliseconds: 1_700_000_000_100
            )
            XCTFail("Authorization reuse must not overwrite an outcome.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyLocalOutcomeStoreError,
                .outcomeConflict(
                    first.envelope.authorizationBinding.authorizationID.rawValue
                )
            )
        }
    }

    func testIncompleteStageIsInvisibleAndCompleteStageRecovers() async throws {
        let incompleteRoot = try temporaryRoot()
        let incompleteControl = OutcomeStoreTestControl()
        incompleteControl.faultPoint =
            .afterStagedOutcomeVerificationBeforeCommitMarker
        let incompleteStore = try await openStore(
            root: incompleteRoot,
            control: incompleteControl
        )
        let incompleteCapture = try sampleCapture(
            sessionID: UUID(),
            authorizationID: UUID(),
            captureID: UUID(),
            x: 5
        )
        await assertInjectedFailure {
            try await self.storeOutcome(
                incompleteStore,
                capture: incompleteCapture
            )
        }
        incompleteControl.faultPoint = nil
        let incompleteOutcomes = try await incompleteStore.allOutcomes()
        XCTAssertTrue(incompleteOutcomes.isEmpty)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                atPath: quarantineDirectory(root: incompleteRoot).path
            ).isEmpty
        )

        let completeRoot = try temporaryRoot()
        let completeControl = OutcomeStoreTestControl()
        completeControl.faultPoint =
            .afterCommitMarkerSynchronizationBeforePromotion
        let interrupted = try await openStore(
            root: completeRoot,
            control: completeControl
        )
        let completeCapture = try sampleCapture(
            sessionID: UUID(),
            authorizationID: UUID(),
            captureID: UUID(),
            x: 6
        )
        await assertInjectedFailure {
            try await self.storeOutcome(
                interrupted,
                capture: completeCapture
            )
        }
        let recovered = try await openStore(root: completeRoot)
        let recoveredOutcomes = try await recovered.allOutcomes()
        XCTAssertEqual(recoveredOutcomes.count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: finalDirectory(
                    root: completeRoot,
                    capture: completeCapture
                ).path
            )
        )
    }

    func testTamperedOutcomeAndCommitAreQuarantined() async throws {
        for fileName in ["outcome.json", "commit.json"] {
            let root = try temporaryRoot()
            let store = try await openStore(root: root)
            let capture = try sampleCapture(
                sessionID: UUID(),
                authorizationID: UUID(),
                captureID: UUID(),
                x: fileName == "outcome.json" ? 7 : 8
            )
            _ = try await storeOutcome(store, capture: capture)
            let file = finalDirectory(root: root, capture: capture)
                .appendingPathComponent(fileName)
            var data = try Data(contentsOf: file)
            data.append(0x20)
            try data.write(to: file)

            let survivingOutcomes = try await store.allOutcomes()
            XCTAssertTrue(survivingOutcomes.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            XCTAssertFalse(
                try FileManager.default.contentsOfDirectory(
                    atPath: quarantineDirectory(root: root).path
                ).isEmpty
            )
        }
    }

    func testProtectedDataFailureIsRetryableWithoutQuarantine() async throws {
        let root = try temporaryRoot()
        let control = OutcomeStoreTestControl()
        let store = try await openStore(root: root, control: control)
        let capture = try sampleCapture(
            sessionID: UUID(),
            authorizationID: UUID(),
            captureID: UUID(),
            x: 9
        )
        _ = try await storeOutcome(store, capture: capture)
        control.protectedDataAvailable = false

        do {
            _ = try await store.allOutcomes()
            XCTFail("Protected-data unavailability must remain retryable.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyLocalOutcomeStoreError,
                .protectedDataUnavailable
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: finalDirectory(root: root, capture: capture).path
            )
        )
        control.protectedDataAvailable = true
        let restoredOutcomes = try await store.allOutcomes()
        XCTAssertEqual(restoredOutcomes.count, 1)
    }

    private typealias Capture = (
        packet: ChordInkCanonicalTrajectoryPacket,
        envelope: RecognitionStudyCaptureEnvelope
    )

    private func sampleCapture(
        sessionID: UUID,
        authorizationID: UUID,
        captureID: UUID,
        x: Double
    ) throws -> Capture {
        let session = try RecognitionStudySessionManifest(
            localSessionID: sessionID,
            clientCreatedAtUnixMilliseconds: 1_700_000_000_000,
            clientAppContext: RecognitionStudyClientAppContext(
                appVersion: "1.0",
                buildNumber: "100",
                operatingSystemMajorVersion: 26,
                operatingSystemMinorVersion: 0
            )
        )
        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [InkPoint(x: x, y: 2, timeOffset: 0.25)],
                creationTimeOffset: 0
            )
        ])
        let envelope = try RecognitionStudyCaptureEnvelope(
            localCaptureID: captureID,
            captureOrdinal: 0,
            authorizationBinding: try .localEngineeringDryRun(
                authorizationID: authorizationID
            ),
            sessionManifest: session,
            clientCapturedAtUnixMilliseconds: 1_700_000_000_050,
            presentedSurface: try RecognitionStudyPresentedSurface(
                presentedChartStyle: .simpleChordSheet,
                clientObservedOrientation: .portrait,
                canvasWidth: 768,
                canvasHeight: 1024,
                presentedPaceInstruction: .natural,
                presentedSizeInstruction: .normal,
                presentedConstructionInstruction: .rootFirst
            ),
            trajectoryDescriptor: try RecognitionStudyTrajectoryDescriptor(
                derivingFrom: packet
            )
        )
        return (packet, envelope)
    }

    private func sampleBase() throws -> RecognitionStudyBaseRecognizerOutcome {
        try RecognitionStudyBaseRecognizerOutcome(
            recognizerID: "vision-baseline",
            recognizerVersion: "vision-baseline-v1",
            disposition: .review,
            candidate: "C△7"
        )
    }

    private func sampleOutcome(
        capture: Capture
    ) throws -> RecognitionStudySemanticOutcomeArtifact {
        try RecognitionStudySemanticOutcomeArtifact(
            packet: capture.packet,
            envelope: capture.envelope,
            promptID: "c-major-seven-natural",
            intendedChord: "C△7",
            writerConfirmationState: .asPrompted,
            baseRecognizerOutcome: try sampleBase(),
            clientRecordedAtUnixMilliseconds: 1_700_000_000_100
        )
    }

    private func storeOutcome(
        _ store: RecognitionStudyLocalOutcomeStore,
        capture: Capture,
        recordedAt: Int64 = 1_700_000_000_100
    ) async throws -> RecognitionStudySemanticOutcomeArtifact {
        try await store.storeOutcome(
            packet: capture.packet,
            envelope: capture.envelope,
            promptID: "c-major-seven-natural",
            intendedChord: "C△7",
            writerConfirmationState: .asPrompted,
            baseRecognizerOutcome: try sampleBase(),
            clientRecordedAtUnixMilliseconds: recordedAt
        )
    }

    private func openStore(
        root: URL,
        control: OutcomeStoreTestControl = OutcomeStoreTestControl()
    ) async throws -> RecognitionStudyLocalOutcomeStore {
        try await RecognitionStudyLocalOutcomeStore.open(
            rootDirectory: root,
            hooks: RecognitionStudyLocalOutcomeStoreHooks(
                isProtectedDataAvailable: {
                    control.protectedDataAvailable
                },
                observePolicyRequest: { request in
                    control.record(request)
                },
                injectFault: { point in
                    try control.inject(point)
                }
            )
        )
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "recognition-study-outcome-tests-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func finalDirectory(root: URL, capture: Capture) -> URL {
        root.appendingPathComponent(
            RecognitionStudyLocalOutcomeStore.storeDirectoryName,
            isDirectory: true
        )
        .appendingPathComponent("outcomes", isDirectory: true)
        .appendingPathComponent(
            capture.envelope.authorizationBinding.authorizationID.rawValue,
            isDirectory: true
        )
    }

    private func quarantineDirectory(root: URL) -> URL {
        root.appendingPathComponent(
            RecognitionStudyLocalOutcomeStore.storeDirectoryName,
            isDirectory: true
        ).appendingPathComponent("quarantine", isDirectory: true)
    }

    private func assertInjectedFailure<Value>(
        operation: () async throws -> Value
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected injected crash boundary.")
        } catch {
            XCTAssertEqual(error as? OutcomeStoreInjectedFailure, .stop)
        }
    }

    private func uuid(_ string: String) -> UUID {
        UUID(uuidString: string)!
    }
}

private enum OutcomeStoreInjectedFailure: Error, Equatable {
    case stop
}

private final class OutcomeStoreTestControl: @unchecked Sendable {
    private let lock = NSLock()
    private var protectedDataAvailableStorage = true
    private var faultPointStorage: RecognitionStudyLocalOutcomeStoreFaultPoint?
    private var requestStorage: [RecognitionStudyLocalOutcomeStorePolicyRequest]
        = []

    var protectedDataAvailable: Bool {
        get { lock.withLock { protectedDataAvailableStorage } }
        set { lock.withLock { protectedDataAvailableStorage = newValue } }
    }

    var faultPoint: RecognitionStudyLocalOutcomeStoreFaultPoint? {
        get { lock.withLock { faultPointStorage } }
        set { lock.withLock { faultPointStorage = newValue } }
    }

    var requests: [RecognitionStudyLocalOutcomeStorePolicyRequest] {
        lock.withLock { requestStorage }
    }

    func record(_ request: RecognitionStudyLocalOutcomeStorePolicyRequest) {
        lock.withLock { requestStorage.append(request) }
    }

    func inject(_ point: RecognitionStudyLocalOutcomeStoreFaultPoint) throws {
        if lock.withLock({ faultPointStorage == point }) {
            throw OutcomeStoreInjectedFailure.stop
        }
    }
}
