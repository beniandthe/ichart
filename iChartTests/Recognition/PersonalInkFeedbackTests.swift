import XCTest
@testable import iChart

final class PersonalInkFeedbackTests: XCTestCase {
    func testChangingThePresentedChoiceIsExplicitCorrectionAcrossRootsAndQualities() {
        let labels = ["A", "B", "C", "D", "E", "F", "G", "Bb7", "F#m7", "Ebmaj7", "G/B"]
        for presented in labels {
            for accepted in labels {
                XCTAssertEqual(PersonalInkExampleSource.reviewedChoice(acceptedText: accepted, presentedText: presented),
                               accepted == presented ? .confirmedReview : .explicitCorrection,
                               "\(presented) → \(accepted)")
            }
        }
    }

    func testTypingAValidLabelForNoReadIsExplicitSupervision() {
        for presented in [nil, "", "not a chord"] as [String?] {
            XCTAssertEqual(PersonalInkExampleSource.reviewedChoice(acceptedText: "D7", presentedText: presented), .explicitCorrection)
        }
    }

    func testEquivalentSpellingDoesNotUpgradeConfirmationAuthority() {
        for (accepted, presented) in [("  Cm7  ", "C-7"), ("Ebmaj7", "Eb△7"), ("G/B", "G/B")] {
            XCTAssertEqual(PersonalInkExampleSource.reviewedChoice(acceptedText: accepted, presentedText: presented), .confirmedReview)
        }
    }

    func testInvalidLabelsCannotBecomeLearningEvidence() {
        for invalid in ["", "   ", "not a chord"] {
            XCTAssertNil(PersonalInkExampleSource.reviewedChoice(acceptedText: invalid, presentedText: "C"))
        }
    }

    func testAcceptingThePersonalDefaultIsNotIndependentCorrectionEvidence() {
        // The baseline might disagree, but the user only accepted what was
        // displayed. Do not promote the personal model's own default to a
        // stronger supervision source merely because it differs from baseline.
        XCTAssertEqual(PersonalInkExampleSource.reviewedChoice(acceptedText: "G7", presentedText: "G7"), .confirmedReview)
    }
}
