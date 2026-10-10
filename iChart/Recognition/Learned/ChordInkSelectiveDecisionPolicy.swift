import Foundation

enum ChordInkSelectiveDecisionReviewReason: Equatable, Sendable {
    case calibrationUnavailable
    case selectiveAuthorityUnavailable
    case invalidDecodeScores
    case belowConfirmThreshold
}

enum ChordInkSelectiveDecisionNoReadReason: Equatable, Sendable {
    case noCandidates
    case invalidDecodeScores
    case modelPreferredNoRead
    case candidateSupportBelowReviewFloor
}

enum ChordInkSelectiveDecisionDisposition: Equatable, Sendable {
    case autoAccept(ChordNotation)
    case confirm(primary: ChordNotation, alternatives: [ChordNotation])
    case candidateReview(
        primary: ChordNotation,
        alternatives: [ChordNotation],
        reason: ChordInkSelectiveDecisionReviewReason
    )
    case noRead(ChordInkSelectiveDecisionNoReadReason)
}

struct ChordInkSelectiveCandidateEvidence: Equatable, Sendable {
    let notation: ChordNotation
    /// Binary, one-vs-rest support after independently fitted temperature
    /// scaling. Values are not renormalized across the pruned candidate list.
    let calibratedSupport: Double
}

struct ChordInkSelectiveDecisionMetrics: Equatable, Sendable {
    let candidates: [ChordInkSelectiveCandidateEvidence]
    let noReadSupport: Double
    let topCandidateSupport: Double?
    /// Top support minus the strongest observed rival, where the rival is the
    /// second decoded candidate or the no-read outcome, whichever is larger.
    let topCandidateMargin: Double?

    // Normalized entropy is intentionally absent. The decoder exposes only
    // three grammar survivors plus no-read, so entropy over that truncated set
    // would discard residual/invalid-combination mass and inflate certainty.
    // Minimum component probability is also unavailable post-decode because
    // per-head contributions are not retained in ChordInkLearnedDecodeResult.
}

struct ChordInkSelectiveDecision: Equatable, Sendable {
    let disposition: ChordInkSelectiveDecisionDisposition
    let metrics: ChordInkSelectiveDecisionMetrics?
}

/// Post-decode calibration and selective classification. This layer is pure:
/// it does not update UI, persistence, telemetry, or correction memory.
struct ChordInkSelectiveDecisionPolicy {
    func decision(
        for decodeResult: ChordInkLearnedDecodeResult,
        manifest: ChordInkModelArtifactManifest,
        calibrationArtifact: ChordInkCalibrationArtifact?,
        selectiveArtifact: ChordInkSelectiveDecisionArtifact?,
        routeDecision: ChordInkLearnedRouteDecision
    ) -> ChordInkSelectiveDecision {
        let rankedNotations = rank(decodeResult.candidates).map(\.notation)

        let calibrationResolution = ChordInkCalibrationResolution.resolve(
            artifact: calibrationArtifact,
            manifest: manifest
        )
        guard case .validated(let calibration) = calibrationResolution else {
            return fallbackDecision(
                candidates: rankedNotations,
                metrics: nil,
                reviewReason: .calibrationUnavailable
            )
        }

        let metrics: ChordInkSelectiveDecisionMetrics
        do {
            metrics = try calibratedMetrics(
                for: decodeResult,
                temperature: calibration.artifact.temperature
            )
        } catch {
            return fallbackDecision(
                candidates: rankedNotations,
                metrics: nil,
                reviewReason: .invalidDecodeScores,
                noReadReason: .invalidDecodeScores
            )
        }

        guard case .learnedCandidate(let sealedGateReceipt) = routeDecision.authority,
              routeDecision.learnedMayAffectUI,
              routeDecision.learnedMayAffectPersistence,
              let selectiveArtifact,
              (try? selectiveArtifact.validate(
                manifest: manifest,
                calibration: calibration,
                sealedGateReceipt: sealedGateReceipt
              )) != nil else {
            return fallbackDecision(
                candidates: rankedNotations,
                metrics: metrics,
                reviewReason: .selectiveAuthorityUnavailable
            )
        }

        let thresholds = selectiveArtifact.thresholds
        guard let primary = metrics.candidates.first,
              let topSupport = metrics.topCandidateSupport,
              let margin = metrics.topCandidateMargin else {
            return ChordInkSelectiveDecision(
                disposition: .noRead(.noCandidates),
                metrics: metrics
            )
        }

        if metrics.noReadSupport >= thresholds.noReadMinimumSupport,
           metrics.noReadSupport >= topSupport {
            return ChordInkSelectiveDecision(
                disposition: .noRead(.modelPreferredNoRead),
                metrics: metrics
            )
        }

        guard topSupport >= thresholds.candidateReviewMinimumTopSupport else {
            return ChordInkSelectiveDecision(
                disposition: .noRead(.candidateSupportBelowReviewFloor),
                metrics: metrics
            )
        }

        if topSupport >= thresholds.autoAcceptMinimumTopSupport,
           margin >= thresholds.autoAcceptMinimumMargin {
            return ChordInkSelectiveDecision(
                disposition: .autoAccept(primary.notation),
                metrics: metrics
            )
        }

        let alternatives = Array(metrics.candidates.dropFirst().map(\.notation))
        if topSupport >= thresholds.confirmMinimumTopSupport,
           margin >= thresholds.confirmMinimumMargin {
            return ChordInkSelectiveDecision(
                disposition: .confirm(
                    primary: primary.notation,
                    alternatives: alternatives
                ),
                metrics: metrics
            )
        }

        return ChordInkSelectiveDecision(
            disposition: .candidateReview(
                primary: primary.notation,
                alternatives: alternatives,
                reason: .belowConfirmThreshold
            ),
            metrics: metrics
        )
    }

