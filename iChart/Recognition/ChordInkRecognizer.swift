import Foundation

enum ChordInkRecognitionPipelineIdentity {
    /// Bump whenever a device trace or committed ink chord must be
    /// distinguishable from a materially different recognition pipeline.
    static let version = "maximum-trust-v16-2026-09-12"
}

protocol ChordInkRecognizing {
    func recognize(
        strokes: [InkStroke],
        options: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult
}

extension ChordInkRecognizing {
    func recognize(strokes: [InkStroke]) -> ChordInkRecognitionResult {
        recognize(strokes: strokes, options: .live)
    }
}

struct ChordInkRecognizer: ChordInkRecognizing {
    var clusterer: StrokeClusterer
    var glyphRecognizer: GestureTemplateRecognizer
    var candidateComposer: ChordInkCandidateComposer
    var semanticCandidateComposer: ChordInkSemanticCandidateComposer
    var semanticGlyphContextualizer: ChordInkSemanticGlyphContextualizer
    var symbolLedger: ChordInkSymbolLedger
    var templates: [GestureTemplate]
    var maxGlyphCandidatesPerCluster: Int
    var minimumAcceptedCandidateConfidence: Double
    var normalizesOversizedInput: Bool

    init(
        clusterer: StrokeClusterer = StrokeClusterer(),
        glyphRecognizer: GestureTemplateRecognizer = GestureTemplateRecognizer(),
        candidateComposer: ChordInkCandidateComposer = ChordInkCandidateComposer(),
        semanticCandidateComposer: ChordInkSemanticCandidateComposer = ChordInkSemanticCandidateComposer(),
        semanticGlyphContextualizer: ChordInkSemanticGlyphContextualizer = ChordInkSemanticGlyphContextualizer(),
        symbolLedger: ChordInkSymbolLedger = ChordInkSymbolLedger(),
        templates: [GestureTemplate] = ChordGlyphTemplateLibrary.initialTemplates,
        maxGlyphCandidatesPerCluster: Int = 8,
        minimumAcceptedCandidateConfidence: Double = 3.70,
        normalizesOversizedInput: Bool = false
    ) {
        self.clusterer = clusterer
        self.glyphRecognizer = glyphRecognizer
        self.candidateComposer = candidateComposer
        self.semanticCandidateComposer = semanticCandidateComposer
        self.semanticGlyphContextualizer = semanticGlyphContextualizer
        self.symbolLedger = symbolLedger
        self.templates = templates
        self.maxGlyphCandidatesPerCluster = maxGlyphCandidatesPerCluster
        self.minimumAcceptedCandidateConfidence = minimumAcceptedCandidateConfidence
        self.normalizesOversizedInput = normalizesOversizedInput
    }

    func recognize(
        strokes: [InkStroke],
        options: ChordInkRecognitionOptions = .live
    ) -> ChordInkRecognitionResult {
        let recognitionStart = Date()
        let recognitionStrokes = normalizesOversizedInput
            ? ChordInkRecognitionScaleNormalizer.strokes(from: strokes)
            : strokes
        // Cross-stroke chronology belongs to ChordInkSequentialGrouper, which
        // has already established that these paths form one chord. Reapplying
        // a short glyph-level time-gap cutoff here can tear a deliberately
        // written multi-stroke sharp (or another constructed glyph) apart when
        // the musician pauses between its lines. Preserve geometry and local
        // point timing, but remove the drawing-wide creation clock for glyph
        // clustering inside the completed chord.
        let glyphClusteringStrokes = recognitionStrokes.map { stroke in
            InkStroke(
                points: stroke.points,
                bounds: stroke.bounds,
                creationTimeOffset: nil
            )
        }
        let clusterStart = Date()
        let clusters = clusterer.cluster(glyphClusteringStrokes)
        let clusterMilliseconds = Self.elapsedMilliseconds(since: clusterStart)

        let glyphStart = Date()
        let glyphCandidateGroups = clusters.map { cluster in
            glyphRecognizer.rankedCandidates(
                for: cluster,
                templates: templates,
                limit: maxGlyphCandidatesPerCluster
            )
        }
        let glyphMilliseconds = Self.elapsedMilliseconds(since: glyphStart)

        let contextStart = Date()
        let contextualGlyphCandidateGroups = semanticGlyphContextualizer.contextualizedGlyphCandidateGroups(
            glyphCandidateGroups,
            clusters: clusters
        )
        let contextualGlyphMilliseconds = Self.elapsedMilliseconds(since: contextStart)

        let recognitionCandidateComposer = ChordInkRecognitionCandidateComposer(
            baseComposer: candidateComposer,
            semanticCandidateComposer: semanticCandidateComposer
        )
        let candidateResult = recognitionCandidateComposer.composeRecognitionCandidates(
            from: contextualGlyphCandidateGroups,
            clusters: clusters
        )
        let chordRepeatCandidate = ChordRepeatInkDetector.candidate(from: recognitionStrokes)
        let chordCandidates: [ChordInkCandidate]
        if let chordRepeatCandidate {
            chordCandidates = [chordRepeatCandidate] + candidateResult.candidates.filter {
                $0.text != chordRepeatCandidate.text
            }
        } else {
            chordCandidates = candidateResult.candidates
        }
        let rawCandidates = chordCandidates.map(\.text)
        let symbolLedgerSnapshot = options.includesSymbolLedgerDiagnostics
            ? symbolLedger.snapshot(
                glyphCandidateGroups: contextualGlyphCandidateGroups,
                clusters: clusters,
                chordCandidates: chordCandidates
            )
            : nil

        let matchStart = Date()
        let minimumScoredCandidateConfidence = minimumAcceptedCandidateConfidence
            - ChordInkRecognitionPolicy.closeRaceConfidenceGap
        var matchCache: [String: ChordRecognitionMatch] = [:]
        var unmatchedCandidateTexts = Set<String>()
        func cachedMatch(_ text: String) -> ChordRecognitionMatch? {
            if let match = matchCache[text] {
                return match
            }
            if unmatchedCandidateTexts.contains(text) {
                return nil
            }

            guard let match = ChordRecognitionCompendium.match(text) else {
                unmatchedCandidateTexts.insert(text)
                return nil
            }

            matchCache[text] = match
            return match
        }

        let acceptedCandidate = chordCandidates.lazy.compactMap { candidate -> (ChordRecognitionMatch, Double, [GlyphCandidate])? in
            guard let match = cachedMatch(candidate.text),
                  candidate.confidence >= minimumAcceptedCandidateConfidence else {
                return nil
            }

            return (match, candidate.confidence, candidate.glyphCandidates)
        }.first
        let candidateScores = Self.candidateScores(
            from: chordCandidates,
            minimumConfidence: minimumScoredCandidateConfidence,
            match: cachedMatch
        )
        let reviewCandidateScores = acceptedCandidate == nil
            ? Self.reviewCandidateScores(
                from: chordCandidates,
                minimumConfidence: minimumAcceptedCandidateConfidence - 0.40,
                excluding: candidateScores,
                match: cachedMatch
            )
            : []
        let match = acceptedCandidate?.0
        let acceptedConfidence = acceptedCandidate?.1 ?? 0
        let matchMilliseconds = Self.elapsedMilliseconds(since: matchStart)
        let symbolLedgerAssessment = symbolLedgerSnapshot?.assessment(
            primaryDisplayText: match?.displayText
        )

        return ChordInkRecognitionResult(
            rawCandidates: rawCandidates,
            glyphCandidates: contextualGlyphCandidateGroups,
            match: match,
            confidence: acceptedConfidence,
            acceptedGlyphCandidates: acceptedCandidate?.2 ?? [],
            candidateScores: candidateScores,
            reviewCandidateScores: reviewCandidateScores,
            symbolLedger: symbolLedgerSnapshot,
            symbolLedgerAssessment: symbolLedgerAssessment,
            metrics: ChordInkRecognitionMetrics(
                clusterMilliseconds: clusterMilliseconds,
                glyphMilliseconds: glyphMilliseconds,
                contextualGlyphMilliseconds: contextualGlyphMilliseconds,
                composeMilliseconds: candidateResult.composeMilliseconds,
                semanticMilliseconds: candidateResult.semanticMilliseconds,
                matchMilliseconds: matchMilliseconds,
                totalMilliseconds: Self.elapsedMilliseconds(since: recognitionStart),
                strokeCount: strokes.count,
                clusterCount: clusters.count,
                glyphCandidateColumnCount: contextualGlyphCandidateGroups.count,
                semanticCandidateCount: candidateResult.semanticCandidateCount + (chordRepeatCandidate == nil ? 0 : 1),
                rawCandidateCount: rawCandidates.count,
                compositionMetrics: candidateResult.compositionMetrics
            )
        )
    }

