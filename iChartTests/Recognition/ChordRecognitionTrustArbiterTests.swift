import XCTest
@testable import iChart

final class ChordRecognitionTrustArbiterTests: XCTestCase {
    func testNoOCREvidenceUsesPrimaryDecision() {
        let result = recognitionResult(
            matchText: "C",
            confidence: 4.80,
            scores: [
                candidateScore("C", confidence: 4.80),
                candidateScore("G", confidence: 4.10)
            ]
        )

        let decision = ChordRecognitionTrustArbiter.decision(for: result)

        XCTAssertEqual(decision.action, .autoRender)
        XCTAssertEqual(decision.acceptedText, "C")
        XCTAssertEqual(decision.trustSource, .primaryRecognizer)
        XCTAssertEqual(decision.agreementLevel, .ocrNotRequested)
    }

    func testOCRAgreementCanResolveClosePrimaryRace() {
        let result = recognitionResult(
            matchText: "C",
            confidence: 4.80,
            scores: [
                candidateScore("C", confidence: 4.80),
                candidateScore("G", confidence: 4.72)
            ],
            ocrCandidates: [
                ocrCandidate("C", confidence: 0.91)
            ]
        )

        let decision = ChordRecognitionTrustArbiter.decision(for: result)

        XCTAssertEqual(decision.action, .autoRender)
        XCTAssertEqual(decision.acceptedText, "C")
        XCTAssertEqual(decision.trustSource, .primaryWithOCRAgreement)
        XCTAssertEqual(decision.agreementLevel, .agreesWithPrimary)
        XCTAssertEqual(decision.ocrBestCandidateText, "C")
    }

