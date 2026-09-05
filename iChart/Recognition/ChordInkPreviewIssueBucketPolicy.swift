import Foundation

struct ChordInkPreviewIssueBucketCounts: Hashable {
    var issueCount = 0
    var rootIssueCount = 0
    var rootAccidentalIssueCount = 0
    var qualityIssueCount = 0
    var triangleQualityIssueCount = 0
    var dimQualityIssueCount = 0
    var extensionIssueCount = 0
    var alterationIssueCount = 0
    var slashBassIssueCount = 0
    var barlineSequenceIssueCount = 0
    var candidateLimitIssueCount = 0
    var unknownIssueCount = 0

    fileprivate mutating func record(_ families: Set<ChordInkPreviewIssueFamily>) {
        if families.contains(.root) {
            rootIssueCount += 1
        }

        if families.contains(.rootAccidental) {
            rootAccidentalIssueCount += 1
        }

        if families.contains(.quality) {
            qualityIssueCount += 1
        }

        if families.contains(.triangleQuality) {
            triangleQualityIssueCount += 1
        }

        if families.contains(.dimQuality) {
            dimQualityIssueCount += 1
        }

        if families.contains(.extension) {
            extensionIssueCount += 1
        }

        if families.contains(.alteration) {
            alterationIssueCount += 1
        }

        if families.contains(.slashBass) {
            slashBassIssueCount += 1
        }

        if families.contains(.unknown) {
            unknownIssueCount += 1
        }
    }
}

fileprivate enum ChordInkPreviewIssueFamily: Hashable {
    case root
    case rootAccidental
    case quality
    case triangleQuality
    case dimQuality
    case `extension`
    case alteration
    case slashBass
    case unknown
}

enum ChordInkPreviewIssueBucketPolicy {
    private static let rootTexts: Set<String> = ["A", "B", "C", "D", "E", "F", "G"]
    private static let accidentalTexts: Set<String> = ["b", "#"]
    private static let qualityTexts: Set<String> = ["-", "m", "△", "Δ", "∆", "°", "ø", "•", "+", "s", "u", "a", "l", "t"]
    private static let triangleTexts: Set<String> = ["△", "Δ", "∆"]
    private static let diminishedTexts: Set<String> = ["°", "ø", "•"]
    private static let extensionTexts: Set<String> = ["6", "7", "9", "1", "3"]

    static func counts(
        results: [ChordInkRecognitionResult],
        decisions: [ChordInkRecognitionDecision],
        barlineCount: Int
    ) -> ChordInkPreviewIssueBucketCounts {
        var counts = ChordInkPreviewIssueBucketCounts()

        for index in results.indices {
            let result = results[index]
            let decision = decisions.indices.contains(index)
                ? decisions[index]
                : ChordInkRecognitionPolicy.decision(for: result)

            guard isIssue(result: result, decision: decision) else {
                continue
            }

            counts.issueCount += 1

            if barlineCount > 0 {
                counts.barlineSequenceIssueCount += 1
            }

            if result.metrics.compositionMetrics.hitGeneratedSequenceLimit {
                counts.candidateLimitIssueCount += 1
            }

            var families = issueFamilies(for: result, decision: decision)
            if families.isEmpty {
                families.insert(.unknown)
            }
            counts.record(families)
        }

        return counts
    }

    private static func isIssue(
        result: ChordInkRecognitionResult,
        decision: ChordInkRecognitionDecision
    ) -> Bool {
        result.match == nil
            || decision.action == .confirm
            || decision.isCloseRace
            || result.metrics.compositionMetrics.hitGeneratedSequenceLimit
    }

    private static func issueFamilies(
        for result: ChordInkRecognitionResult,
        decision: ChordInkRecognitionDecision
    ) -> Set<ChordInkPreviewIssueFamily> {
        var families: Set<ChordInkPreviewIssueFamily> = []
        let symbols = parsedSymbols(for: result, decision: decision)

        if decision.reason.localizedCaseInsensitiveContains("root")
            || hasRootEvidenceIssue(result, symbols: symbols) {
            families.insert(.root)
        }

        if symbols.contains(where: { $0.kind == .rooted && $0.accidental != .natural })
            || hasRootAccidentalGlyph(result) {
            families.insert(.rootAccidental)
        }

        if symbols.contains(where: { $0.kind == .rooted && !$0.quality.isEmpty })
            || hasPostRootGlyph(result, in: qualityTexts, minimumConfidence: 0.45) {
            families.insert(.quality)
        }

        if symbols.contains(where: { isTriangleQuality($0.quality) })
            || hasPostRootGlyph(result, in: triangleTexts, minimumConfidence: 0.45)
            || rawCandidateTextLooksLikeMajorTriangle(result) {
            families.insert(.quality)
            families.insert(.triangleQuality)
        }

        if symbols.contains(where: { isDiminishedQuality($0.quality) })
            || hasPostRootGlyph(result, in: diminishedTexts, minimumConfidence: 0.45)
            || rawCandidateTextLooksDiminished(result) {
            families.insert(.quality)
            families.insert(.dimQuality)
        }

        if symbols.contains(where: { !$0.extensions.isEmpty })
            || hasPostRootGlyph(result, in: extensionTexts, minimumConfidence: 0.45) {
            families.insert(.extension)
        }

        if symbols.contains(where: { !$0.alterations.isEmpty })
            || rawCandidateTextLooksAltered(result) {
            families.insert(.alteration)
        }

        if symbols.contains(where: { $0.slashBass != nil })
            || hasPostRootGlyph(result, in: ["/"], minimumConfidence: 0.45)
            || result.rawCandidates.prefix(12).contains(where: { $0.contains("/") }) {
            families.insert(.slashBass)
        }

        if result.match == nil,
           families.isEmpty,
           !result.glyphCandidates.isEmpty {
            families.insert(.root)
        }

        return families
    }