    private static func elapsedMilliseconds(since start: Date) -> Double {
        Date().timeIntervalSince(start) * 1_000
    }

    static func candidateScores(
        from chordCandidates: [ChordInkCandidate],
        minimumConfidence: Double,
        match: (String) -> ChordRecognitionMatch?
    ) -> [ChordInkCandidateScore] {
        let rawScorePrefixCount = 8
        let supportedScoreTargetCount = 12
        var scores: [ChordInkCandidateScore] = []
        var scoredCandidateTexts = Set<String>()
        var supportedDisplayTexts = Set<String>()

        func appendScore(
            for candidate: ChordInkCandidate,
            match: ChordRecognitionMatch?,
            requiredConfidence: Double
        ) {
            guard candidate.confidence >= requiredConfidence,
                  !scoredCandidateTexts.contains(candidate.text) else {
                return
            }

            let displayText = match?.displayText
            scores.append(
                ChordInkCandidateScore(
                    text: candidate.text,
                    displayText: displayText,
                    confidence: candidate.confidence
                )
            )
            scoredCandidateTexts.insert(candidate.text)

            if let displayText {
                supportedDisplayTexts.insert(displayText)
            }
        }

        for candidate in chordCandidates.prefix(rawScorePrefixCount) {
            appendScore(
                for: candidate,
                match: match(candidate.text),
                requiredConfidence: minimumConfidence
            )
        }

        for candidate in chordCandidates.dropFirst(rawScorePrefixCount) {
            guard candidate.confidence >= minimumConfidence,
                  let supportedMatch = match(candidate.text),
                  !supportedDisplayTexts.contains(supportedMatch.displayText) else {
                continue
            }

            appendScore(
                for: candidate,
                match: supportedMatch,
                requiredConfidence: minimumConfidence
            )
            if supportedDisplayTexts.count >= supportedScoreTargetCount {
                break
            }
        }

        return scores
    }

    /// A below-threshold candidate is never recognition evidence, but a small
    /// set of grammar-supported alternatives can still spare the musician from
    /// retyping during explicit review. Keeping these scores in a separate
    /// field prevents recovery UI from changing the automatic trust decision.
    static func reviewCandidateScores(
        from chordCandidates: [ChordInkCandidate],
        minimumConfidence: Double,
        excluding primaryScores: [ChordInkCandidateScore],
        match: (String) -> ChordRecognitionMatch?
    ) -> [ChordInkCandidateScore] {
        let maximumReviewCandidateCount = 4
        var excludedDisplayTexts = Set(primaryScores.compactMap(\.displayText))
        var scoredCandidateTexts = Set<String>()
        var scores: [ChordInkCandidateScore] = []

        for candidate in chordCandidates {
            guard candidate.confidence >= minimumConfidence,
                  scoredCandidateTexts.insert(candidate.text).inserted,
                  let supportedMatch = match(candidate.text),
                  excludedDisplayTexts.insert(supportedMatch.displayText).inserted else {
                continue
            }

            scores.append(
                ChordInkCandidateScore(
                    text: candidate.text,
                    displayText: supportedMatch.displayText,
                    confidence: candidate.confidence
                )
            )
            if scores.count >= maximumReviewCandidateCount {
                break
            }
        }

        return scores
    }
}

/// The glyph heuristics intentionally use physical-size bounds to distinguish
/// dots, accidentals, roots, and wrapper marks. Pencil zoom and page layout can
/// otherwise enlarge the exact same chord beyond those calibrated bounds.
/// Uniformly cap only oversized groups at the corpus median height; smaller
/// handwriting is left untouched and temporal metadata is preserved.
enum ChordInkRecognitionScaleNormalizer {
    static let maximumUnscaledHeight = 48.0
    static let normalizedHeight = 40.0
    static let recoveryHeights = [32.0, 36.0, 39.5, 44.0, 48.0]
    /// Far below PencilKit's useful spatial resolution, but large enough to
    /// remove floating-point residue introduced by a recovery scale transform.
    private static let coordinateQuantum = 0.000_001