    private func calibratedMetrics(
        for result: ChordInkLearnedDecodeResult,
        temperature: Double
    ) throws -> ChordInkSelectiveDecisionMetrics {
        guard temperature.isFinite, temperature > 0 else {
            throw CalibrationMathError.invalidTemperature
        }

        let ranked = rank(result.candidates)
        let candidates = try ranked.map { candidate in
            ChordInkSelectiveCandidateEvidence(
                notation: candidate.notation,
                calibratedSupport: try calibratedOneVsRestSupport(
                    rawJointLogProbability: candidate.rawJointLogScore,
                    temperature: temperature
                )
            )
        }
        let noReadSupport = try calibratedOneVsRestSupport(
            rawJointLogProbability: result.noReadLogScore,
            temperature: temperature
        )
        let topSupport = candidates.first?.calibratedSupport
        let rivalSupport = max(
            candidates.dropFirst().first?.calibratedSupport ?? 0,
            noReadSupport
        )

        return ChordInkSelectiveDecisionMetrics(
            candidates: candidates,
            noReadSupport: noReadSupport,
            topCandidateSupport: topSupport,
            topCandidateMargin: topSupport.map { $0 - rivalSupport }
        )
    }

    private enum CalibrationMathError: Error {
        case invalidTemperature
        case invalidLogProbability
    }

    /// Applies binary temperature scaling to the decoded path probability.
    /// This does not softmax the top-three survivors and therefore preserves
    /// the decoder's residual and grammar-pruned probability mass.
    private func calibratedOneVsRestSupport(
        rawJointLogProbability: Double,
        temperature: Double
    ) throws -> Double {
        guard rawJointLogProbability.isFinite,
              rawJointLogProbability <= 0 else {
            throw CalibrationMathError.invalidLogProbability
        }
        if rawJointLogProbability == 0 {
            return 1
        }

        let logOneMinusProbability: Double
        if rawJointLogProbability < -0.6931471805599453 {
            logOneMinusProbability = log1p(-exp(rawJointLogProbability))
        } else {
            logOneMinusProbability = log(-expm1(rawJointLogProbability))
        }
        let scaledLogit =
            (rawJointLogProbability - logOneMinusProbability) / temperature
        if scaledLogit >= 0 {
            return 1 / (1 + exp(-scaledLogit))
        }
        let exponential = exp(scaledLogit)
        return exponential / (1 + exponential)
    }

    private func rank(
        _ candidates: [ChordInkLearnedDecodedCandidate]
    ) -> [ChordInkLearnedDecodedCandidate] {
        candidates.sorted { lhs, rhs in
            if lhs.rawJointLogScore.isFinite != rhs.rawJointLogScore.isFinite {
                return lhs.rawJointLogScore.isFinite
            }
            if lhs.rawJointLogScore != rhs.rawJointLogScore {
                return lhs.rawJointLogScore > rhs.rawJointLogScore
            }
            return lhs.notation.canonicalDisplay < rhs.notation.canonicalDisplay
        }
    }

    private func fallbackDecision(
        candidates: [ChordNotation],
        metrics: ChordInkSelectiveDecisionMetrics?,
        reviewReason: ChordInkSelectiveDecisionReviewReason,
        noReadReason: ChordInkSelectiveDecisionNoReadReason = .noCandidates
    ) -> ChordInkSelectiveDecision {
        guard let primary = candidates.first else {
            return ChordInkSelectiveDecision(
                disposition: .noRead(noReadReason),
                metrics: metrics
            )
        }
        return ChordInkSelectiveDecision(
            disposition: .candidateReview(
                primary: primary,
                alternatives: Array(candidates.dropFirst()),
                reason: reviewReason
            ),
            metrics: metrics
        )
    }
}
