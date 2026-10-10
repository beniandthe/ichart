import Foundation
import XCTest
@testable import iChart

final class HandwritingPersonalizationProductPolicyTests: XCTestCase {
    func testHandwritingPersonalizationIsParkedIndependentOfBuildConfiguration() {
        XCTAssertFalse(HandwritingPersonalizationProductPolicy.isAvailable)
    }

    #if canImport(UIKit)
    func testDefaultRecognitionSessionIgnoresSavedProfileAndEvaluationContextWithoutMutatingProfile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profileURL = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: profileURL)
        let strokes = [InkStroke(points: [
            InkPoint(x: 0, y: 0, timeOffset: 0),
            InkPoint(x: 4, y: 8, timeOffset: 0.1)
        ])]
        try store.update {
            $0.isEnabled = true
            try $0.learn(strokes: strokes, label: "G", kind: .chord, source: .setup)
        }
        let savedBytes = try Data(contentsOf: profileURL)
        let recognizer = ParkedPersonalInkRecognizer(result: Self.result(for: "C"))
        let session = ChordInkRecognitionSession(
            queue: DispatchQueue(label: "personal-ink-product-policy"),
            recognizer: recognizer,
            personalProfile: store
        )
        var request = ChordInkRecognitionSessionRequest(
            requestID: UUID(),
            scheduledAt: Date(),
            requestedDelay: 0,
            strokes: strokes,
            drawingData: Data([0x01]),
            target: (UUID(), 0.5),
            options: .live
        )
        request.evaluationContext = .init(runID: UUID(), profile: store.snapshot())

        let completed = expectation(description: "standard recognition without personal ink")
        session.start(request: request) { payload in
            XCTAssertEqual(payload.result.match?.displayText, "C")
            XCTAssertNil(payload.result.personalSuggestion)
            XCTAssertNil(payload.evaluationPrediction)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)

        XCTAssertEqual(try Data(contentsOf: profileURL), savedBytes)
        XCTAssertEqual(store.snapshot().profile.examples.count, 1)
    }

    private static func result(for text: String) -> ChordInkRecognitionResult {
        ChordInkRecognitionResult(
            rawCandidates: [text],
            glyphCandidates: [],
            match: ChordRecognitionCompendium.match(text),
            confidence: 4.5,
            candidateScores: [ChordInkCandidateScore(
                text: text,
                displayText: ChordRecognitionCompendium.match(text)?.displayText,
                confidence: 4.5
            )]
        )
    }
    #endif
}

#if canImport(UIKit)
private final class ParkedPersonalInkRecognizer: ChordInkRecognizing {
    let result: ChordInkRecognitionResult

    init(result: ChordInkRecognitionResult) {
        self.result = result
    }

    func recognize(strokes _: [InkStroke], options _: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        result
    }
}
#endif
