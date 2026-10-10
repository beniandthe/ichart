#if canImport(CoreGraphics) && canImport(Vision)
import CoreGraphics
import Vision
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyVisionChordRecognizerTests: XCTestCase {
    func testCanonicalNormalizerDelegatesToSharedStrictTypedGrammar() {
        let normalizer = RecognitionStudyCanonicalChordNormalizer()

        XCTAssertEqual(normalizer.normalizedChord(from: "C△7"), "C△7")
        XCTAssertEqual(normalizer.normalizedChord(from: "Bb7(#9)/D"), "Bb7(#9)/D")
        XCTAssertEqual(normalizer.normalizedChord(from: "•/•"), "•/•")
        XCTAssertNil(normalizer.normalizedChord(from: "Cmaj7"))
        XCTAssertNil(normalizer.normalizedChord(from: "CΔ7"))
        XCTAssertNil(normalizer.normalizedChord(from: "c7"))
        XCTAssertNil(normalizer.normalizedChord(from: " C7"))
        XCTAssertNil(normalizer.normalizedChord(from: "H7"))
    }

    func testEmptyInkReturnsNoReadBeforeVisionRuns() throws {
        let recognizer = RecognitionStudyVisionChordRecognizer(
            normalizer: FixtureNormalizer()
        )

        let result = try recognizer.recognize(strokes: [])

        XCTAssertEqual(result.decision, .noRead(.noInk))
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testDecisionAcceptsOnlyHighConfidenceSeparatedCrossRasterConsensus() {
        let evidence = [
            [
                candidate("C△7", 0.94, pass: 0, rank: 0),
                candidate("C-7", 0.61, pass: 0, rank: 1)
            ],
            [
                candidate("C△7", 0.91, pass: 1, rank: 0),
                candidate("G7", 0.50, pass: 1, rank: 1)
            ]
        ]

        let result = RecognitionStudyVisionChordRecognizer.decide(
            evidenceByPass: evidence
        )

        XCTAssertEqual(
            result.decision,
            .accepted(chord: "C△7", confidenceFloor: 0.91)
        )
        XCTAssertEqual(result.candidates.count, 4)
        XCTAssertEqual(result.candidates[0].rawText, "C△7")
        XCTAssertEqual(result.candidates[0].rawConfidenceFloor, 0.94)
    }

    func testDecisionRoutesDisagreementLowConfidenceAndNarrowMarginToReview() {
        let disagreement = RecognitionStudyVisionChordRecognizer.decide(
            evidenceByPass: [
                [candidate("B", 0.95, pass: 0, rank: 0)],
                [candidate("G", 0.96, pass: 1, rank: 0)]
            ]
        )
        XCTAssertEqual(disagreement.decision, .review(.rasterPassDisagreement))

        let lowConfidence = RecognitionStudyVisionChordRecognizer.decide(
            evidenceByPass: [
                [candidate("B", 0.74, pass: 0, rank: 0)],
                [candidate("B", 0.75, pass: 1, rank: 0)]
            ]
        )
        XCTAssertEqual(lowConfidence.decision, .review(.confidenceBelowThreshold))

        let narrowMargin = RecognitionStudyVisionChordRecognizer.decide(
            evidenceByPass: [
                [
                    candidate("B", 0.95, pass: 0, rank: 0),
                    candidate("G", 0.89, pass: 0, rank: 1)
                ],
                [
                    candidate("B", 0.94, pass: 1, rank: 0),
                    candidate("C", 0.88, pass: 1, rank: 1)
                ]
            ]
        )
        XCTAssertEqual(narrowMargin.decision, .review(.candidateMarginBelowThreshold))
    }

    func testDecisionNeverPromotesAValidRunnerUpPastAnInvalidVisionLeader() {
        let result = RecognitionStudyVisionChordRecognizer.decide(
            evidenceByPass: [
                [
                    candidate("BAND", 0.96, pass: 0, rank: 0),
                    candidate("B", 0.90, pass: 0, rank: 1)
                ],
                [
                    candidate("B", 0.94, pass: 1, rank: 0)
                ]
            ]
        )

        XCTAssertEqual(result.decision, .review(.topCandidateOutsideGrammar))
    }

    func testDecisionDistinguishesNoVisionTextNoGrammarCandidateAndOnePass() {
        XCTAssertEqual(
            RecognitionStudyVisionChordRecognizer.decide(evidenceByPass: [[], []]).decision,
            .noRead(.noVisionText)
        )
        XCTAssertEqual(
            RecognitionStudyVisionChordRecognizer.decide(
                evidenceByPass: [
                    [candidate("hello", 0.99, pass: 0, rank: 0)],
                    [candidate("world", 0.98, pass: 1, rank: 0)]
                ]
            ).decision,
            .noRead(.noGrammarCandidate)
        )
        XCTAssertEqual(
            RecognitionStudyVisionChordRecognizer.decide(
                evidenceByPass: [[candidate("C7", 0.99, pass: 0, rank: 0)]]
            ).decision,
            .review(.insufficientConsensus)
        )
    }

    func testCandidatePreservesEveryRawComponentConfidence() {
        let candidate = RecognitionStudyVisionChordRecognizer.Candidate(
            rawText: "C7",
            rawComponentConfidences: [0.91, 0.83],
            normalizedChord: "C7",
            passIndex: 1,
            rank: 2
        )

        XCTAssertEqual(candidate.rawText, "C7")
        XCTAssertEqual(candidate.rawComponentConfidences, [0.91, 0.83])
        XCTAssertEqual(candidate.rawConfidenceFloor, 0.83)
        XCTAssertEqual(candidate.normalizedChord, "C7")
    }

    func testRasterizationIsByteDeterministicAndTranslationScaleInvariant() throws {
        let first = try packet(strokes: [
            stroke([(0, 0), (10, 20), (20, 0)]),
            stroke([(24, 0), (24, 20)])
        ])
        let translatedAndScaled = try packet(strokes: [
            stroke([(100, -50), (120, -10), (140, -50)]),
            stroke([(148, -50), (148, -10)])
        ])

        let firstRaster = try RecognitionStudyVisionChordRecognizer.rasterize(
            packet: first,
            strokeWidth: 7
        )
        let repeatedRaster = try RecognitionStudyVisionChordRecognizer.rasterize(
            packet: first,
            strokeWidth: 7
        )
        let invariantRaster = try RecognitionStudyVisionChordRecognizer.rasterize(
            packet: translatedAndScaled,
            strokeWidth: 7
        )

        XCTAssertEqual(firstRaster.width, 512)
        XCTAssertEqual(firstRaster.height, 256)
        XCTAssertEqual(firstRaster.bytesPerRow, 512)
        XCTAssertEqual(firstRaster.grayscalePixels.count, 512 * 256)
        XCTAssertEqual(firstRaster.grayscalePixels, repeatedRaster.grayscalePixels)
        XCTAssertEqual(firstRaster.grayscalePixels, invariantRaster.grayscalePixels)
        XCTAssertTrue(firstRaster.grayscalePixels.contains { $0 < 255 })
    }

    func testRasterizationUsesPointsRatherThanUntrustedStoredBounds() throws {
        let points = [
            InkPoint(x: 0, y: 0, timeOffset: nil),
            InkPoint(x: 10, y: 20, timeOffset: nil)
        ]
        let normal = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(points: points)
        ])
        let unrelatedStoredBounds = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: points,
                bounds: InkBounds(minX: -9_000, minY: -8_000, maxX: 7_000, maxY: 6_000)
            )
        ])

        let lhs = try RecognitionStudyVisionChordRecognizer.rasterize(
            packet: normal,
            strokeWidth: 7
        )
        let rhs = try RecognitionStudyVisionChordRecognizer.rasterize(
            packet: unrelatedStoredBounds,
            strokeWidth: 7
        )

        XCTAssertEqual(lhs.grayscalePixels, rhs.grayscalePixels)
    }

    func testRasterizationEnforcesPointAndStrokeBudgetsBeforeAllocating() throws {
        var pointLimited = RecognitionStudyVisionChordRecognizer.Configuration.default
        pointLimited.maximumPointCount = 1
        let twoPointPacket = try packet(strokes: [stroke([(0, 0), (1, 1)])])

        XCTAssertThrowsError(
            try RecognitionStudyVisionChordRecognizer.rasterize(
                packet: twoPointPacket,
                strokeWidth: 7,
                configuration: pointLimited
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyVisionChordRecognizer.RecognitionError,
                .pointLimitExceeded(actual: 2, maximum: 1)
            )
        }

        var strokeLimited = RecognitionStudyVisionChordRecognizer.Configuration.default
        strokeLimited.maximumStrokeCount = 1
        let twoStrokePacket = try packet(strokes: [
            stroke([(0, 0)]),
            stroke([(1, 1)])
        ])
        XCTAssertThrowsError(
            try RecognitionStudyVisionChordRecognizer.rasterize(
                packet: twoStrokePacket,
                strokeWidth: 7,
                configuration: strokeLimited
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyVisionChordRecognizer.RecognitionError,
                .strokeLimitExceeded(actual: 2, maximum: 1)
            )
        }
    }

    func testRasterizationRejectsConfigurationThatExceedsHardAllocationCaps() throws {
        var configuration = RecognitionStudyVisionChordRecognizer.Configuration.default
        configuration.canvasWidth = 100_000
        let packet = try packet(strokes: [stroke([(0, 0), (1, 1)])])

        XCTAssertThrowsError(
            try RecognitionStudyVisionChordRecognizer.rasterize(
                packet: packet,
                strokeWidth: 7,
                configuration: configuration
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyVisionChordRecognizer.RecognitionError,
                .invalidConfiguration
            )
        }
    }

    private func candidate(
        _ rawText: String,
        _ confidence: Float,
        pass: Int,
        rank: Int
    ) -> RecognitionStudyVisionChordRecognizer.Candidate {
        RecognitionStudyVisionChordRecognizer.Candidate(
            rawText: rawText,
            rawConfidence: confidence,
            normalizedChord: RecognitionStudyCanonicalChordNormalizer()
                .normalizedChord(from: rawText),
            passIndex: pass,
            rank: rank
        )
    }

    private struct FixtureNormalizer: RecognitionStudyChordCandidateNormalizing {
        func normalizedChord(from rawText: String) -> String? {
            RecognitionStudyCanonicalChordNormalizer()
                .normalizedChord(from: rawText)
        }
    }

    private func packet(
        strokes: [InkStroke]
    ) throws -> ChordInkCanonicalTrajectoryPacket {
        try ChordInkCanonicalTrajectoryPacket(strokes: strokes)
    }

    private func stroke(
        _ points: [(Double, Double)]
    ) -> InkStroke {
        InkStroke(
            points: points.map { point in
                InkPoint(x: point.0, y: point.1, timeOffset: nil)
            }
        )
    }
}
#endif
