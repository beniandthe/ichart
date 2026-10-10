import Foundation

/// Review-only adapter for a verified learned shadow artifact.
///
/// This provider deliberately has no calibrated threshold or auto-accept path.
/// It exists so a frozen candidate can be exercised on physical iPad hardware
/// before promotion, while the Study outcome keeps the artifact identity and
/// version separate from the Apple Vision baseline.
struct RecognitionStudyLearnedResultProvider<Runtime: ChordInkLearnedModelRuntime>:
    RecognitionStudyLocalResultProviding,
    @unchecked Sendable
{
    let runtime: Runtime

    let recognizerID = "learned-shadow-coreml"
    /// The detached manifest digest binds the exact manifest bytes, compiled
    /// model fingerprint, interface, and export-parity evidence. A mutable
    /// human-facing model identifier is not sufficient outcome provenance.
    var recognizerVersion: String {
        runtime.loadedArtifactIdentity.manifestArtifactSHA256
    }

    func result(
        for packet: ChordInkCanonicalTrajectoryPacket
    ) async -> RecognitionStudyLocalResult {
        do {
            let clock = ContinuousClock()
            let started = clock.now
            let input = ChordInkLearnedModelInput(
                trajectory: try ChordInkTrajectoryFeatureEncoder.encode(packet),
                raster: try ChordInkRasterizer.rasterize(packet)
            )
            let decoded = try ChordInkLearnedInferenceEngine().predict(
                input: input,
                runtime: runtime,
                maximumCandidateCount: 3
            )
            let elapsed = started.duration(to: clock.now).components
            let elapsedMilliseconds =
                (Double(elapsed.seconds) * 1_000)
                + (Double(elapsed.attoseconds) / 1_000_000_000_000_000)
            return Self.presentation(
                for: decoded,
                elapsedMilliseconds: elapsedMilliseconds
            )
        } catch {
            return .technicalFailure(
                detail: "The verified learned shadow could not process this ink. Nothing was accepted."
            )
        }
    }

    static func presentation(
        for decoded: ChordInkLearnedDecodeResult,
        elapsedMilliseconds: Double
    ) -> RecognitionStudyLocalResult {
        let elapsedText = String(format: "%.0f ms", elapsedMilliseconds)
        guard let candidate = decoded.candidates.first,
              candidate.rawJointLogScore > decoded.noReadLogScore else {
            return .noRead(
                detail: "Uncalibrated learned shadow preferred no-read (\(elapsedText)). Nothing was accepted."
            )
        }
        return .review(
            candidate: candidate.notation.canonicalDisplay,
            detail: "Uncalibrated learned shadow candidate (\(elapsedText)). Review only; this build never auto-accepts it."
        )
    }
}

struct RecognitionStudyUnavailableResultProvider:
    RecognitionStudyLocalResultProviding
{
    let recognizerID = "learned-shadow-configuration-invalid"
    let recognizerVersion = "learned-shadow-configuration-invalid-v1"

    func result(
        for packet: ChordInkCanonicalTrajectoryPacket
    ) async -> RecognitionStudyLocalResult {
        .technicalFailure(
            detail: "The learned shadow was configured but its complete verified artifact was unavailable. Vision fallback is disabled for this pass."
        )
    }
}

enum RecognitionStudyResultProviderFactory {
    static let manifestNameKey = "RecognitionStudyLearnedManifestName"
    static let compiledModelNameKey = "RecognitionStudyLearnedModelName"
    static let detachedManifestSHA256Key =
        "RecognitionStudyLearnedDetachedManifestSHA256"

    static func make(
        bundle: Bundle = .main
    ) -> any RecognitionStudyLocalResultProviding {
        let manifestName = configuredString(manifestNameKey, bundle: bundle)
        let compiledModelName = configuredString(
            compiledModelNameKey,
            bundle: bundle
        )
        let detachedDigest = configuredString(
            detachedManifestSHA256Key,
            bundle: bundle
        )
        let supplied = [manifestName, compiledModelName, detachedDigest]
            .compactMap { $0 }
        guard !supplied.isEmpty else {
            return RecognitionStudyVisionResultProvider()
        }
        guard let manifestName,
              let compiledModelName,
              let detachedDigest,
              ChordInkArtifactDigest.isCanonicalSHA256(detachedDigest) else {
            return RecognitionStudyUnavailableResultProvider()
        }
        do {
            let runtime = try ChordInkCoreMLModelRuntime.load(
                resources: .init(
                    manifestName: manifestName,
                    compiledModelName: compiledModelName
                ),
                detachedManifestSHA256: detachedDigest,
                bundle: bundle
            )
            return RecognitionStudyLearnedResultProvider(runtime: runtime)
        } catch {
            // A partially configured or unverifiable learned pass must not
            // silently become a Vision pass; that would corrupt comparison
            // provenance while appearing to work.
            return RecognitionStudyUnavailableResultProvider()
        }
    }

    private static func configuredString(
        _ key: String,
        bundle: Bundle
    ) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
