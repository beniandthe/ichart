import XCTest
@testable import RecognitionStudy

final class RecognitionStudyLearnedResultProviderTests: XCTestCase {
    func testConfiguredDefaultRemainsVisionWhenNoLearnedArtifactIsDeclared() {
        XCTAssertNil(
            Bundle.main.object(
                forInfoDictionaryKey:
                    RecognitionStudyResultProviderFactory.manifestNameKey
            )
        )
        XCTAssertTrue(
            RecognitionStudyResultProviderFactory.make()
                is RecognitionStudyVisionResultProvider
        )
    }

    func testLearnedOutcomeIdentityBindsVerifiedManifestBytesNotFriendlyName() {
        let runtime = NeverRuntime(
            modelIdentifier: "mutable-friendly-name",
            manifestDigest: String(repeating: "a", count: 64),
            modelDigest: String(repeating: "b", count: 64)
        )
        let provider = RecognitionStudyLearnedResultProvider(runtime: runtime)

        XCTAssertEqual(provider.recognizerID, "learned-shadow-coreml")
        XCTAssertEqual(
            provider.recognizerVersion,
            runtime.loadedArtifactIdentity.manifestArtifactSHA256
        )
        XCTAssertNotEqual(provider.recognizerVersion, runtime.manifest.modelIdentifier)
    }

    func testLearnedPresentationIsAlwaysReviewOnly() throws {
        let notation = ChordNotation.rooted(
            try ChordNotation.Rooted(
                root: ChordNotation.Pitch(letter: .c),
                extensionTone: .seven
            )
        )
        let result = RecognitionStudyLearnedResultProvider<NeverRuntime>
            .presentation(
                for: ChordInkLearnedDecodeResult(
                    candidates: [
                        ChordInkLearnedDecodedCandidate(
                            notation: notation,
                            rawJointLogScore: -0.2
                        )
                    ],
                    noReadLogScore: -2
                ),
                elapsedMilliseconds: 24.4
            )
        guard case let .review(candidate, detail) = result else {
            return XCTFail("An uncalibrated learned candidate must remain review-only.")
        }
        XCTAssertEqual(candidate, "C7")
        XCTAssertTrue(detail.contains("24 ms"))
        XCTAssertTrue(detail.contains("never auto-accepts"))
    }

    func testLearnedPresentationPreservesNoReadWhenItWins() throws {
        let notation = ChordNotation.rooted(
            try ChordNotation.Rooted(
                root: ChordNotation.Pitch(letter: .g)
            )
        )
        let result = RecognitionStudyLearnedResultProvider<NeverRuntime>
            .presentation(
                for: ChordInkLearnedDecodeResult(
                    candidates: [
                        ChordInkLearnedDecodedCandidate(
                            notation: notation,
                            rawJointLogScore: -1
                        )
                    ],
                    noReadLogScore: -0.1
                ),
                elapsedMilliseconds: 10
            )
        guard case let .noRead(detail) = result else {
            return XCTFail("The winning no-read path must not prefill a chord.")
        }
        XCTAssertTrue(detail.contains("preferred no-read"))
    }

    func testRuntimeExecutionErrorRequiresTechnicalExclusion() async throws {
        let runtime = NeverRuntime()
        let provider = RecognitionStudyLearnedResultProvider(runtime: runtime)
        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(points: [InkPoint(x: 10, y: 10, timeOffset: 0)])
        ])
        let result = await provider.result(for: packet)
        XCTAssertEqual(runtime.predictionCount, 1)
        guard case .technicalFailure = result else {
            return XCTFail("A failed model execution must not count as a no-read prediction.")
        }
        XCTAssertTrue(result.requiresTechnicalFailureExclusion)
        XCTAssertNil(result.displayText)
    }
}

private final class NeverRuntime: ChordInkLearnedModelRuntime {
    let manifest: ChordInkModelArtifactManifest
    let loadedArtifactIdentity: ChordInkLoadedModelArtifactIdentity
    private(set) var predictionCount = 0
    private enum TestError: Error { case inferenceFailed }

    init(
        modelIdentifier: String = "unused-presentation-model",
        manifestDigest: String = String(repeating: "a", count: 64),
        modelDigest: String = String(repeating: "b", count: 64)
    ) {
        manifest = ChordInkModelArtifactManifest(
            modelIdentifier: modelIdentifier,
            manifestArtifactSHA256: manifestDigest,
            modelArtifactSHA256: modelDigest,
            modelArtifactByteCount: 1,
            trainingProvenance: ChordInkTrainingProvenance(
                checkpointContractVersion: ChordInkTrainingProvenance.checkpointContractVersion,
                checkpointArtifactSHA256: String(repeating: "c", count: 64),
                checkpointArtifactByteCount: 1,
                modelArchitectureID: .dualViewV2LayoutPreserving,
                developmentRecordsSHA256: String(repeating: "d", count: 64),
                developmentSampleCount: 1,
                developmentWriterCount: 1,
                developmentSelectionAuthority: .unselectedDevelopmentTraining,
                developmentSelectionReportSHA256: nil
            )
        )
        loadedArtifactIdentity = ChordInkLoadedModelArtifactIdentity(
            manifestArtifactSHA256: manifestDigest,
            modelArtifactSHA256: modelDigest,
            modelArtifactByteCount: 1
        )
    }

    func predict(
        input: ChordInkLearnedModelInput
    ) throws -> ChordInkLearnedFactorOutput {
        predictionCount += 1
        throw TestError.inferenceFailed
    }
}
