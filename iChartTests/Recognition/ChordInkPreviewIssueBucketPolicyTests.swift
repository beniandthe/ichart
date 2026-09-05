import XCTest
@testable import iChart

final class ChordInkPreviewIssueBucketPolicyTests: XCTestCase {
    func testTrustedPlainRootDoesNotEmitIssueBuckets() {
        let result = recognitionResult(
            text: "C",
            confidence: 4.2,
            glyphCandidates: [
                [glyph("C", 0.96), glyph("G", 0.20)]
            ]
        )

        let counts = ChordInkPreviewIssueBucketPolicy.counts(
            results: [result],
            decisions: [decision(.trusted, acceptedText: "C")],
            barlineCount: 0
        )

        XCTAssertEqual(counts.issueCount, 0)
        XCTAssertEqual(counts.rootIssueCount, 0)
        XCTAssertEqual(counts.unknownIssueCount, 0)
    }

    func testNoReadRootSignalEmitsRootIssueBucket() {
        let result = recognitionResult(
            rawCandidates: [],
            match: nil,
            confidence: 0,
            glyphCandidates: [
                [glyph("C", 0.61), glyph("G", 0.55)]
            ]
        )

        let counts = ChordInkPreviewIssueBucketPolicy.counts(
            results: [result],
            decisions: [decision(.confirm, acceptedText: nil, reason: "No reliable read yet.")],
            barlineCount: 0
        )

        XCTAssertEqual(counts.issueCount, 1)
        XCTAssertEqual(counts.rootIssueCount, 1)
        XCTAssertEqual(counts.unknownIssueCount, 0)
    }

    func testNoReadWithoutEvidenceEmitsUnknownIssueBucket() {
        let result = recognitionResult(
            rawCandidates: [],
            match: nil,
            confidence: 0,
            glyphCandidates: []
        )

        let counts = ChordInkPreviewIssueBucketPolicy.counts(
            results: [result],
            decisions: [decision(.confirm, acceptedText: nil, reason: "No reliable read yet.")],
            barlineCount: 0
        )

        XCTAssertEqual(counts.issueCount, 1)
        XCTAssertEqual(counts.rootIssueCount, 0)
        XCTAssertEqual(counts.unknownIssueCount, 1)
    }

    func testFlatRootConfirmEmitsRootAccidentalIssueBucket() {
        let result = recognitionResult(
            text: "Eb",
            confidence: 3.1,
            glyphCandidates: [
                [glyph("E", 0.92)],
                [glyph("b", 0.72), glyph("6", 0.55)]
            ]
        )

        let counts = ChordInkPreviewIssueBucketPolicy.counts(
            results: [result],
            decisions: [decision(.confirm, acceptedText: "Eb")],
            barlineCount: 0
        )

        XCTAssertEqual(counts.issueCount, 1)
        XCTAssertEqual(counts.rootIssueCount, 0)
        XCTAssertEqual(counts.rootAccidentalIssueCount, 1)
    }

    func testMajorTriangleConfirmEmitsTriangleQualityAndExtensionBuckets() {
        let result = recognitionResult(
            text: "Eb△7",
            confidence: 3.5,
            glyphCandidates: [
                [glyph("E", 0.91)],
                [glyph("b", 0.78)],
                [glyph("△", 0.70), glyph("°", 0.38)],
                [glyph("7", 0.88)]
            ]
        )

        let counts = ChordInkPreviewIssueBucketPolicy.counts(
            results: [result],
            decisions: [decision(.confirm, acceptedText: "Eb△7")],
            barlineCount: 0
        )

        XCTAssertEqual(counts.issueCount, 1)
        XCTAssertEqual(counts.rootAccidentalIssueCount, 1)
        XCTAssertEqual(counts.qualityIssueCount, 1)
        XCTAssertEqual(counts.triangleQualityIssueCount, 1)
        XCTAssertEqual(counts.extensionIssueCount, 1)
        XCTAssertEqual(counts.dimQualityIssueCount, 0)
    }

    func testDiminishedConfirmEmitsDimQualityAndExtensionBuckets() {
        let result = recognitionResult(
            text: "C°7",
            confidence: 3.2,
            glyphCandidates: [
                [glyph("C", 0.90)],
                [glyph("°", 0.71), glyph("△", 0.30)],
                [glyph("7", 0.83)]
            ]
        )

        let counts = ChordInkPreviewIssueBucketPolicy.counts(
            results: [result],
            decisions: [decision(.confirm, acceptedText: "C°7")],
            barlineCount: 0
        )

        XCTAssertEqual(counts.issueCount, 1)
        XCTAssertEqual(counts.qualityIssueCount, 1)
        XCTAssertEqual(counts.dimQualityIssueCount, 1)
        XCTAssertEqual(counts.triangleQualityIssueCount, 0)
        XCTAssertEqual(counts.extensionIssueCount, 1)
    }

