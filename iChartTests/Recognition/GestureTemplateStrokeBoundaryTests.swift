import XCTest
@testable import iChart

/// Synthetic normalization integrity only; these tests do not establish recognition accuracy.
final class GestureTemplateStrokeBoundaryTests: XCTestCase {
    func testExistingMemberwiseConfigurationAndDefaultRemainLegacy() {
        let configuration = GestureTemplateRecognizerConfiguration(
            samplePointCount: 8,
            aspectRatioWeight: 0.18,
            strokeCountWeight: 0.12
        )
        XCTAssertEqual(configuration.normalizationMode, .legacyJoinedPath)
        XCTAssertEqual(GestureTemplateRecognizerConfiguration.chordGlyphs.normalizationMode, .legacyJoinedPath)
        XCTAssertEqual(GestureTemplateRecognizer().configuration.normalizationMode, .legacyJoinedPath)
    }

    func testCandidateNeverSamplesThePenLiftBetweenDisconnectedPaths() throws {
        let strokes = [stroke([(0, 0), (10, 0)]), stroke([(100, 0), (110, 0)])]
        let legacy = try samples(strokes, count: 8, mode: .legacyJoinedPath)
        let candidate = try samples(strokes, count: 8)
        XCTAssertTrue(legacy.contains { $0.x > 10 && $0.x < 100 })
        XCTAssertEqual(candidate.count, 8)
        XCTAssertTrue(candidate.allSatisfy { $0.y == 0 && ($0.x <= 10 || $0.x >= 100) })
        XCTAssertEqual(candidate.first, strokes[0].points.first)
        XCTAssertEqual(candidate[3], strokes[0].points.last)
        XCTAssertEqual(candidate[4], strokes[1].points.first)
        XCTAssertEqual(candidate.last, strokes[1].points.last)
    }

    func testFlatteningCollisionTiesLegacyButCandidateRetainsBoundaryDifference() throws {
        let first = [stroke([(0, 0), (10, 0)]), stroke([(100, 0), (110, 0)])]
        let second = [stroke([(0, 0)]), stroke([(10, 0), (100, 0), (110, 0)])]
        XCTAssertEqual(first.flatMap(\.points), second.flatMap(\.points))
        XCTAssertEqual(first.count, second.count)
        assertPointBitsEqual(try samples(first, count: 8, mode: .legacyJoinedPath),
                             try samples(second, count: 8, mode: .legacyJoinedPath))
        XCTAssertNotEqual(try samples(first, count: 8), try samples(second, count: 8))

        let templates = [GestureTemplate(text: "C", strokes: first), GestureTemplate(text: "D", strokes: second)]
        let legacy = recognizer(mode: .legacyJoinedPath).rankedCandidates(for: InkCluster(strokes: first), templates: templates)
        let candidate = recognizer(mode: .preserveStrokeBoundaries).rankedCandidates(for: InkCluster(strokes: first), templates: templates)
        let legacyC = try XCTUnwrap(legacy.first { $0.text == "C" })
        let legacyD = try XCTUnwrap(legacy.first { $0.text == "D" })
        XCTAssertEqual(legacyC.source, .template)
        XCTAssertEqual(legacyD.source, .template)
        XCTAssertEqual(legacyC.confidence, legacyD.confidence)
        XCTAssertEqual(try XCTUnwrap(candidate.first { $0.text == "C" }).confidence, 1)
        XCTAssertLessThan(try XCTUnwrap(candidate.first { $0.text == "D" }).confidence, 1)
    }

    func testNonzeroStrokeEndpointsAndDotSurviveAtExactMinimumBudget() throws {
        let strokes = [stroke([(0, 0), (100, 0)]), stroke([(20, 10), (21, 10)]), stroke([(60, 20)])]
        let result = try samples(strokes, count: 5)
        XCTAssertEqual(result, strokes.flatMap(\.points))
        XCTAssertNil(sampled(strokes, count: 4))
        let expanded = try samples(strokes, count: 48)
        XCTAssertEqual(expanded.count, 48)
        XCTAssertEqual(expanded.filter { $0.y == 20 }, strokes[2].points)
        XCTAssertTrue(expanded.contains(strokes[1].points[0]))
        XCTAssertTrue(expanded.contains(strokes[1].points[1]))
    }

