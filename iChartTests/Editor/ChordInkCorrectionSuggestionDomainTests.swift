#if canImport(UIKit)
import XCTest
@testable import iChart

final class ChordInkCorrectionSuggestionDomainTests: XCTestCase {
    func testLegacyUnsupportedCandidateSignaturesNeverBecomeQuickChoices() {
        let candidates = ["ñ", "J", "1", "Cmiñ7"]
        let correction = makeCorrection(currentText: "C", candidateTexts: candidates)

        XCTAssertEqual(correction.candidateTexts, candidates)
        XCTAssertEqual(correction.currentDisplayText, "C")
        XCTAssertEqual(correction.quickChoiceTexts, [ChordSymbol.chordRepeatDisplayText])
    }

    func testMixedCandidatesKeepOnlyCompleteSupportedChordsInOriginalOrder() {
        let correction = makeCorrection(
            currentText: "C",
            candidateTexts: [
                "ñ", "G/B", "F sharp m", "G/B", "J", "Cmaj7", "1", "CMaj7"
            ],
            enharmonicChoiceTexts: ["B♭", "C", "Db7(b9)"]
        )

        XCTAssertEqual(
            correction.quickChoiceTexts,
            ["Bb", "Db7(b9)", "G/B", "F#-", "C△7", ChordSymbol.chordRepeatDisplayText]
        )
    }

    func testUnsupportedCurrentEditTextIsPreservedButNotOfferedAsSuggestion() {
        let correction = makeCorrection(
            currentText: "legacy typed text",
            rawInput: "legacy raw input",
            candidateTexts: ["J", "C7", "C7", "1"]
        )

        XCTAssertEqual(correction.currentDisplayText, "legacy typed text")
        XCTAssertEqual(correction.rawInput, "legacy raw input")
        XCTAssertEqual(correction.candidateTexts, ["J", "C7", "C7", "1"])
        XCTAssertEqual(correction.quickChoiceTexts, ["C7", ChordSymbol.chordRepeatDisplayText])
    }

    private func makeCorrection(
        currentText: String,
        rawInput: String? = nil,
        candidateTexts: [String],
        enharmonicChoiceTexts: [String] = []
    ) -> PendingChordCorrection {
        PendingChordCorrection(
            chordEventID: UUID(),
            measureID: UUID(),
            measureIndex: 0,
            currentText: currentText,
            rawInput: rawInput,
            candidateTexts: candidateTexts,
            enharmonicChoiceTexts: enharmonicChoiceTexts
        )
    }
}
#endif
