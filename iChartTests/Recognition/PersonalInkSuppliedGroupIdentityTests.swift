import XCTest
@testable import iChart

/// Synthetic source-contract checks only. These tests do not measure handwriting
/// quality, ownership correctness, confidence, or complete-chord recognition.
final class PersonalInkSuppliedGroupIdentityTests: XCTestCase {
    private final class SpyEncoder: PersonalInkVisualEncoding {
        let identity = "synthetic-supplied-group-identity-only"
        let vocabulary = ["A", "B", "7"]
        let suppliesAnchorBank: Bool
        var inputs: [[InkStroke]] = []

        init(suppliesAnchorBank: Bool = false) {
            self.suppliesAnchorBank = suppliesAnchorBank
        }

        var anchorBank: PersonalInkAnchorBank? {
            guard suppliesAnchorBank else { return nil }
            return .init(
                vocabulary: vocabulary,
                features: vocabulary.indices.map(Self.unit)
            )
        }

        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            inputs.append(strokes)
            let signature = strokes.flatMap(\.points).reduce(0.0) { partial, point in
                partial + point.x * 3 + point.y * 5
            }
            let index = Int(abs(signature.rounded())) % vocabulary.count
            var logits = [Double](repeating: -3, count: vocabulary.count)
            logits[index] = 3
            return .init(embedding: Self.unit(index), genericLogits: logits)
        }