    func testProportionalAllocationAndLargestRemainderTiesUseStrokeOrder() throws {
        let unequal = [stroke([(0, 0), (1, 0)]), stroke([(0, 10), (3, 10)])]
        let weighted = try samples(unequal, count: 12)
        XCTAssertEqual(weighted.filter { $0.y == 0 }.count, 4)
        XCTAssertEqual(weighted.filter { $0.y == 10 }.count, 8)

        let equal = [stroke([(0, 0), (1, 0)]), stroke([(0, 10), (1, 10)]), stroke([(0, 20), (1, 20)])]
        let residual = try samples(equal, count: 8)
        XCTAssertEqual([0.0, 10.0, 20.0].map { y in residual.filter { $0.y == y }.count }, [3, 3, 2])
        XCTAssertEqual(residual, try samples(equal, count: 8))
    }

    func testDotsEmptyPathsAndExactCountClampWithoutInventedGeometry() throws {
        let dots = [stroke([(1, 2)]), stroke([]), stroke([(5, 6)]), stroke([(9, 10)])]
        let result = try samples(dots, count: 8)
        XCTAssertEqual(result.count, 8)
        XCTAssertEqual([1.0, 5.0, 9.0].map { x in result.filter { $0.x == x }.count }, [3, 3, 2])
        XCTAssertTrue(result.allSatisfy { dots.flatMap(\.points).contains($0) })
        XCTAssertEqual(try samples([stroke([]), stroke([(4, 5)]), stroke([])], count: -20),
                       Array(repeating: InkPoint(x: 4, y: 5, timeOffset: nil), count: 2))
        XCTAssertNil(sampled([], count: 48))
        XCTAssertNil(sampled([stroke([]), stroke([])], count: 48))
        for count in [3, 4, 5, 11, 48] {
            XCTAssertEqual(try samples(dots, count: count).count, count)
        }
    }

    func testCapacityOverflowFailsInsteadOfDroppingAnyStroke() {
        let dots = (0..<5).map { stroke([(Double($0), 0)]) }
        XCTAssertNil(sampled(dots, count: 4))
        XCTAssertNil(sampled(Array(dots.prefix(3)), count: 0))
        let paths = (0..<3).map { stroke([(0, Double($0)), (1, Double($0))]) }
        XCTAssertNil(sampled(paths, count: 5))
        var configuration = GestureTemplateRecognizerConfiguration.chordGlyphs
        configuration.samplePointCount = 5
        configuration.normalizationMode = .preserveStrokeBoundaries
        XCTAssertTrue(GestureTemplateRecognizer(configuration: configuration).rankedCandidates(
            for: InkCluster(strokes: paths), templates: [GestureTemplate(text: "C", strokes: paths)]
        ).isEmpty)
    }