    static func strokes(from strokes: [InkStroke]) -> [InkStroke] {
        guard !strokes.isEmpty else {
            return strokes
        }

        let bounds = InkBounds.enclosing(strokes.map(\.bounds))
        guard bounds.height > maximumUnscaledHeight else {
            return strokes
        }

        return Self.strokes(from: strokes, targetHeight: normalizedHeight)
    }

    static func strokes(
        from strokes: [InkStroke],
        targetHeight: Double
    ) -> [InkStroke] {
        guard !strokes.isEmpty, targetHeight > 0 else {
            return strokes
        }

        let bounds = InkBounds.enclosing(strokes.map(\.bounds))
        guard bounds.height > 0,
              abs(bounds.height - targetHeight) > 0.0001 else {
            return strokes
        }

        let scale = targetHeight / bounds.height
        return strokes.map { stroke in
            InkStroke(
                points: stroke.points.map { point in
                    InkPoint(
                        x: stableCoordinate(
                            bounds.minX + (point.x - bounds.minX) * scale
                        ),
                        y: stableCoordinate(
                            bounds.minY + (point.y - bounds.minY) * scale
                        ),
                        timeOffset: point.timeOffset
                    )
                },
                creationTimeOffset: stroke.creationTimeOffset
            )
        }
    }

    private static func stableCoordinate(_ value: Double) -> Double {
        (value / coordinateQuantum).rounded() * coordinateQuantum
    }
}

/// Adds a reject option to the existing recognizer. A candidate that the base
/// policy considers trusted must also have corroborating symbol-ledger support
/// and remain the same trusted read under small scale and rotation changes.
/// Unstable results remain available as suggestions but require confirmation.
struct ChordInkMaximumTrustRecognizer: ChordInkRecognizing {
    private enum Probe: CaseIterable {
        case normalizedPointDensity
        case scaledDown
        case rotatedCounterclockwise
        case rotatedClockwise

        var failureOutcome: ChordInkTrustEvidenceOutcome {
            switch self {
            case .normalizedPointDensity:
                return .unstableUnderPointDensity
            case .scaledDown:
                return .unstableUnderScale
            case .rotatedCounterclockwise:
                return .unstableUnderCounterclockwiseRotation
            case .rotatedClockwise:
                return .unstableUnderClockwiseRotation
            }
        }
    }

    private struct ProbeValidation {
        var failureOutcome: ChordInkTrustEvidenceOutcome?
        var completedProbeCount: Int
    }

    private let baseRecognizer: any ChordInkRecognizing
    private let minimumSymbolSupportCount: Int
    private let scaleRecoveryRecognizer: ChordInkRecognizer?
    private let validatesProbesConcurrently: Bool

    init(
        minimumSymbolSupportCount: Int = 2
    ) {
        // The user's actual Pencil geometry is the primary evidence. Alternate
        // canonical sizes are recovery suggestions for uncertain reads; they
        // must not silently replace a stronger semantic read at the written
        // size (as happened to an entire captured device row).
        self.baseRecognizer = ChordInkRecognizer(
            normalizesOversizedInput: false
        )
        self.minimumSymbolSupportCount = minimumSymbolSupportCount
        self.scaleRecoveryRecognizer = ChordInkRecognizer(
            normalizesOversizedInput: false
        )
        self.validatesProbesConcurrently = true
    }

    init(
        baseRecognizer: any ChordInkRecognizing,
        minimumSymbolSupportCount: Int = 2
    ) {
        self.baseRecognizer = baseRecognizer
        self.minimumSymbolSupportCount = minimumSymbolSupportCount
        self.scaleRecoveryRecognizer = nil
        // Injected recognizers are frequently stateful test doubles and have
        // no Sendable contract. Keep their calls serial while the production
        // value recognizer can evaluate independent trust probes in parallel.
        self.validatesProbesConcurrently = false
    }

