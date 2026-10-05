import XCTest
@testable import iChart

final class PersonalInkArbitrationTests: XCTestCase {
    func testEveryNativeReadingRemainsDefaultAgainstEveryConflictingPersonalLabel() throws {
        let labels = try comparisonLabels()
        for baseline in labels {
            for personal in labels where personal != baseline {
                for source in [ChordInkPersonalSuggestion.Source.wholeChord, .symbols] {
                    for provenance in [PersonalInkExampleSource.setup, .confirmedReview, .explicitCorrection] {
                        for trusted in [false, true] {
                            let selection = PersonalInkArbitrationPolicy.select(baselineText: baseline, baselineTrusted: trusted,
                                suggestion: .init(text: personal, source: source, distance: 0,
                                    supportingExampleCount: 5,
                                    correctionSupportCount: provenance == .explicitCorrection ? 5 : 0))
                            XCTAssertEqual(selection.text, baseline, "\(baseline) vs \(personal), \(source), \(provenance), trusted=\(trusted)")
                            XCTAssertFalse(selection.prefersPersonal)
                            XCTAssertEqual(selection.disposition, trusted ? .protectedBaseline : .alternative)
                        }
                    }
                }
            }
        }
    }

    func testAgreementPreservesNativeDecisionWithoutInventingTrust() {
        for trusted in [true, false] {
            let selection = PersonalInkArbitrationPolicy.select(baselineText: "A", baselineTrusted: trusted,
                suggestion: .init(text: "A", source: .wholeChord, distance: 0))
            XCTAssertEqual(selection.disposition, .agreement)
            XCTAssertFalse(selection.prefersPersonal)
        }
    }

    func testExplicitCorrectionCannotReplaceAnExistingAmbiguousDefault() {
        let setup = ChordInkPersonalSuggestion(text: "A", source: .wholeChord, distance: 0.01)
        let before = PersonalInkArbitrationPolicy.select(baselineText: "B", baselineTrusted: false, suggestion: setup)
        XCTAssertEqual(before.text, "B"); XCTAssertEqual(before.disposition, .alternative)
        var correction = setup; correction.correctionSupportCount = 1
        let after = PersonalInkArbitrationPolicy.select(baselineText: "B", baselineTrusted: false, suggestion: correction)
        XCTAssertEqual(after.text, "B"); XCTAssertEqual(after.disposition, .alternative)
        XCTAssertFalse(after.prefersPersonal)
        correction.source = .symbols
        XCTAssertEqual(PersonalInkArbitrationPolicy.select(baselineText: "B", baselineTrusted: false, suggestion: correction).text, "B")
    }

    func testNoReadCanReceiveAReviewOnlyPersonalRecovery() {
        for source in [ChordInkPersonalSuggestion.Source.wholeChord, .symbols] {
            for provenance in [PersonalInkExampleSource.setup, .confirmedReview, .explicitCorrection] {
                let selection = PersonalInkArbitrationPolicy.select(baselineText: nil, baselineTrusted: false,
                    suggestion: .init(text: "A", source: source, distance: 0.01,
                        correctionSupportCount: provenance == .explicitCorrection ? 1 : 0))
                XCTAssertEqual(selection.text, "A"); XCTAssertEqual(selection.disposition, .personalRecovery)
                XCTAssertTrue(selection.prefersPersonal)
            }
        }
    }

    func testHistoricCorrectedReviewDispositionStillDecodes() throws {
        let decoded = try JSONDecoder().decode(PersonalInkArbitrationPolicy.Disposition.self,
            from: Data("\"correctedReview\"".utf8))
        XCTAssertEqual(decoded, .correctedReview)
    }

    func testMalformedEvidenceCannotBecomeAReviewDefault() {
        for distance in [Double.nan, .infinity, -1] {
            let selection = PersonalInkArbitrationPolicy.select(baselineText: nil, baselineTrusted: false,
                suggestion: .init(text: "A", source: .wholeChord, distance: distance))
            XCTAssertNil(selection.text)
        }
        XCTAssertNil(PersonalInkArbitrationPolicy.select(baselineText: nil, baselineTrusted: false,
            suggestion: .init(text: "unsupported", source: .wholeChord, distance: 0)).text)
    }

    private func comparisonLabels() throws -> [String] {
        let rootQualities = ["A", "B", "C", "D", "E", "F", "G"].flatMap { root in
            ["", "7", "m7", "maj7"].map { root + $0 }
        }
        return try (rootQualities + ["F#7", "Bb7", "Ebmaj7", "G/B", "F#m7/C#", "Bbmaj7/F"])
            .map { try XCTUnwrap(ChordRecognitionCompendium.match($0)?.displayText) }
    }
}
