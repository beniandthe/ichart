import XCTest
@testable import iChart

final class ChordInkLearnedShadowRecognizerTests: XCTestCase {
    func testWrapperReturnsExactProductionResultAndOnlyEnqueuesObservation() {
        let expected = ChordInkRecognitionResult(
            rawCandidates: ["C"],
            glyphCandidates: [],
            match: ChordRecognitionCompendium.match("C"),
            confidence: 4.2,
            candidateScores: [
                ChordInkCandidateScore(text: "C", displayText: "C", confidence: 4.2)
            ]
        )
        let production = ProductionRecognizerSpy(result: expected)
        let observer = LearnedShadowObserverSpy()
        let wrapper = ChordInkLearnedShadowRecognizer(
            production: production,
            observer: observer
        )
        let strokes = [testStroke()]

        let actual = wrapper.recognize(
            strokes: strokes,
            options: .includingSymbolLedgerDiagnostics
        )

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(production.callCount, 1)
        XCTAssertEqual(observer.requests.count, 1)
        XCTAssertEqual(observer.requests[0].strokes, strokes)
        XCTAssertEqual(
            observer.requests[0].options,
            .includingSymbolLedgerDiagnostics
        )
        XCTAssertEqual(observer.requests[0].productionResult, expected)
    }

    func testWrapperCannotReplaceNoReadProductionResult() throws {
        let productionResult = ChordInkRecognitionResult(
            rawCandidates: [],
            glyphCandidates: [],
            match: nil,
            confidence: 0
        )
        let learnedCandidate = try ChordNotation.parseCanonical("G△7")
        let learnedReview = try ChordInkLearnedLegacyBridge.reviewOnlyOutput(
            from: ChordInkLearnedDecodeResult(
                candidates: [
                    ChordInkLearnedDecodedCandidate(
                        notation: learnedCandidate,
                        rawJointLogScore: -0.01
                    )
                ],
                noReadLogScore: -4
            )
        )
        let observer = LearnedShadowObserverSpy(reviewOutput: learnedReview)
        let wrapper = ChordInkLearnedShadowRecognizer(
            production: ProductionRecognizerSpy(result: productionResult),
            observer: observer
        )

        let returned = wrapper.recognize(strokes: [testStroke()], options: .live)

        XCTAssertEqual(returned, productionResult)
        XCTAssertNil(returned.match)
        XCTAssertNil(observer.reviewOutput?.symbolForPrefill)
        XCTAssertNil(observer.reviewOutput?.symbolForPersistence)
    }

    private func testStroke() -> InkStroke {
        InkStroke(points: [
            InkPoint(x: 1, y: 2),
            InkPoint(x: 3, y: 4)
        ])
    }
}

private final class ProductionRecognizerSpy: ChordInkRecognizing {
    private(set) var callCount = 0
    let result: ChordInkRecognitionResult

    init(result: ChordInkRecognitionResult) {
        self.result = result
    }

    func recognize(
        strokes _: [InkStroke],
        options _: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult {
        callCount += 1
        return result
    }
}

private final class LearnedShadowObserverSpy: ChordInkLearnedShadowObserving {
    private(set) var requests: [ChordInkLearnedShadowRequest] = []
    let reviewOutput: ChordInkLearnedLegacyBridgeOutput?

    init(reviewOutput: ChordInkLearnedLegacyBridgeOutput? = nil) {
        self.reviewOutput = reviewOutput
    }

    func enqueue(_ request: ChordInkLearnedShadowRequest) {
        requests.append(request)
    }
}