    func recognize(
        strokes: [InkStroke],
        options: ChordInkRecognitionOptions = .live
    ) -> ChordInkRecognitionResult {
        var evidenceOptions = options
        evidenceOptions.includesSymbolLedgerDiagnostics = true
        var result = baseRecognizer.recognize(
            strokes: strokes,
            options: evidenceOptions
        )

        let preliminaryDecision = ChordInkRecognitionPolicy.decision(for: result)
        let validationStartedAt = ProcessInfo.processInfo.systemUptime
        let symbolSupportCount = result.symbolLedgerAssessment?.supportCount ?? 0
        if requiresCapturedHandwritingEvidence(result.match?.symbol) {
            result.trustEvidence = evidence(
                outcome: .insufficientCapturedFamilyEvidence,
                symbolSupportCount: symbolSupportCount,
                completedProbeCount: 0,
                startedAt: validationStartedAt
            )
            result.metrics.totalMilliseconds += result.trustEvidence?.validationMilliseconds ?? 0
            return finalized(result, strokes: strokes, options: options)
        }

        guard preliminaryDecision.action == .trusted,
              let acceptedText = preliminaryDecision.acceptedText else {
            return finalized(result, strokes: strokes, options: options)
        }

        guard symbolSupportCount >= minimumSymbolSupportCount else {
            result.trustEvidence = evidence(
                outcome: .insufficientSymbolEvidence,
                symbolSupportCount: symbolSupportCount,
                completedProbeCount: 0,
                startedAt: validationStartedAt
            )
            result.metrics.totalMilliseconds += result.trustEvidence?.validationMilliseconds ?? 0
            return finalized(result, strokes: strokes, options: options)
        }

        if hasImplausiblePlainRootGeometry(result: result, strokes: strokes) {
            result.trustEvidence = evidence(
                outcome: .implausibleRootGeometry,
                symbolSupportCount: symbolSupportCount,
                completedProbeCount: 0,
                startedAt: validationStartedAt
            )
            result.metrics.totalMilliseconds += result.trustEvidence?.validationMilliseconds ?? 0
            return finalized(result, strokes: strokes, options: options)
        }

        if let outcome = sevenNineTrustConflict(
            result: result,
            strokes: strokes
        ) {
            result.trustEvidence = evidence(
                outcome: outcome,
                symbolSupportCount: symbolSupportCount,
                completedProbeCount: 0,
                startedAt: validationStartedAt
            )
            result.metrics.totalMilliseconds += result.trustEvidence?.validationMilliseconds ?? 0
            return finalized(result, strokes: strokes, options: options)
        }

        if let outcome = semanticAmbiguityTrustConflict(result: result) {
            result.trustEvidence = evidence(
                outcome: outcome,
                symbolSupportCount: symbolSupportCount,
                completedProbeCount: 0,
                startedAt: validationStartedAt
            )
            result.metrics.totalMilliseconds += result.trustEvidence?.validationMilliseconds ?? 0
            return finalized(result, strokes: strokes, options: options)
        }

        if hasStrongCompetingAlterationEvidence(result) {
            result.trustEvidence = evidence(
                outcome: .conflictingAlterationEvidence,
                symbolSupportCount: symbolSupportCount,
                completedProbeCount: 0,
                startedAt: validationStartedAt
            )
            result.metrics.totalMilliseconds += result.trustEvidence?.validationMilliseconds ?? 0
            return finalized(result, strokes: strokes, options: options)
        }

        if hasStrongCompetingQualityEvidence(result) {
            result.trustEvidence = evidence(
                outcome: .conflictingQualityEvidence,
                symbolSupportCount: symbolSupportCount,
                completedProbeCount: 0,
                startedAt: validationStartedAt
            )
            result.metrics.totalMilliseconds += result.trustEvidence?.validationMilliseconds ?? 0
            return finalized(result, strokes: strokes, options: options)
        }

        let probeValidation = validateTrustProbes(
            strokes: strokes,
            acceptedText: acceptedText
        )
        if let failureOutcome = probeValidation.failureOutcome {
            result.trustEvidence = evidence(
                outcome: failureOutcome,
                symbolSupportCount: symbolSupportCount,
                completedProbeCount: probeValidation.completedProbeCount,
                startedAt: validationStartedAt
            )
            result.metrics.totalMilliseconds += result.trustEvidence?.validationMilliseconds ?? 0
            return finalized(result, strokes: strokes, options: options)
        }

        result.trustEvidence = evidence(
            outcome: .corroborated,
            symbolSupportCount: symbolSupportCount,
            completedProbeCount: probeValidation.completedProbeCount,
            startedAt: validationStartedAt
        )
        result.metrics.totalMilliseconds += result.trustEvidence?.validationMilliseconds ?? 0
        return finalized(result, strokes: strokes, options: options)
    }

    /// Robustness probes are independent, read-only recognitions. Evaluating
    /// them concurrently removes their serial wall-clock penalty without
    /// changing the probes, candidate search, or the ordered reason reported
    /// for the first failure. This method remains synchronous to preserve the
    /// recognizer protocol and the existing off-main recognition session.
    private func validateTrustProbes(
        strokes: [InkStroke],
        acceptedText: String
    ) -> ProbeValidation {
        let probes = Probe.allCases
        guard validatesProbesConcurrently,
              probes.count > 1,
              ProcessInfo.processInfo.activeProcessorCount > 1 else {
            for (index, probe) in probes.enumerated() {
                let result = baseRecognizer.recognize(
                    strokes: transformed(strokes, for: probe),
                    options: .live
                )
                let decision = ChordInkRecognitionPolicy.decision(for: result)
                guard decision.action == .trusted,
                      decision.acceptedText == acceptedText else {
                    return ProbeValidation(
                        failureOutcome: probe.failureOutcome,
                        completedProbeCount: index + 1
                    )
                }
            }
            return ProbeValidation(
                failureOutcome: nil,
                completedProbeCount: probes.count
            )
        }

        let resultLock = NSLock()
        var results = Array<ChordInkRecognitionResult?>(
            repeating: nil,
            count: probes.count
        )
        DispatchQueue.concurrentPerform(iterations: probes.count) { index in
            let result = baseRecognizer.recognize(
                strokes: transformed(strokes, for: probes[index]),
                options: .live
            )
            resultLock.lock()
            results[index] = result
            resultLock.unlock()
        }

        // concurrentPerform is synchronous, so every slot must be populated.
        // The fallback is defensive and retains the exact probe if that
        // contract ever changes.
        for (index, probe) in probes.enumerated() {
            let result = results[index] ?? baseRecognizer.recognize(
                strokes: transformed(strokes, for: probes[index]),
                options: .live
            )
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            guard decision.action == .trusted,
                  decision.acceptedText == acceptedText else {
                return ProbeValidation(
                    failureOutcome: probe.failureOutcome,
                    completedProbeCount: index + 1
                )
            }
        }
        return ProbeValidation(
            failureOutcome: nil,
            completedProbeCount: probes.count
        )
    }

    /// The parser intentionally accepts more chord vocabulary than the retained
    /// real-ink archive currently proves. These forms may be offered as useful
    /// suggestions, but they cannot silently render until representative Pencil
    /// captures have exercised their complete handwritten glyph sequence.
    private func requiresCapturedHandwritingEvidence(_ symbol: ChordSymbol?) -> Bool {
        guard let symbol,
              symbol.kind == .rooted else {
            return false
        }

        if symbol.quality == "add"
            || symbol.extensions == ["6", "9"]
            || (symbol.quality == "sus"
                && (symbol.extensions == ["2"] || symbol.extensions == ["9"]))
            || (symbol.quality == "-△" && symbol.extensions == ["9"]) {
            return true
        }

        return symbol.slashBass != nil
            && (!symbol.quality.isEmpty
                || !symbol.extensions.isEmpty
                || !symbol.alterations.isEmpty)
    }

