import XCTest
@testable import iChart

final class PersonalInkMLChordHypothesisIntegrationTests: XCTestCase {
    private final class Encoder: PersonalInkVisualEncoding {
        let identity = "synthetic-complete-token-integration"
        let vocabulary = ["C", ">", "7"]
        var calls = 0
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            calls += 1
            let root = strokes.flatMap(\.points).map(\.x).min()! < 20
            return .init(embedding: [1] + Array(repeating: 0, count: 127),
                         genericLogits: root ? [5, 0, -1] : [-1, 5, 4])
        }
    }
    private var ink: [InkStroke] {
        [.init(points: [.init(x: 0, y: 0), .init(x: 8, y: 20)]),
         .init(points: [.init(x: 60, y: 0), .init(x: 66, y: 20)])]
    }
    private func makeRun() -> PersonalInkEvaluationRun {
        var profile = PersonalInkProfile(); profile.isEnabled = true
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet",
            phase: .beforeCorrections, pipeline: "synthetic", profile: profile)
        run.status = .complete; run.expectedChordCount = 1
        run.records = [.init(measureIndex: 1, fraction: 0, strokes: ink, fingerprint: "synthetic-only",
            baseline: "G", personalized: "G", baselineAction: "confirm", personalizedAction: "confirm", knownInk: false,
            recognitionMilliseconds: 1, totalMilliseconds: 1, cacheHit: false, intended: "C7", recognitionStrokes: ink)]
        return run
    }

    func testCompleteAlternativesDoNotReplaceGreedyPredictionsOrImproveTheirScorecard() throws {
        let run = makeRun()
        let ordinary = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder(), grouping: .losslessSourceV2)
        let alternatives = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder(), grouping: .losslessSourceV2,
            includesCompleteTokenHypotheses: true)
        XCTAssertNil(ordinary.rows[0].completeTokenHypotheses)
        XCTAssertEqual(alternatives.rows[0].prediction, ordinary.rows[0].prediction)
        XCTAssertEqual(alternatives.scorecard, ordinary.scorecard)
        XCTAssertNil(alternatives.rows[0].prediction?.genericChord)
        let hypotheses = try XCTUnwrap(alternatives.rows[0].completeTokenHypotheses)
        XCTAssertTrue(hypotheses.generic.candidates.contains { $0.text == "C7" && $0.tokens == ["C", "7"] })
        XCTAssertTrue(hypotheses.generic.searchComplete)
        XCTAssertEqual(hypotheses.generic.totalSequenceCount, 9)
        XCTAssertTrue(hypotheses.assuranceNote.contains("unverified"))
        XCTAssertEqual(alternatives.evaluationSourceSHA256, ordinary.evaluationSourceSHA256)
    }

    func testIntendedLabelsAndRecordedAppReadsDoNotReachTheAlternativeSearch() throws {
        var run = makeRun()
        let before = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder(), grouping: .losslessSourceV2,
            includesCompleteTokenHypotheses: true)
        run.records[0].intended = "F#13"
        run.records[0].baseline = "D7"; run.records[0].personalized = "E-7"
        let after = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder(), grouping: .losslessSourceV2,
            includesCompleteTokenHypotheses: true)
        XCTAssertEqual(after.rows[0].prediction, before.rows[0].prediction)
        XCTAssertEqual(after.rows[0].completeTokenHypotheses, before.rows[0].completeTokenHypotheses)
        XCTAssertNotEqual(after.rows[0].intended, before.rows[0].intended)
        XCTAssertTrue(run.profile.examples.isEmpty)
    }

    func testUnsupportedGroupingCannotEncodeOrBypassSelectiveOwnership() throws {
        for grouping in [PersonalInkLearnedComparison.Grouping.legacyGeometryV1, .selectiveLosslessOwnershipV3] {
            let encoder = Encoder()
            XCTAssertThrowsError(try PersonalInkLearnedRunReport.compare(makeRun(), encoder: encoder, grouping: grouping,
                includesCompleteTokenHypotheses: true)) { error in
                guard case PersonalInkLearnedComparison.Failure.unsupportedHypothesisGrouping = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(encoder.calls, 0)
        }
        let run = makeRun()
        let selective = try PersonalInkLearnedComparison(profile: run.profile, encoder: Encoder(), grouping: .selectiveLosslessOwnershipV3)
            .predict(ink, currentProfile: run.profile)
        XCTAssertThrowsError(try PersonalInkMLChordHypothesisComparison.make(prediction: selective, sourceStrokeCount: ink.count))
        XCTAssertNotNil(selective.ownership)
        XCTAssertTrue(selective.glyphs.isEmpty)
        XCTAssertNil(selective.genericChord)
    }

    func testHypothesesRoundTripSeparatelyWhileLegacyRowsRemainAbsent() throws {
        let run = makeRun()
        let ordinary = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        let oldData = try JSONEncoder().encode(ordinary)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("completeTokenHypotheses"))
        let legacy = try JSONDecoder().decode(PersonalInkLearnedRunReport.self, from: oldData)
        XCTAssertNil(legacy.rows[0].completeTokenHypotheses)
        XCTAssertNil(legacy.completeTokenHypothesisVersion)
        let report = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder(), grouping: .losslessSourceV2,
            includesCompleteTokenHypotheses: true)
        let decoded = try JSONDecoder().decode(PersonalInkLearnedRunReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(decoded.rows[0].completeTokenHypotheses, report.rows[0].completeTokenHypotheses)
        XCTAssertEqual(decoded.scorecard, report.scorecard)
        XCTAssertEqual(decoded.completeTokenHypothesisVersion, PersonalInkMLChordHypothesisComparison.version)
    }

    func testRequestedMethodSurvivesWhenEveryRowHasNoSavedRecognitionInput() throws {
        var run = makeRun()
        for index in run.records.indices { run.records[index].recognitionStrokes = nil }
        let report = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder(), grouping: .losslessSourceV2,
            includesCompleteTokenHypotheses: true)
        XCTAssertFalse(report.rows.isEmpty)
        XCTAssertTrue(report.rows.allSatisfy { $0.prediction == nil && $0.completeTokenHypotheses == nil })
        XCTAssertEqual(report.groupingVersion, PersonalInkLearnedComparison.Grouping.losslessSourceV2.rawValue)
        let decoded = try JSONDecoder().decode(PersonalInkLearnedRunReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(decoded.completeTokenHypothesisVersion, PersonalInkMLChordHypothesisComparison.version)
    }
}