    func testOCRSupportingRunnerUpKeepsConfirmation() {
        let result = recognitionResult(
            matchText: "C",
            confidence: 4.80,
            scores: [
                candidateScore("C", confidence: 4.80),
                candidateScore("G", confidence: 4.72)
            ],
            ocrCandidates: [
                ocrCandidate("G", confidence: 0.88)
            ]
        )

        let decision = ChordRecognitionTrustArbiter.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "C")
        XCTAssertEqual(decision.competingCandidateText, "G")
        XCTAssertEqual(decision.trustSource, .primaryWithOCRDisagreement)
        XCTAssertEqual(decision.agreementLevel, .supportsRunnerUp)
    }

    func testPartialOCRDoesNotVetoPrimaryAutoRender() {
        let result = recognitionResult(
            matchText: "Bb",
            confidence: 4.09,
            scores: [
                candidateScore("Bb", confidence: 4.09),
                candidateScore("Db", confidence: 3.91),
                candidateScore("B6", confidence: 3.61)
            ],
            ocrCandidates: [
                ocrCandidate("B", confidence: 0.50)
            ]
        )

        let decision = ChordRecognitionTrustArbiter.decision(for: result)

        XCTAssertEqual(decision.action, .autoRender)
        XCTAssertEqual(decision.acceptedText, "Bb")
        XCTAssertEqual(decision.trustSource, .primaryRecognizer)
        XCTAssertEqual(decision.agreementLevel, .partialOCR)
        XCTAssertEqual(decision.ocrBestCandidateText, "B")
    }

    func testUnrankedOCRDisagreementDoesNotVetoPrimaryAutoRender() {
        let result = recognitionResult(
            matchText: "Cb",
            confidence: 4.08,
            scores: [
                candidateScore("Cb", confidence: 4.08),
                candidateScore("Gb", confidence: 3.96),
                candidateScore("C6", confidence: 3.60)
            ],
            ocrCandidates: [
                ocrCandidate("E", confidence: 0.50)
            ]
        )

        let decision = ChordRecognitionTrustArbiter.decision(for: result)

        XCTAssertEqual(decision.action, .autoRender)
        XCTAssertEqual(decision.acceptedText, "Cb")
        XCTAssertEqual(decision.trustSource, .primaryRecognizer)
        XCTAssertEqual(decision.agreementLevel, .disagreesWithPrimary)
        XCTAssertEqual(decision.ocrBestCandidateText, "E")
    }

    func testInvalidOCRIsIgnoredBehindCompendiumGate() {
        let result = recognitionResult(
            matchText: "C",
            confidence: 4.80,
            scores: [
                candidateScore("C", confidence: 4.80)
            ],
            ocrCandidates: [
                ocrCandidate("EGG", confidence: 0.95)
            ]
        )

        let decision = ChordRecognitionTrustArbiter.decision(for: result)

        XCTAssertEqual(decision.action, .autoRender)
        XCTAssertEqual(decision.acceptedText, "C")
        XCTAssertEqual(decision.trustSource, .primaryRecognizer)
        XCTAssertEqual(decision.agreementLevel, .ocrInvalid)
        XCTAssertNil(decision.ocrBestCandidateText)
    }

    func testOCROnlySupportedCandidateRequiresConfirmation() {
        let result = recognitionResult(
            matchText: nil,
            confidence: 0,
            scores: [
                ChordInkCandidateScore(text: "EGG", displayText: nil, confidence: 3.80)
            ],
            ocrCandidates: [
                ocrCandidate("Dbsus", confidence: 0.76)
            ]
        )

        let decision = ChordRecognitionTrustArbiter.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "Dbsus")
        XCTAssertEqual(decision.trustSource, .ocrSupportedCandidate)
        XCTAssertEqual(decision.agreementLevel, .ocrOnlySupported)
    }

    func testOCRIsRequestedOnlyForAmbiguousPrimaryReads() {
        let clearResult = recognitionResult(
            matchText: "C",
            confidence: 4.80,
            scores: [
                candidateScore("C", confidence: 4.80)
            ]
        )
        let mediumConfidenceAutoRenderResult = recognitionResult(
            matchText: "Bb",
            confidence: 4.09,
            scores: [
                candidateScore("Bb", confidence: 4.09),
                candidateScore("Db", confidence: 3.91),
                candidateScore("B6", confidence: 3.61)
            ]
        )
        let closeResult = recognitionResult(
            matchText: "C",
            confidence: 4.80,
            scores: [
                candidateScore("C", confidence: 4.80),
                candidateScore("G", confidence: 4.77)
            ]
        )
        let moderateGapResult = recognitionResult(
            matchText: "C",
            confidence: 4.80,
            scores: [
                candidateScore("C", confidence: 4.80),
                candidateScore("G", confidence: 4.74)
            ]
        )

        XCTAssertFalse(ChordRecognitionTrustArbiter.shouldRequestOCR(for: clearResult))
        XCTAssertFalse(ChordRecognitionTrustArbiter.shouldRequestOCR(for: mediumConfidenceAutoRenderResult))
        XCTAssertFalse(ChordRecognitionTrustArbiter.shouldRequestOCR(for: moderateGapResult))
        XCTAssertTrue(ChordRecognitionTrustArbiter.shouldRequestOCR(for: closeResult))
    }

    private func recognitionResult(
        matchText: String?,
        confidence: Double,
        scores: [ChordInkCandidateScore],
        ocrCandidates: [ChordOCRCandidate]? = nil
    ) -> ChordInkRecognitionResult {
        ChordInkRecognitionResult(
            rawCandidates: scores.map(\.text),
            glyphCandidates: [],
            match: matchText.flatMap(ChordRecognitionCompendium.match),
            confidence: confidence,
            candidateScores: scores,
            ocrCandidates: ocrCandidates
        )
    }

    private func candidateScore(_ text: String, confidence: Double) -> ChordInkCandidateScore {
        let match = ChordRecognitionCompendium.match(text)
        return ChordInkCandidateScore(
            text: text,
            displayText: match?.displayText,
            confidence: confidence
        )
    }

    private func ocrCandidate(_ rawText: String, confidence: Double) -> ChordOCRCandidate {
        ChordOCRCandidate.normalized(
            rawText: rawText,
            confidence: confidence,
            source: .testDouble
        )
    }
}