    private func finalized(
        _ result: ChordInkRecognitionResult,
        strokes: [InkStroke],
        options: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult {
        let augmentedResult: ChordInkRecognitionResult
        if ChordInkRecognitionPolicy.decision(for: result).action == .confirm {
            augmentedResult = addingScaleRecoverySuggestions(
                to: result,
                strokes: strokes
            )
        } else {
            augmentedResult = result
        }

        return hidingInternalLedgerIfNeeded(augmentedResult, options: options)
    }

    /// Page zoom and layout changes can present identical Pencil strokes at a
    /// different absolute size. If the primary read already needs confirmation,
    /// audit a small set of retained-corpus sizes and expose their supported
    /// reads as suggestions. Alternate scales never replace or auto-trust the
    /// primary answer; they only make an uncertain read recoverable.
    private func addingScaleRecoverySuggestions(
        to result: ChordInkRecognitionResult,
        strokes: [InkStroke]
    ) -> ChordInkRecognitionResult {
        guard let scaleRecoveryRecognizer else {
            return result
        }

        let bounds = InkBounds.enclosing(strokes.map(\.bounds))
        // Compact completed chords can also hit absolute-size glyph floors.
        // Recover only a root-led, multi-glyph no-read, never a standalone
        // scribble or an already-supported compact primary. The half-height
        // floor bounds enlargement to 2x at the largest recovery size. All
        // recovered scores remain review-only; primary and trust stay intact.
        let compactRootLedNoRead = result.match == nil
            && bounds.height >= ChordInkRecognitionScaleNormalizer.maximumUnscaledHeight * 0.50
            && result.glyphCandidates.count >= 3
            && result.glyphCandidates.first?.contains(where: {
                $0.confidence >= 0.72 && ["A", "B", "C", "D", "E", "F", "G"].contains($0.text)
            }) == true
        guard bounds.height > ChordInkRecognitionScaleNormalizer.maximumUnscaledHeight
                || compactRootLedNoRead else {
            return result
        }

        var augmented = result
        var rawCandidates = Set(result.rawCandidates)
        var primaryDisplayTexts = Set(result.candidateScores.compactMap(\.displayText))
        if let primaryDisplayText = result.match?.displayText {
            primaryDisplayTexts.insert(primaryDisplayText)
        }
        var bestReviewScoreByDisplayText: [String: ChordInkCandidateScore] = [:]
        for score in result.reviewCandidateScores {
            guard let displayText = score.displayText,
                  !primaryDisplayTexts.contains(displayText) else {
                continue
            }
            if let current = bestReviewScoreByDisplayText[displayText],
               current.confidence >= score.confidence {
                continue
            }
            bestReviewScoreByDisplayText[displayText] = score
        }

        for targetHeight in ChordInkRecognitionScaleNormalizer.recoveryHeights {
            let recoveryResult = scaleRecoveryRecognizer.recognize(
                strokes: ChordInkRecognitionScaleNormalizer.strokes(
                    from: strokes,
                    targetHeight: targetHeight
                ),
                options: .live
            )
            augmented.metrics.totalMilliseconds += recoveryResult.metrics.totalMilliseconds

            for rawCandidate in recoveryResult.rawCandidates where rawCandidates.insert(rawCandidate).inserted {
                augmented.rawCandidates.append(rawCandidate)
            }

            let recoveryScores = ChordInkRecognitionPolicy.rankedSupportedScores(for: recoveryResult)
                + recoveryResult.reviewCandidateScores
            for score in recoveryScores {
                guard let displayText = score.displayText,
                      !primaryDisplayTexts.contains(displayText) else {
                    continue
                }
                if let current = bestReviewScoreByDisplayText[displayText],
                   current.confidence >= score.confidence {
                    continue
                }
                bestReviewScoreByDisplayText[displayText] = score
            }
        }

        augmented.reviewCandidateScores = Array(bestReviewScoreByDisplayText.values
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                return (lhs.displayText ?? lhs.text) < (rhs.displayText ?? rhs.text)
            }
            .prefix(4))
        return augmented
    }