    func testCandidateRejectsNonfiniteCoordinatesAndLengthsIncludingSingleStroke() {
        for coordinate in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(sampled([stroke([(coordinate, 0)])], count: 8))
            XCTAssertNil(sampled([stroke([(0, 0), (1, 0)]), stroke([(0, coordinate)])], count: 8))
        }
        XCTAssertNil(sampled([stroke([(-Double.greatestFiniteMagnitude, 0), (Double.greatestFiniteMagnitude, 0)])], count: 8))
        XCTAssertNil(sampled([stroke([(-Double.greatestFiniteMagnitude, 0)]), stroke([(Double.greatestFiniteMagnitude, 0)])], count: 8))
    }

    func testSingleNonemptyStrokeHasBitExactLegacySamplingAndCandidateOutput() throws {
        let paths = [stroke([(2, 3)]), stroke([(0, 0), (0, 0), (7, 11), (20, 4)]), stroke([(3, 5), (3, 5)])]
        for path in paths {
            for count in [-2, 2, 3, 17, 48] {
                let strokes = [stroke([]), path, stroke([])]
                assertPointBitsEqual(try samples(strokes, count: count, mode: .legacyJoinedPath),
                                     try samples(strokes, count: count))
                let templates = [GestureTemplate(text: "C", strokes: strokes)]
                let cluster = InkCluster(strokes: strokes)
                XCTAssertEqual(recognizer(mode: .legacyJoinedPath, count: count).rankedCandidates(for: cluster, templates: templates),
                               recognizer(mode: .preserveStrokeBoundaries, count: count).rankedCandidates(for: cluster, templates: templates))
            }
        }
    }

    func testSamplingAndRankingDoNotMutateSourceInk() throws {
        let strokes = [stroke([(0, 0), (10, 0)], timed: true), stroke([(100, 20), (110, 20)], timed: true)]
        let original = strokes
        let templates = [GestureTemplate(text: "C", strokes: strokes)]
        let cluster = InkCluster(strokes: strokes)
        for mode in [GestureTemplateNormalizationMode.legacyJoinedPath, .preserveStrokeBoundaries] {
            _ = try samples(strokes, count: 48, mode: mode)
            _ = recognizer(mode: mode, count: 48).rankedCandidates(for: cluster, templates: templates)
        }
        XCTAssertEqual(strokes, original)
        XCTAssertEqual(cluster.strokes, original)
        XCTAssertEqual(templates[0].strokes, original)
    }

    func testTemplateCacheSeparatesModesAndCanReturnToLegacy() {
        let strokes = [stroke([(0, 0), (10, 0)]), stroke([(100, 0), (110, 0)])]
        let templates = [GestureTemplate(text: "C", strokes: strokes)]
        let cluster = InkCluster(strokes: strokes)
        var shared = recognizer(mode: .legacyJoinedPath)
        let expectedLegacy = recognizer(mode: .legacyJoinedPath).rankedCandidates(for: cluster, templates: templates)
        XCTAssertEqual(shared.rankedCandidates(for: cluster, templates: templates), expectedLegacy)
        shared.configuration.normalizationMode = .preserveStrokeBoundaries
        let expectedCandidate = recognizer(mode: .preserveStrokeBoundaries).rankedCandidates(for: cluster, templates: templates)
        XCTAssertEqual(shared.rankedCandidates(for: cluster, templates: templates), expectedCandidate)
        XCTAssertEqual(expectedCandidate.first { $0.text == "C" }?.confidence, 1)
        shared.configuration.normalizationMode = .legacyJoinedPath
        XCTAssertEqual(shared.rankedCandidates(for: cluster, templates: templates), expectedLegacy)
    }

    private func sampled(_ strokes: [InkStroke], count: Int, mode: GestureTemplateNormalizationMode = .preserveStrokeBoundaries) -> [InkPoint]? {
        GestureTemplateRecognizer.normalizationSamplesForTesting(strokes: strokes, samplePointCount: count, mode: mode)
    }

    private func samples(_ strokes: [InkStroke], count: Int, mode: GestureTemplateNormalizationMode = .preserveStrokeBoundaries) throws -> [InkPoint] {
        try XCTUnwrap(sampled(strokes, count: count, mode: mode))
    }

    private func stroke(_ coordinates: [(Double, Double)], timed: Bool = false) -> InkStroke {
        InkStroke(points: coordinates.enumerated().map { index, coordinate in
            InkPoint(x: coordinate.0, y: coordinate.1, timeOffset: timed ? Double(index) * 0.01 : nil)
        }, creationTimeOffset: timed ? 0.25 : nil)
    }

    private func recognizer(mode: GestureTemplateNormalizationMode, count: Int = 8) -> GestureTemplateRecognizer {
        GestureTemplateRecognizer(configuration: GestureTemplateRecognizerConfiguration(
            samplePointCount: count, aspectRatioWeight: 0.18, strokeCountWeight: 0.12, normalizationMode: mode
        ))
    }

    private func assertPointBitsEqual(_ lhs: [InkPoint], _ rhs: [InkPoint], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for (left, right) in zip(lhs, rhs) {
            XCTAssertEqual(left.x.bitPattern, right.x.bitPattern, file: file, line: line)
            XCTAssertEqual(left.y.bitPattern, right.y.bitPattern, file: file, line: line)
            XCTAssertEqual(left.timeOffset?.bitPattern, right.timeOffset?.bitPattern, file: file, line: line)
        }
    }
}
