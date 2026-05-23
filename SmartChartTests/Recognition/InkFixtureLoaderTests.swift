import XCTest
@testable import SmartChart

final class InkFixtureLoaderTests: XCTestCase {
    func testLoadsInkFixtureFromDiskWithoutPencilKit() throws {
        let fixture = try InkFixtureLoader.load("C", file: #filePath)

        XCTAssertEqual(fixture.name, "C")
        XCTAssertEqual(fixture.expectedDisplayText, "C")
        XCTAssertEqual(fixture.expectedClusterCount, 1)
        XCTAssertEqual(fixture.expectedTopGlyphs, ["C"])
        XCTAssertEqual(fixture.strokes.count, 1)
        XCTAssertEqual(fixture.strokes.first?.points.count, 6)
        XCTAssertEqual(
            fixture.strokes.first?.bounds,
            InkBounds(minX: 12, minY: 12, maxX: 43, maxY: 55)
        )
    }

    func testLoadsAllInkFixturesInStableOrder() throws {
        let fixtureNames = try InkFixtureLoader.fixtureNames(file: #filePath)
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        let seedFixtureNames = Set(["Bb", "C", "CMajor7Triangle", "CMinor", "CMinor7", "Db7b9", "FSharp", "GSlashB"])
        let sortedFixtureNames = fixtureNames.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        XCTAssertEqual(fixtureNames, sortedFixtureNames)
        XCTAssertTrue(Set(fixtureNames).isSuperset(of: seedFixtureNames))
        XCTAssertEqual(fixtures.map(\.name), fixtureNames)
    }
}