    private func evidence(
        outcome: ChordInkTrustEvidenceOutcome,
        symbolSupportCount: Int,
        completedProbeCount: Int,
        startedAt: TimeInterval
    ) -> ChordInkTrustEvidence {
        ChordInkTrustEvidence(
            outcome: outcome,
            symbolSupportCount: symbolSupportCount,
            completedProbeCount: completedProbeCount,
            requiredProbeCount: Probe.allCases.count,
            validationMilliseconds: max(
                0,
                (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
        )
    }

    private func hidingInternalLedgerIfNeeded(
        _ result: ChordInkRecognitionResult,
        options: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult {
        guard !options.includesSymbolLedgerDiagnostics else {
            return result
        }

        var result = result
        result.symbolLedger = nil
        result.symbolLedgerAssessment = nil
        return result
    }

    private func transformed(_ strokes: [InkStroke], for probe: Probe) -> [InkStroke] {
        guard !strokes.isEmpty else {
            return strokes
        }

        let bounds = InkBounds.enclosing(strokes.map(\.bounds))
        let centerX = (bounds.minX + bounds.maxX) / 2
        let centerY = (bounds.minY + bounds.maxY) / 2

        return strokes.map { stroke in
            let transformedPoints = stroke.points.map { point in
                let x = point.x - centerX
                let y = point.y - centerY
                let transformedPoint: (x: Double, y: Double)

                switch probe {
                case .normalizedPointDensity:
                    transformedPoint = (point.x, point.y)
                case .scaledDown:
                    transformedPoint = (
                        centerX + x * 0.90,
                        centerY + y * 0.90
                    )
                case .rotatedCounterclockwise:
                    transformedPoint = rotated(
                        x: x,
                        y: y,
                        radians: -.pi / 60,
                        centerX: centerX,
                        centerY: centerY
                    )
                case .rotatedClockwise:
                    transformedPoint = rotated(
                        x: x,
                        y: y,
                        radians: .pi / 60,
                        centerX: centerX,
                        centerY: centerY
                    )
                }

                return InkPoint(
                    x: transformedPoint.x,
                    y: transformedPoint.y,
                    timeOffset: point.timeOffset
                )
            }

            if probe == .normalizedPointDensity {
                return InkStroke(
                    points: resampled(transformedPoints, targetSpacing: 3.4),
                    creationTimeOffset: stroke.creationTimeOffset
                )
            }

            return InkStroke(
                points: transformedPoints,
                creationTimeOffset: stroke.creationTimeOffset
            )
        }
    }

    private func sevenNineTrustConflict(
        result: ChordInkRecognitionResult,
        strokes: [InkStroke]
    ) -> ChordInkTrustEvidenceOutcome? {
        guard let symbol = result.match?.symbol,
              symbol.kind == .rooted,
              symbol.extensions == ["7"],
              symbol.alterations.isEmpty,
              symbol.slashBass == nil else {
            return nil
        }

        let clusters = StrokeClusterer().cluster(strokes)
        for (columnIndex, selectedCandidate) in result.acceptedGlyphCandidates.enumerated() {
            guard selectedCandidate.text == "7",
                  result.glyphCandidates.indices.contains(columnIndex) else {
                continue
            }
            let candidates = result.glyphCandidates[columnIndex]
            guard candidates.first?.text == "7",
                  candidates.contains(where: { $0.text == "9" && $0.confidence >= 0.55 }),
                  clusters.indices.contains(columnIndex) else {
                continue
            }

            let cluster = clusters[columnIndex]
            if hasLateUpperReturn(in: cluster) {
                return .conflictingExtensionEvidence
            }

            let segmentLengths = cluster.strokes.flatMap { stroke in
                zip(stroke.points, stroke.points.dropFirst()).map { start, end in
                    hypot(end.x - start.x, end.y - start.y)
                }
            }.sorted()
            guard !segmentLengths.isEmpty else {
                continue
            }

            let medianSegmentLength = segmentLengths[segmentLengths.count / 2]
            if medianSegmentLength > 5.5 {
                return .insufficientPointDensity
            }
        }

        return nil
    }

    /// The base one-stroke fallback intentionally accepts loose C/G writing,
    /// but that also makes stable zigzags and cancellation scribbles look like
    /// roots. Keep those results available for review while refusing to call
    /// them trusted. The thresholds are separated from ordinary C/G fixtures:
    /// the retained one-stroke corpus stays below 0.78 aspect, 2.93 normalized
    /// path length, and two significant vertical reversals.
    private func hasImplausiblePlainRootGeometry(
        result: ChordInkRecognitionResult,
        strokes: [InkStroke]
    ) -> Bool {
        guard let symbol = result.match?.symbol,
              symbol.kind == .rooted,
              symbol.root == .c || symbol.root == .g,
              symbol.accidental == .natural,
              symbol.quality.isEmpty,
              symbol.extensions.isEmpty,
              symbol.alterations.isEmpty,
              symbol.slashBass == nil,
              strokes.count == 1,
              let stroke = strokes.first,
              stroke.points.count > 1 else {
            return false
        }

        let width = max(stroke.bounds.width, 1)
        let height = max(stroke.bounds.height, 1)
        let aspectRatio = width / height
        let pathLength = zip(stroke.points, stroke.points.dropFirst())
            .map { start, end in hypot(end.x - start.x, end.y - start.y) }
            .reduce(0, +)
        let normalizedPathLength = pathLength / max(width, height)
        let verticalReversalCount = significantDirectionChangeCount(
            points: stroke.points,
            value: { $0.y },
            minimumDelta: max(2, height * 0.06)
        )

        return aspectRatio > 1.65
            || normalizedPathLength > 4.25
            || verticalReversalCount >= 3
    }

    private func significantDirectionChangeCount(
        points: [InkPoint],
        value: (InkPoint) -> Double,
        minimumDelta: Double
    ) -> Int {
        var previousDirection = 0
        var changeCount = 0

        for (currentPoint, nextPoint) in zip(points, points.dropFirst()) {
            let delta = value(nextPoint) - value(currentPoint)
            guard abs(delta) >= minimumDelta else {
                continue
            }

            let direction = delta > 0 ? 1 : -1
            if previousDirection != 0, direction != previousDirection {
                changeCount += 1
            }
            previousDirection = direction
        }

        return changeCount
    }

    private func hasLateUpperReturn(in cluster: InkCluster) -> Bool {
        guard cluster.strokes.count == 1,
              let stroke = cluster.strokes.first,
              stroke.points.count >= 8 else {
            return false
        }

        let upperReturnLimit = stroke.bounds.minY + stroke.bounds.height * 0.34
        return stroke.points.dropFirst(stroke.points.count / 2).contains { point in
            point.y <= upperReturnLimit
        }
    }

    /// Stability probes can only prove that a read is repeatable; they cannot
    /// prove that a repeatable glyph lookalike has the right musical role.
    /// Keep the known cross-role collisions out of the trusted path while
    /// preserving the candidate as a user-selectable suggestion.
    private func semanticAmbiguityTrustConflict(
        result: ChordInkRecognitionResult
    ) -> ChordInkTrustEvidenceOutcome? {
        guard let symbol = result.match?.symbol,
              symbol.kind == .rooted else {
            return nil
        }

        if symbol.quality == "ø",
           result.acceptedGlyphCandidates.contains(where: { glyph in
               glyph.text == "ø" && glyph.source == .composer
           }) {
            return .conflictingQualityEvidence
        }

        if isAmbiguousPlainSixth(result: result, symbol: symbol) {
            return .conflictingExtensionEvidence
        }

        if hasStrongerRootAccidentalLookalike(result: result, symbol: symbol)
            || hasNaturalMinorVersusFlatRootConflict(result: result, symbol: symbol) {
            return .conflictingAccidentalEvidence
        }

        return nil
    }

    private func isAmbiguousPlainSixth(
        result: ChordInkRecognitionResult,
        symbol: ChordSymbol
    ) -> Bool {
        guard symbol.accidental == .natural,
              symbol.quality.isEmpty,
              symbol.extensions == ["6"],
              symbol.alterations.isEmpty,
              symbol.slashBass == nil,
              let index = result.acceptedGlyphCandidates.firstIndex(where: { $0.text == "6" }),
              result.glyphCandidates.indices.contains(index) else {
            return false
        }

        let selected = result.acceptedGlyphCandidates[index]
        let column = result.glyphCandidates[index]
        let selectedConfidence = max(
            selected.confidence,
            column.first(where: { $0.text == "6" })?.confidence ?? 0
        )
        let flatConfidence = column
            .filter { $0.text == "b" }
            .map(\.confidence)
            .max() ?? 0
        let rootPressure = column
            .filter { glyph in
                glyph.source == .heuristic && "ABCDEFG".contains(glyph.text)
            }
            .map(\.confidence)
            .max() ?? 0

        let nearTiedFlat = flatConfidence >= 0.90
            && flatConfidence + 0.04 >= selectedConfidence
        let muchStrongerRoot = rootPressure >= 0.95
            && rootPressure >= selectedConfidence + 0.18

        return nearTiedFlat || muchStrongerRoot
    }

    private func hasStrongerRootAccidentalLookalike(
        result: ChordInkRecognitionResult,
        symbol: ChordSymbol
    ) -> Bool {
        guard symbol.accidental != .natural,
              result.acceptedGlyphCandidates.indices.contains(1),
              result.glyphCandidates.indices.contains(1) else {
            return false
        }

        let selected = result.acceptedGlyphCandidates[1]
        guard selected.text == "b" || selected.text == "#" else {
            return false
        }

        let selectedConfidence = max(
            selected.confidence,
            result.glyphCandidates[1]
                .first(where: { $0.text == selected.text })?.confidence ?? 0
        )
        let competingTexts: Set<String> = [
            "A", "B", "C", "D", "E", "F", "G",
            "1", "2", "3", "5", "6", "7", "9", "m", "-", "△", "°", "ø"
        ]

        return result.glyphCandidates[1].contains { glyph in
            glyph.source == .heuristic
                && competingTexts.contains(glyph.text)
                && glyph.confidence >= 0.95
                && glyph.confidence >= selectedConfidence + 0.01
        }
    }

    private func hasNaturalMinorVersusFlatRootConflict(
        result: ChordInkRecognitionResult,
        symbol: ChordSymbol
    ) -> Bool {
        guard symbol.accidental == .natural,
              symbol.quality == "-" || symbol.quality == "m",
              !symbol.alterations.isEmpty,
              result.glyphCandidates.indices.contains(0),
              let qualityIndex = result.acceptedGlyphCandidates.firstIndex(where: { glyph in
                  glyph.text == "m" || glyph.text == "-"
              }),
              result.glyphCandidates.indices.contains(qualityIndex) else {
            return false
        }

        let hasPlausibleLostFlat = result.glyphCandidates[0].contains { glyph in
            glyph.text == "b"
                && glyph.source == .heuristic
                && glyph.confidence >= 0.44
        }
        guard hasPlausibleLostFlat else {
            return false
        }

        let selected = result.acceptedGlyphCandidates[qualityIndex]
        return result.glyphCandidates[qualityIndex].contains { glyph in
            glyph.source == .heuristic
                && "ABCDEFG".contains(glyph.text)
                && glyph.confidence >= 0.95
                && glyph.confidence + 0.03 >= selected.confidence
        }
    }

    private func hasStrongCompetingAlterationEvidence(
        _ result: ChordInkRecognitionResult
    ) -> Bool {
        guard let primary = result.match?.symbol,
              primary.kind == .rooted,
              !primary.alterations.isEmpty else {
            return false
        }

        if hasDirectSharpFiveVersusFlatThirteenConflict(
            result: result,
            primary: primary
        ) {
            return true
        }

        return ChordInkRecognitionPolicy.rankedSupportedScores(for: result).contains { score in
            guard score.displayText != result.match?.displayText,
                  score.confidence >= ChordInkRecognitionPolicy.trustedMinimumConfidence,
                  let displayText = score.displayText,
                  let competitor = ChordRecognitionCompendium.match(displayText)?.symbol else {
                return false
            }

            return competitor.kind == .rooted
                && competitor.root == primary.root
                && competitor.accidental == primary.accidental
                && competitor.quality == primary.quality
                && competitor.extensions == primary.extensions
                && competitor.slashBass == primary.slashBass
                && competitor.alterations != primary.alterations
        }
    }

    /// A handwritten sharp-five can be synthesized as flat-thirteen when the
    /// sharp and five remain strong direct glyphs but the composer inserts a
    /// low-confidence `1` ahead of a template `3`. Stability probes reproduce
    /// that same semantic mistake, so direct glyph disagreement must require
    /// confirmation instead of becoming a silently trusted altered chord.
    private func hasDirectSharpFiveVersusFlatThirteenConflict(
        result: ChordInkRecognitionResult,
        primary: ChordSymbol
    ) -> Bool {
        guard primary.alterations.contains("b13") else {
            return false
        }

        for index in result.acceptedGlyphCandidates.indices {
            let selected = result.acceptedGlyphCandidates[index]
            guard selected.text == "1",
                  selected.source == .composer,
                  result.glyphCandidates.indices.contains(index),
                  result.acceptedGlyphCandidates.indices.contains(index + 1),
                  result.glyphCandidates.indices.contains(index + 1),
                  result.acceptedGlyphCandidates[index + 1].text == "3" else {
                continue
            }

            let sharpConfidence = result.glyphCandidates[index]
                .filter { $0.text == "#" && $0.source == .heuristic }
                .map(\.confidence)
                .max() ?? 0
            let fiveConfidence = result.glyphCandidates[index + 1]
                .filter { $0.text == "5" && $0.source == .heuristic }
                .map(\.confidence)
                .max() ?? 0

            if sharpConfidence >= 0.90, fiveConfidence >= 0.90 {
                return true
            }
        }

        return false
    }

    private func hasStrongCompetingQualityEvidence(
        _ result: ChordInkRecognitionResult
    ) -> Bool {
        guard let quality = result.match?.symbol.quality,
              quality == "°" || quality == "ø" || quality.contains("△") else {
            return false
        }

        for (columnIndex, selectedCandidate) in result.acceptedGlyphCandidates.enumerated() {
            guard result.glyphCandidates.indices.contains(columnIndex),
                  selectedCandidate.text == "°"
                    || selectedCandidate.text == "ø"
                    || selectedCandidate.text == "△" else {
                continue
            }
            let candidates = result.glyphCandidates[columnIndex]
            let triangleConfidence = candidates.first(where: { $0.text == "△" })?.confidence ?? 0
            let roundConfidence = candidates
                .filter { $0.text == "°" || $0.text == "ø" }
                .map(\.confidence)
                .max() ?? 0

            if (quality == "°" || quality == "ø"),
               roundConfidence >= 0.90,
               triangleConfidence >= 0.70 {
                return true
            }
            if quality.contains("△"),
               triangleConfidence >= 0.90,
               roundConfidence >= 0.70 {
                return true
            }
        }

        return false
    }

    private func resampled(_ points: [InkPoint], targetSpacing: Double) -> [InkPoint] {
        guard let firstPoint = points.first,
              let lastPoint = points.last,
              points.count > 1 else {
            return points
        }

        let pathLength = zip(points, points.dropFirst())
            .map { start, end in hypot(end.x - start.x, end.y - start.y) }
            .reduce(0, +)
        guard pathLength > 0 else {
            return points
        }

        let sampleCount = max(2, Int((pathLength / targetSpacing).rounded(.up)) + 1)
        guard sampleCount > points.count else {
            return points
        }

        let interval = pathLength / Double(sampleCount - 1)
        var sampledPoints = [firstPoint]
        var distanceSinceLastSample = 0.0
        var previousPoint = firstPoint
        var sourceIndex = points.index(after: points.startIndex)

        while sourceIndex < points.endIndex, sampledPoints.count < sampleCount {
            let currentPoint = points[sourceIndex]
            let segmentLength = hypot(
                currentPoint.x - previousPoint.x,
                currentPoint.y - previousPoint.y
            )
            guard segmentLength > 0 else {
                previousPoint = currentPoint
                sourceIndex = points.index(after: sourceIndex)
                continue
            }

            if distanceSinceLastSample + segmentLength >= interval {
                let amount = (interval - distanceSinceLastSample) / segmentLength
                let timeOffset: TimeInterval?
                if let startTime = previousPoint.timeOffset,
                   let endTime = currentPoint.timeOffset {
                    timeOffset = startTime + (endTime - startTime) * amount
                } else {
                    timeOffset = previousPoint.timeOffset ?? currentPoint.timeOffset
                }
                sampledPoints.append(InkPoint(
                    x: previousPoint.x + (currentPoint.x - previousPoint.x) * amount,
                    y: previousPoint.y + (currentPoint.y - previousPoint.y) * amount,
                    timeOffset: timeOffset
                ))
                previousPoint = sampledPoints[sampledPoints.count - 1]
                distanceSinceLastSample = 0
            } else {
                distanceSinceLastSample += segmentLength
                previousPoint = currentPoint
                sourceIndex = points.index(after: sourceIndex)
            }
        }

        if sampledPoints.last != lastPoint {
            sampledPoints.append(lastPoint)
        }
        return sampledPoints
    }

    private func rotated(
        x: Double,
        y: Double,
        radians: Double,
        centerX: Double,
        centerY: Double
    ) -> (x: Double, y: Double) {
        let cosine = cos(radians)
        let sine = sin(radians)
        return (
            centerX + x * cosine - y * sine,
            centerY + x * sine + y * cosine
        )
    }
}

private enum ChordRepeatInkDetector {
    static func candidate(from strokes: [InkStroke]) -> ChordInkCandidate? {
        let indexedStrokes = strokes.enumerated().filter { !$0.element.points.isEmpty }
        guard indexedStrokes.count == 3 else {
            return nil
        }

        let bounds = InkBounds.enclosing(indexedStrokes.map(\.element.bounds))
        for slashStroke in indexedStrokes where isSlashLike(slashStroke.element, symbolBounds: bounds) {
            let dotStrokes = indexedStrokes.filter { $0.offset != slashStroke.offset }
            guard dotStrokes.count == 2,
                  dotStrokes.allSatisfy({ isDotLike($0.element, symbolBounds: bounds) }),
                  hasChordRepeatLayout(
                    slashStroke: slashStroke.element,
                    dotStrokes: dotStrokes.map(\.element),
                    symbolBounds: bounds
                  ) else {
                continue
            }

            return ChordInkCandidate(
                text: ChordSymbol.chordRepeatDisplayText,
                confidence: 4.95,
                glyphCandidates: [
                    GlyphCandidate(text: "•", confidence: 0.94, source: .composer),
                    GlyphCandidate(text: "/", confidence: 0.94, source: .composer),
                    GlyphCandidate(text: "•", confidence: 0.94, source: .composer)
                ]
            )
        }

        return nil
    }

    private static func isSlashLike(_ stroke: InkStroke, symbolBounds: InkBounds) -> Bool {
        stroke.bounds.width >= 4
            && stroke.bounds.height >= max(14, symbolBounds.height * 0.42)
            && stroke.diagonalAngleMagnitude >= 40
            && stroke.diagonalAngleMagnitude <= 82
            && stroke.straightness >= 0.55
    }

    private static func isDotLike(_ stroke: InkStroke, symbolBounds: InkBounds) -> Bool {
        let maximumDotSize = max(14, min(22, max(symbolBounds.width, symbolBounds.height) * 0.42))
        let width = stroke.bounds.width
        let height = stroke.bounds.height
        let aspect = max(max(width, height), 1) / max(min(width, height), 1)
        let longThinMark = max(width, height) >= 8 && aspect >= 2.2

        return width <= maximumDotSize
            && height <= maximumDotSize
            && !longThinMark
    }

    private static func hasChordRepeatLayout(
        slashStroke: InkStroke,
        dotStrokes: [InkStroke],
        symbolBounds: InkBounds
    ) -> Bool {
        let orderedDots = dotStrokes.sorted { lhs, rhs in
            lhs.bounds.recognitionMidX < rhs.bounds.recognitionMidX
        }
        guard let leftDot = orderedDots.first,
              let rightDot = orderedDots.last else {
            return false
        }

        let horizontalTolerance = max(8, symbolBounds.width * 0.22)
        let verticalTolerance = max(10, symbolBounds.height * 0.30)
        let dotHorizontalSpread = rightDot.bounds.recognitionMidX - leftDot.bounds.recognitionMidX
        let slashCenterX = slashStroke.bounds.recognitionMidX
        let slashBetweenDots = slashCenterX >= leftDot.bounds.recognitionMidX - horizontalTolerance
            && slashCenterX <= rightDot.bounds.recognitionMidX + horizontalTolerance
        let slashCoversDotsVertically = slashStroke.bounds.minY <= min(leftDot.bounds.recognitionMidY, rightDot.bounds.recognitionMidY) + verticalTolerance
            && slashStroke.bounds.maxY >= max(leftDot.bounds.recognitionMidY, rightDot.bounds.recognitionMidY) - verticalTolerance
        let diagonalRepeatDots = leftDot.bounds.recognitionMidY <= slashStroke.bounds.recognitionMidY + verticalTolerance
            && rightDot.bounds.recognitionMidY >= slashStroke.bounds.recognitionMidY - verticalTolerance
        let horizontalRepeatDots = abs(leftDot.bounds.recognitionMidY - rightDot.bounds.recognitionMidY) <= verticalTolerance

        return dotHorizontalSpread >= max(8, symbolBounds.width * 0.24)
            && slashBetweenDots
            && slashCoversDotsVertically
            && (diagonalRepeatDots || horizontalRepeatDots)
    }
}