    func testSlashBassConfirmEmitsSlashBassIssueBucket() {
        let result = recognitionResult(
            text: "G/Bb",
            confidence: 3.0,
            glyphCandidates: [
                [glyph("G", 0.93)],
                [glyph("/", 0.86)],
                [glyph("B", 0.90)],
                [glyph("b", 0.69)]
            ]
        )

        let counts = ChordInkPreviewIssueBucketPolicy.counts(
            results: [result],
            decisions: [decision(.confirm, acceptedText: "G/Bb")],
            barlineCount: 0
        )

        XCTAssertEqual(counts.issueCount, 1)
        XCTAssertEqual(counts.slashBassIssueCount, 1)
        XCTAssertEqual(counts.rootAccidentalIssueCount, 0)
    }

    func testAlteredExtensionConfirmEmitsAlterationAndExtensionBuckets() {
        let result = recognitionResult(
            text: "C7(b9)",
            confidence: 3.0,
            glyphCandidates: [
                [glyph("C", 0.94)],
                [glyph("7", 0.88)],
                [glyph("(", 0.50)],
                [glyph("b", 0.66)],
                [glyph("9", 0.84)],
                [glyph(")", 0.50)]
            ]
        )

        let counts = ChordInkPreviewIssueBucketPolicy.counts(
            results: [result],
            decisions: [decision(.confirm, acceptedText: "C7(b9)")],
            barlineCount: 0
        )

        XCTAssertEqual(counts.issueCount, 1)
        XCTAssertEqual(counts.extensionIssueCount, 1)
        XCTAssertEqual(counts.alterationIssueCount, 1)
    }

    func testGeneratedSequenceLimitAndBarlinesEmitSeparateIssueBuckets() {
        var metrics = ChordInkRecognitionMetrics()
        metrics.compositionMetrics.hitGeneratedSequenceLimit = true
        let result = recognitionResult(
            text: "C△7",
            confidence: 4.2,
            glyphCandidates: [
                [glyph("C", 0.95)],
                [glyph("△", 0.72)],
                [glyph("7", 0.88)]
            ],
            metrics: metrics
        )

        let counts = ChordInkPreviewIssueBucketPolicy.counts(
            results: [result],
            decisions: [decision(.trusted, acceptedText: "C△7")],
            barlineCount: 2
        )

        XCTAssertEqual(counts.issueCount, 1)
        XCTAssertEqual(counts.candidateLimitIssueCount, 1)
        XCTAssertEqual(counts.barlineSequenceIssueCount, 1)
        XCTAssertEqual(counts.triangleQualityIssueCount, 1)
        XCTAssertEqual(counts.extensionIssueCount, 1)
    }

    private func recognitionResult(
        text: String,
        confidence: Double,
        glyphCandidates: [[GlyphCandidate]],
        metrics: ChordInkRecognitionMetrics = ChordInkRecognitionMetrics()
    ) -> ChordInkRecognitionResult {
        recognitionResult(
            rawCandidates: [text],
            match: ChordRecognitionCompendium.match(text),
            confidence: confidence,
            glyphCandidates: glyphCandidates,
            metrics: metrics
        )
    }

    private func recognitionResult(
        rawCandidates: [String],
        match: ChordRecognitionMatch?,
        confidence: Double,
        glyphCandidates: [[GlyphCandidate]],
        metrics: ChordInkRecognitionMetrics = ChordInkRecognitionMetrics()
    ) -> ChordInkRecognitionResult {
        ChordInkRecognitionResult(
            rawCandidates: rawCandidates,
            glyphCandidates: glyphCandidates,
            match: match,
            confidence: confidence,
            candidateScores: rawCandidates.map { text in
                let match = ChordRecognitionCompendium.match(text)
                return ChordInkCandidateScore(
                    text: text,
                    displayText: match?.displayText,
                    confidence: confidence
                )
            },
            metrics: metrics
        )
    }

    private func decision(
        _ action: ChordInkRecognitionAction,
        acceptedText: String?,
        reason: String = "Low-confidence read.",
        isCloseRace: Bool = false
    ) -> ChordInkRecognitionDecision {
        ChordInkRecognitionDecision(
            action: action,
            acceptedText: acceptedText,
            reason: reason,
            isCloseRace: isCloseRace,
            competingCandidateText: nil,
            confidenceGap: nil
        )
    }

    private func glyph(_ text: String, _ confidence: Double) -> GlyphCandidate {
        GlyphCandidate(text: text, confidence: confidence, source: .heuristic)
    }
}
