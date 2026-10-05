import XCTest
@testable import iChart

/// Storage-fidelity checks for the personal template matcher. The arbitrary
/// valid chord label only exercises profile persistence; these tests make no
/// claim about music-recognition accuracy.
final class PersonalInkShapePersistenceTests: XCTestCase {
    func test129PointSkippedInteriorExtremumRemainsExactAfterLearning() throws {
        let points = (0..<129).map { index in
            InkPoint(x: Double(index), y: index == 1 ? 96 : 0)
        }
        let strokes = [InkStroke(points: points)]

        try assertExactReferenceSurvivesSnapshotAndReload(strokes)
    }

    func test257PointSkippedAlternatingExtremaRemainExactAfterLearning() throws {
        let points = (0..<257).map { index -> InkPoint in
            let y: Double
            switch index {
            case 1: y = 88
            case 2: y = -76
            default: y = 0
            }
            return InkPoint(x: Double(index), y: y)
        }
        let strokes = [InkStroke(points: points)]

        try assertExactReferenceSurvivesSnapshotAndReload(strokes)
    }

    func testDenseMultistrokeSkippedExtremaRemainExactAfterLearning() throws {
        let first = InkStroke(points: (0..<129).map { index in
            InkPoint(x: Double(index), y: index == 1 ? 110 : 0)
        })
        let second = InkStroke(points: (0..<257).map { index -> InkPoint in
            let y: Double
            switch index {
            case 1: y = -64
            case 2: y = 102
            default: y = 38
            }
            return InkPoint(x: 170 + Double(index) * 0.5, y: y)
        })

        try assertExactReferenceSurvivesSnapshotAndReload([first, second])
    }

    private func assertExactReferenceSurvivesSnapshotAndReload(
        _ strokes: [InkStroke],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        XCTAssertTrue(
            try profile.learn(strokes: strokes, label: "C", kind: .chord, source: .setup),
            file: file,
            line: line
        )
        XCTAssertEqual(profile.examples.count, 1, file: file, line: line)
        XCTAssertTrue(
            zip(profile.examples[0].strokes, strokes).allSatisfy { stored, original in
                stored.points.count < original.points.count
            },
            "The fixture must exercise bounded dense-stroke storage",
            file: file,
            line: line
        )

        try assertExactReference(
            PersonalInkSnapshot(profile: profile),
            matches: strokes,
            file: file,
            line: line
        )

        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(PersonalInkProfile.self, from: encoded)
        XCTAssertEqual(decoded, profile, file: file, line: line)
        try assertExactReference(
            PersonalInkSnapshot(profile: decoded),
            matches: strokes,
            file: file,
            line: line
        )
    }

    private func assertExactReference(
        _ snapshot: PersonalInkSnapshot,
        matches strokes: [InkStroke],
        file: StaticString,
        line: UInt
    ) throws {
        XCTAssertTrue(
            snapshot.wasAlreadyLearned(strokes: strokes),
            "An exact replay must remain the learned reference after bounded storage",
            file: file,
            line: line
        )
        let suggestion = try XCTUnwrap(
            snapshot.suggestion(strokes: strokes),
            "An exact replay must retain its stored personal suggestion",
            file: file,
            line: line
        )
        XCTAssertEqual(suggestion.text, "C", file: file, line: line)
        XCTAssertEqual(
            suggestion.distance,
            0,
            accuracy: 1e-12,
            "Stored and fresh views of the same lesson must use one recognition descriptor",
            file: file,
            line: line
        )
    }
}
