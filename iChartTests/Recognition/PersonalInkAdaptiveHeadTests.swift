import XCTest
@testable import iChart

final class PersonalInkAdaptiveHeadTests: XCTestCase {
    private let a = [InkStroke(points: [InkPoint(x: 0, y: 30), InkPoint(x: 10, y: 0), InkPoint(x: 20, y: 30)]),
                     InkStroke(points: [InkPoint(x: 5, y: 18), InkPoint(x: 15, y: 18)])]
    private let b = [InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 0, y: 30), InkPoint(x: 20, y: 30),
                                      InkPoint(x: 24, y: 20), InkPoint(x: 0, y: 15), InkPoint(x: 20, y: 12),
                                      InkPoint(x: 18, y: 0), InkPoint(x: 0, y: 0)])]

    func testRidgeSolveMatchesClosedFormAndBalancesDuplicateClassWeight() throws {
        let model = try PersonalInkBalancedRidge.fit(features: [[1, 0], [0, 1]], labels: ["one", "two"], regularization: 0.1)
        XCTAssertEqual(model.weights[0][0], 1 / 1.1, accuracy: 1e-12)
        XCTAssertEqual(model.weights[0][1], 0, accuracy: 1e-12)
        let repeated = try PersonalInkBalancedRidge.fit(features: Array(repeating: [1, 0], count: 6) + [[0, 1]],
            labels: Array(repeating: "one", count: 6) + ["two"], regularization: 0.1)
        for (left, right) in zip(model.weights.flatMap { $0 }, repeated.weights.flatMap { $0 }) {
            XCTAssertEqual(left, right, accuracy: 1e-12)
        }
    }

    func testFittedWeightsSatisfyWeightedNormalEquation() throws {
        let features = [[0.1, 0.3, 0.7], [0.4, -0.1, 0.2], [0.9, 0.1, 0.4], [-0.2, 0.8, 0.5]]
        let labels = ["x", "x", "y", "z"]
        let model = try PersonalInkBalancedRidge.fit(features: features, labels: labels, regularization: 0.3)
        for (c, label) in model.labels.enumerated() {
            for d in 0..<3 {
                var derivative = 0.3 * model.weights[c][d]
                for (i, row) in features.enumerated() {
                    let value = zip(row, model.weights[c]).reduce(0.0) { $0 + $1.0 * $1.1 }
                    let frequency = Double(labels.filter { $0 == labels[i] }.count)
                    derivative += row[d] * (value - (labels[i] == label ? 1 : 0)) / frequency
                }
                XCTAssertEqual(derivative, 0, accuracy: 1e-12)
            }
        }
    }

    func testMalformedAndSingleLabelTrainingCannotProduceAModel() {
        for (x, y) in [([[Double.nan]], ["a"]), ([[1], [1, 2]], ["a", "b"]),
                       ([[1], [2]], ["a", "a"]), ([[1], [2]], ["a"]), ([], [])] {
            XCTAssertThrowsError(try PersonalInkBalancedRidge.fit(features: x, labels: y, regularization: 0.1))
        }
        for penalty in [0, -1, Double.infinity, Double.nan] {
            XCTAssertThrowsError(try PersonalInkBalancedRidge.fit(features: [[1], [2]], labels: ["a", "b"], regularization: penalty))
        }
    }

    func testExplicitExamplesTrainWeightsWithoutChangingProfileOrBaseSuggestions() throws {
        let profile = try makeProfile()
        let preserved = profile
        let legacy = PersonalInkSnapshot(profile: profile).suggestion(strokes: a)
        let head = try PersonalInkAdaptiveHead(profile: profile, kind: .glyph)
        XCTAssertEqual(head.exampleCount, 2)
        XCTAssertEqual(head.labels, ["A", "B"])
        XCTAssertEqual(head.rankedCandidates(strokes: a).first?.label, "A")
        XCTAssertEqual(head.rankedCandidates(strokes: b).first?.label, "B")
        let moved = a.reversed().map { stroke in
            InkStroke(points: stroke.points.reversed().map { InkPoint(x: $0.x * 2.5 + 150, y: $0.y * 2.5 - 60) })
        }
        XCTAssertEqual(head.rankedCandidates(strokes: moved).first?.label, "A")
        XCTAssertEqual(head.rankedCandidates(strokes: []).count, 0)
        XCTAssertEqual(profile, preserved)
        XCTAssertEqual(PersonalInkSnapshot(profile: profile).suggestion(strokes: a), legacy)
    }

    func testCorrectionRebuildsOnlyNewSnapshotAndWholeLabelsCannotBecomeGlyphLessons() throws {
        var profile = try makeProfile()
        let frozen = try PersonalInkAdaptiveHead(profile: profile, kind: .glyph)
        try profile.learn(strokes: a, label: "C", kind: .glyph, source: .explicitCorrection)
        try profile.learn(strokes: b, label: "Ebmaj7", kind: .chord, source: .explicitCorrection)
        let updated = try PersonalInkAdaptiveHead(profile: profile, kind: .glyph)
        XCTAssertEqual(updated.labels, ["B", "C"])
        XCTAssertEqual(updated.rankedCandidates(strokes: a).first?.label, "C")
        XCTAssertEqual(frozen.rankedCandidates(strokes: a).first?.label, "A")
        XCTAssertNotEqual(updated.profileRevision, frozen.profileRevision)
        XCTAssertEqual(updated.exampleCount, 2)
    }

    func testContradictoryExamplesHaveTiedScoresNotInventedCertainty() throws {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        try profile.learn(strokes: a, label: "A", kind: .glyph, source: .setup)
        try profile.learn(strokes: a, label: "B", kind: .glyph, source: .setup)
        let rows = try PersonalInkAdaptiveHead(profile: profile, kind: .glyph).rankedCandidates(strokes: a)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].score, rows[1].score, accuracy: 1e-12)
    }

    func testOptOutPreventsTrainingWithoutDeletingExamples() throws {
        var profile = try makeProfile()
        profile.isEnabled = false
        let before = profile
        XCTAssertThrowsError(try PersonalInkAdaptiveHead(profile: profile, kind: .glyph)) { error in
            guard case PersonalInkAdaptiveHead.Failure.disabled = error else {
                return XCTFail("Opt-out must win before feature extraction")
            }
        }
        XCTAssertEqual(profile, before)
    }

    private func makeProfile() throws -> PersonalInkProfile {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        try profile.learn(strokes: a, label: "A", kind: .glyph, source: .setup)
        try profile.learn(strokes: b, label: "B", kind: .glyph, source: .setup)
        return profile
    }
}
