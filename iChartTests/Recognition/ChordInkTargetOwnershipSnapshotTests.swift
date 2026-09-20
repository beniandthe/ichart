import Foundation
import XCTest
@testable import iChart

final class ChordInkTargetOwnershipSnapshotTests: XCTestCase {
    func testBuildsCanonicalExhaustiveVisibleFragmentPartition() throws {
        let snapshot = try XCTUnwrap(ChordInkTargetOwnershipSnapshot(
            sourcePencilStrokeCount: 4,
            visibleFragmentSourceStrokeIndices: [0, 1, 1, 3, 2],
            barlineVisibleFragmentIndices: [3],
            targetVisibleFragmentIndices: [[4, 0], [2]]
        ))

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.indexSpace, .visibleFragmentsBeforeBarlineFilteringV1)
        XCTAssertEqual(snapshot.sourcePencilStrokeCount, 4)
        XCTAssertEqual(snapshot.visibleFragmentSourceStrokeIndices, [0, 1, 1, 3, 2])
        XCTAssertEqual(snapshot.barlineVisibleFragmentIndices, [3])
        XCTAssertEqual(snapshot.targetGroups, [
            .init(targetOrdinal: 0, visibleFragmentIndices: [0, 4]),
            .init(targetOrdinal: 1, visibleFragmentIndices: [2])
        ])
        XCTAssertEqual(snapshot.unassignedVisibleFragmentIndices, [1])
    }

    func testRejectsOutOfRangeDuplicateAndOverlappingOwnership() {
        XCTAssertNil(ChordInkTargetOwnershipSnapshot(
            sourcePencilStrokeCount: 2,
            visibleFragmentSourceStrokeIndices: [0, 2],
            barlineVisibleFragmentIndices: [],
            targetVisibleFragmentIndices: []
        ))
        XCTAssertNil(ChordInkTargetOwnershipSnapshot(
            sourcePencilStrokeCount: 2,
            visibleFragmentSourceStrokeIndices: [0, 1],
            barlineVisibleFragmentIndices: [2],
            targetVisibleFragmentIndices: []
        ))
        XCTAssertNil(ChordInkTargetOwnershipSnapshot(
            sourcePencilStrokeCount: 2,
            visibleFragmentSourceStrokeIndices: [0, 1],
            barlineVisibleFragmentIndices: [0],
            targetVisibleFragmentIndices: [[0]]
        ))
        XCTAssertNil(ChordInkTargetOwnershipSnapshot(
            sourcePencilStrokeCount: 2,
            visibleFragmentSourceStrokeIndices: [0, 1],
            barlineVisibleFragmentIndices: [],
            targetVisibleFragmentIndices: [[0], [0, 1]]
        ))
        XCTAssertNil(ChordInkTargetOwnershipSnapshot(
            sourcePencilStrokeCount: 2,
            visibleFragmentSourceStrokeIndices: [0, 1],
            barlineVisibleFragmentIndices: [],
            targetVisibleFragmentIndices: [[1, 1]]
        ))
    }

    func testCanonicalEncodingRoundTripsDeterministically() throws {
        let snapshot = try XCTUnwrap(ChordInkTargetOwnershipSnapshot(
            sourcePencilStrokeCount: 3,
            visibleFragmentSourceStrokeIndices: [0, 1, 1, 2],
            barlineVisibleFragmentIndices: [3],
            targetVisibleFragmentIndices: [[2, 0]]
        ))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let firstEncoding = try encoder.encode(snapshot)
        let secondEncoding = try encoder.encode(snapshot)

        XCTAssertEqual(firstEncoding, secondEncoding)
        XCTAssertEqual(try JSONDecoder().decode(
            ChordInkTargetOwnershipSnapshot.self,
            from: firstEncoding
        ), snapshot)
    }
}