    private static func parsedSymbols(
        for result: ChordInkRecognitionResult,
        decision: ChordInkRecognitionDecision
    ) -> [ChordSymbol] {
        let texts = ([decision.acceptedText, result.match?.displayText].compactMap { $0 }
            + Array(result.rawCandidates.prefix(12)))

        var seen: Set<String> = []
        var symbols: [ChordSymbol] = []

        for text in texts {
            guard seen.insert(text).inserted,
                  let symbol = try? ChordSymbolParser.parse(text) else {
                continue
            }
            symbols.append(symbol)
        }

        return symbols
    }

    private static func hasRootSignal(_ result: ChordInkRecognitionResult) -> Bool {
        result.glyphCandidates.first?.contains { candidate in
            rootTexts.contains(candidate.text) && candidate.confidence >= 0.45
        } == true
    }

    private static func hasRootEvidenceIssue(
        _ result: ChordInkRecognitionResult,
        symbols: [ChordSymbol]
    ) -> Bool {
        if result.match == nil {
            return hasRootSignal(result)
        }

        guard let rootedSymbol = symbols.first(where: { $0.kind == .rooted }) else {
            return false
        }

        return rootEvidenceStatus(
            acceptedRoot: rootedSymbol.root.rawValue,
            glyphCandidates: result.glyphCandidates
        )?.isIssue ?? true
    }

    private static func rootEvidenceStatus(
        acceptedRoot: String,
        glyphCandidates: [[GlyphCandidate]]
    ) -> RootEvidenceStatus? {
        guard let rootGlyphColumn = glyphCandidates.first else {
            return nil
        }

        let rootCandidates = rootGlyphColumn
            .filter { candidate in
                rootTexts.contains(candidate.text) && candidate.confidence >= 0.30
            }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }

                return lhs.text < rhs.text
            }
        guard let acceptedCandidate = rootCandidates.first(where: { $0.text == acceptedRoot }) else {
            return RootEvidenceStatus(isIssue: true)
        }

        let runnerUp = rootCandidates.first { $0.text != acceptedRoot }
        let runnerUpConfidence = runnerUp?.confidence ?? 0

        return RootEvidenceStatus(
            isIssue: acceptedCandidate.confidence < 0.76
                || acceptedCandidate.confidence - runnerUpConfidence <= 0.08
        )
    }

    private static func hasRootAccidentalGlyph(_ result: ChordInkRecognitionResult) -> Bool {
        guard result.glyphCandidates.indices.contains(1) else {
            return false
        }

        return result.glyphCandidates[1].contains { candidate in
            accidentalTexts.contains(candidate.text) && candidate.confidence >= 0.50
        }
    }

    private static func hasPostRootGlyph(
        _ result: ChordInkRecognitionResult,
        in texts: Set<String>,
        minimumConfidence: Double
    ) -> Bool {
        result.glyphCandidates.dropFirst().contains { group in
            group.contains { candidate in
                texts.contains(candidate.text) && candidate.confidence >= minimumConfidence
            }
        }
    }

    private static func isTriangleQuality(_ quality: String) -> Bool {
        quality.contains("△")
            || quality.contains("Δ")
            || quality.contains("∆")
            || quality.localizedCaseInsensitiveContains("maj")
    }

    private static func isDiminishedQuality(_ quality: String) -> Bool {
        quality.contains("°")
            || quality.contains("ø")
    }

    private static func rawCandidateTextLooksLikeMajorTriangle(_ result: ChordInkRecognitionResult) -> Bool {
        result.rawCandidates.prefix(12).contains { text in
            text.contains("△")
                || text.contains("Δ")
                || text.contains("∆")
                || text.localizedCaseInsensitiveContains("maj")
        }
    }

    private static func rawCandidateTextLooksDiminished(_ result: ChordInkRecognitionResult) -> Bool {
        result.rawCandidates.prefix(12).contains { text in
            text.contains("°")
                || text.contains("ø")
                || text.localizedCaseInsensitiveContains("dim")
        }
    }

    private static func rawCandidateTextLooksAltered(_ result: ChordInkRecognitionResult) -> Bool {
        result.rawCandidates.prefix(12).contains { text in
            let compact = text.filter { !$0.isWhitespace }
            return compact.contains("(b")
                || compact.contains("(#")
                || compact.contains("7b")
                || compact.contains("7#")
                || compact.contains("9b")
                || compact.contains("9#")
                || compact.contains("13b")
                || compact.contains("13#")
        }
    }
}

private struct RootEvidenceStatus: Hashable {
    var isIssue: Bool
}