        private static func unit(_ index: Int) -> [Double] {
            (0..<128).map { $0 == index ? 1 : 0 }
        }
    }

    private enum ExpectedFailure {
        case disabled
        case staleProfile
        case invalidInk
    }

    private var enabledProfile: PersonalInkProfile {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        return profile
    }

    func testEveryInvalidPartitionAndPreparedGeometryFailBeforeEncoding() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let source = makeSource(count: 3)
        let seventeen = makeSource(count: 17)
        let emptyStroke = [InkStroke(points: [], bounds: .zero)]
        let nonFiniteGeometry = [InkStroke(
            points: [.init(x: .nan, y: 4), .init(x: 8, y: 12)],
            bounds: .init(minX: 0, minY: 0, maxX: 8, maxY: 12)
        )]
        var invalidBounds = source
        invalidBounds[1].bounds = InkBounds(minX: 8, minY: 4, maxX: 7, maxY: 9)
        let tooManyStrokes = makeSource(count: ChordInkFeatureSchema.maximumStrokeCount + 1)
        let tooManyPoints = [InkStroke(points: (0...ChordInkFeatureSchema.maximumInputPointCount).map {
            InkPoint(x: Double($0) * 0.01, y: Double($0 % 7))
        })]

        let invalidCases: [(name: String, source: [InkStroke], groups: [[Int]])] = [
            ("empty source and partition", [], []),
            ("empty partition", source, []),
            ("empty group", source, [[0], [], [1, 2]]),
            ("empty stroke", emptyStroke, [[0]]),
            ("incomplete coverage", source, [[0, 1]]),
            ("duplicate index", source, [[0, 0], [1]]),
            ("negative index", source, [[0, 1, -1]]),
            ("out-of-range index", source, [[0, 1, 3]]),
            ("seventeen groups", seventeen, (0..<17).map { [$0] }),
            ("nonfinite point geometry", nonFiniteGeometry, [[0]]),
            ("invalid stored bounds", invalidBounds, [[0, 1, 2]]),
            ("stroke complexity limit", tooManyStrokes, [Array(tooManyStrokes.indices)]),
            ("point complexity limit", tooManyPoints, [[0]])
        ]

        for invalid in invalidCases {
            assertFailure(.invalidInk, invalid.name) {
                try model.readSuppliedOriginalGroups(
                    invalid.source,
                    originalIndexGroups: invalid.groups,
                    currentProfile: profile
                )
            }
            XCTAssertTrue(
                encoder.inputs.isEmpty,
                "\(invalid.name) must fail before the first query encode"
            )
        }
    }

    func testSinglePointZeroExtentGroupEncodesExactOriginalWithoutInventedGeometry() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let point = InkPoint(x: 17.25, y: 42.5, timeOffset: 0.125)
        let source = [InkStroke(
            points: [point],
            bounds: InkBounds(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y),
            creationTimeOffset: 3.75
        )]

        let reading = try model.readSuppliedOriginalGroups(
            source,
            originalIndexGroups: [[0]],
            currentProfile: profile
        )

        XCTAssertEqual(encoder.inputs, [source])
        XCTAssertEqual(encoder.inputs[0][0].points, [point])
        XCTAssertEqual(encoder.inputs[0][0].bounds.width, 0)
        XCTAssertEqual(encoder.inputs[0][0].bounds.height, 0)
        XCTAssertEqual(encoder.inputs[0][0].creationTimeOffset, 3.75)
        XCTAssertEqual(reading.glyphs.map(\.originalStrokeIndexes), [[0]])
        XCTAssertEqual(reading.sourceStrokeCount, 1)
    }

    func testDisabledAndStaleProfilesFailBeforeEncoding() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let source = makeSource(count: 2)

        var disabled = profile
        disabled.isEnabled = false
        assertFailure(.disabled, "disabled profile") {
            try model.readSuppliedOriginalGroups(
                source,
                originalIndexGroups: [[0], [1]],
                currentProfile: disabled
            )
        }

        var stale = profile
        stale.learnsFromReviews.toggle()
        assertFailure(.staleProfile, "stale profile") {
            try model.readSuppliedOriginalGroups(
                source,
                originalIndexGroups: [[0], [1]],
                currentProfile: stale
            )
        }
        XCTAssertTrue(encoder.inputs.isEmpty)
    }

    func testDeclaredGroupOrderUsesAcquisitionOrderAndExactOriginalMetadata() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let source = makeSource(count: 4)

        let reading = try model.readSuppliedOriginalGroups(
            source,
            originalIndexGroups: [[3, 1], [2, 0]],
            currentProfile: profile
        )

        let expectedInputs = [[source[1], source[3]], [source[0], source[2]]]
        XCTAssertEqual(reading.sourceStrokeCount, source.count)
        XCTAssertEqual(reading.encoderIdentity, encoder.identity)
        XCTAssertEqual(reading.glyphs.map(\.originalStrokeIndexes), [[1, 3], [0, 2]])
        XCTAssertEqual(encoder.inputs, expectedInputs)
        XCTAssertEqual(encoder.inputs[0][0].bounds, source[1].bounds)
        XCTAssertEqual(encoder.inputs[0][0].creationTimeOffset, source[1].creationTimeOffset)
        XCTAssertEqual(encoder.inputs[0][0].points, source[1].points)
        XCTAssertEqual(encoder.inputs[1][1].bounds, source[2].bounds)
        XCTAssertEqual(encoder.inputs[1][1].creationTimeOffset, source[2].creationTimeOffset)
        XCTAssertEqual(encoder.inputs[1][1].points, source[2].points)
    }

    func testSuppliedPartitionRanksEqualLosslessRanksForTheSamePartition() throws {
        let profile = try profileWithGlyphLessons()
        let encoder = SpyEncoder(suppliesAnchorBank: true)
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let source = makeSource(count: 5)
        encoder.inputs.removeAll()

        let automatic = try model.predict(
            source,
            currentProfile: profile,
            grouping: .losslessSourceV2
        )
        let automaticInputs = encoder.inputs
        let partition = automatic.glyphs.map(\.originalStrokeIndexes)
        let automaticAnchored = try XCTUnwrap(automatic.anchored)
        XCTAssertFalse(partition.isEmpty)
        XCTAssertEqual(automaticInputs.count, partition.count, "This profile has no whole-chord head")

        encoder.inputs.removeAll()
        let supplied = try model.readSuppliedOriginalGroups(
            source,
            originalIndexGroups: partition,
            currentProfile: profile
        )

        XCTAssertEqual(supplied.glyphs, automatic.glyphs)
        XCTAssertEqual(try XCTUnwrap(supplied.anchoredGlyphRanks), automaticAnchored.glyphRanks)
        XCTAssertEqual(encoder.inputs, automaticInputs)
        XCTAssertEqual(supplied.glyphs.flatMap(\.originalStrokeIndexes).sorted(), Array(source.indices))
    }

    func testSuppliedGroupReadNeverRunsWholeChordHeadAndDoesNotChangeProfile() throws {
        let profile = try profileWithWholeChordLessons()
        let frozenProfile = profile
        let encoder = SpyEncoder(suppliesAnchorBank: true)
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        XCTAssertEqual(model.wholeChordLessonCount, 2)
        let source = makeSource(count: 4)
        let groups = [[0, 2], [1, 3]]
        encoder.inputs.removeAll()

        let reading = try model.readSuppliedOriginalGroups(
            source,
            originalIndexGroups: groups,
            currentProfile: profile
        )

        XCTAssertEqual(encoder.inputs, [[source[0], source[2]], [source[1], source[3]]])
        XCTAssertEqual(encoder.inputs.count, groups.count, "No full-source whole-head query may run")
        XCTAssertEqual(reading.glyphs.count, groups.count)
        XCTAssertEqual(try XCTUnwrap(reading.anchoredGlyphRanks).count, groups.count)
        XCTAssertEqual(profile, frozenProfile)
        XCTAssertEqual(model.profile, frozenProfile)
    }

    func testSelectiveOwnershipRouteStillReturnsBeforeAnyQueryEncoding() throws {
        let profile = try profileWithWholeChordLessons()
        let frozenProfile = profile
        let encoder = SpyEncoder(suppliesAnchorBank: true)
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        encoder.inputs.removeAll()

        let prediction = try model.predict(
            makeSource(count: 4),
            currentProfile: profile,
            grouping: .selectiveLosslessOwnershipV3
        )

        XCTAssertTrue(encoder.inputs.isEmpty, "Selective ownership must not read query groups or the whole chord")
        XCTAssertTrue(prediction.glyphs.isEmpty)
        XCTAssertTrue(prediction.wholeChordRanks.isEmpty)
        XCTAssertNil(prediction.genericChord)
        XCTAssertNil(prediction.personalChord)
        XCTAssertNil(prediction.anchored)
        XCTAssertEqual(prediction.ownership?.disposition, .unresolved)
        XCTAssertEqual(profile, frozenProfile)
        XCTAssertEqual(model.profile, frozenProfile)
    }

    private func makeSource(count: Int) -> [InkStroke] {
        (0..<count).map { index in
            let x = Double(index * 29 + 5)
            let y = Double(index * 13 + 7)
            let points = [
                InkPoint(x: x, y: y, timeOffset: Double(index) * 0.01 + 0.001),
                InkPoint(x: x + Double(index % 3 + 4), y: y + 8, timeOffset: Double(index) * 0.01 + 0.041),
                InkPoint(x: x + 9, y: y + Double(index % 4 + 11), timeOffset: Double(index) * 0.01 + 0.083)
            ]
            return InkStroke(
                points: points,
                bounds: InkBounds(
                    minX: x - 0.25,
                    minY: y - 0.5,
                    maxX: x + 9.75,
                    maxY: y + Double(index % 4 + 11) + 0.75
                ),
                creationTimeOffset: Double(index) + 0.375
            )
        }
    }

    private func profileWithGlyphLessons() throws -> PersonalInkProfile {
        var profile = enabledProfile
        try profile.learn(strokes: [lessonStroke(horizontal: false)], label: "A", kind: .glyph, source: .setup)
        try profile.learn(strokes: [lessonStroke(horizontal: true)], label: "B", kind: .glyph, source: .setup)
        return profile
    }

    private func profileWithWholeChordLessons() throws -> PersonalInkProfile {
        var profile = enabledProfile
        try profile.learn(strokes: [lessonStroke(horizontal: false)], label: "C", kind: .chord, source: .setup)
        try profile.learn(strokes: [lessonStroke(horizontal: true)], label: "D", kind: .chord, source: .setup)
        return profile
    }

    private func lessonStroke(horizontal: Bool) -> InkStroke {
        horizontal
            ? InkStroke(points: [.init(x: 0, y: 0), .init(x: 20, y: 0)])
            : InkStroke(points: [.init(x: 0, y: 0), .init(x: 0, y: 20)])
    }

    private func assertFailure<T>(
        _ expected: ExpectedFailure,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), context, file: file, line: line) { error in
            guard let failure = error as? PersonalInkLearnedComparison.Failure else {
                return XCTFail("Unexpected error for \(context): \(error)", file: file, line: line)
            }
            switch (expected, failure) {
            case (.disabled, .disabled), (.staleProfile, .staleProfile), (.invalidInk, .invalidInk):
                break
            default:
                XCTFail("Unexpected failure for \(context): \(failure)", file: file, line: line)
            }
        }
    }
}
