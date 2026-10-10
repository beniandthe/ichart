#if canImport(PencilKit) && canImport(UIKit)
import PencilKit
import UIKit
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyTrajectoryTests: XCTestCase {
    func testPreparedTrajectoryCanonicalRoundTripPreservesEveryStoredValue() throws {
        let negativeZero = Double(bitPattern: 0x8000_0000_0000_0000)
        let payloadNaN = Double(bitPattern: 0x7ff8_0000_0000_0042)
        let source = [
            InkStroke(
                points: [
                    InkPoint(x: negativeZero, y: Double.leastNonzeroMagnitude, timeOffset: nil),
                    InkPoint(x: 12.25, y: -7.5, timeOffset: 0.125),
                    InkPoint(x: 12.25, y: -7.5, timeOffset: 0.125)
                ],
                bounds: InkBounds(minX: -99, minY: -88, maxX: 77, maxY: 66),
                creationTimeOffset: 4.5
            ),
            InkStroke(
                points: [],
                bounds: InkBounds(minX: 3, minY: 4, maxX: 3, maxY: 4),
                creationTimeOffset: payloadNaN
            )
        ]

        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: source)
        let canonicalData = try packet.canonicalData()
        let decoded = try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(
            canonicalData
        )
        let restored = decoded.preparedStrokes()

        XCTAssertEqual(try decoded.canonicalData(), canonicalData)
        XCTAssertEqual(restored.count, source.count)
        XCTAssertEqual(restored.map(\.points.count), [3, 0])
        XCTAssertEqual(decoded.pointTimingCoverage, .partial)
        XCTAssertEqual(decoded.creationTimingCoverage, .complete)
        XCTAssertEqual(decoded.timingCoverage, .partial)
        XCTAssertTrue(decoded.containsNonFiniteTiming)

        assertSameGeometryAndTiming(restored[0], source[0])
        assertSameGeometryAndTiming(restored[1], source[1])
        XCTAssertEqual(
            restored[1].creationTimeOffset?.bitPattern,
            payloadNaN.bitPattern
        )
    }

    func testExtractedTrajectoryTypesRetainBoundsAndTimelineBehavior() throws {
        let points = [
            InkPoint(x: 8, y: -2, timeOffset: 0.4),
            InkPoint(x: -3, y: 7, timeOffset: 0.1),
            InkPoint(x: 2, y: 5, timeOffset: nil)
        ]
        let stroke = InkStroke(points: points, creationTimeOffset: 10)

        XCTAssertEqual(stroke.bounds, InkBounds(minX: -3, minY: -2, maxX: 8, maxY: 7))
        XCTAssertEqual(stroke.bounds.width, 11)
        XCTAssertEqual(stroke.bounds.height, 9)
        XCTAssertEqual(stroke.timelineStartTimeOffset, 10.1)
        XCTAssertEqual(stroke.timelineEndTimeOffset, 10.4)
        XCTAssertEqual(InkBounds.enclosing([] as [InkPoint]), .zero)
        XCTAssertEqual(InkBounds.enclosing([] as [InkBounds]), .zero)
        XCTAssertEqual(
            stroke.bounds.union(InkBounds(minX: -20, minY: 0, maxX: 4, maxY: 30)),
            InkBounds(minX: -20, minY: -2, maxX: 8, maxY: 30)
        )

        let noCreationTime = InkStroke(points: points)
        XCTAssertNil(noCreationTime.timelineStartTimeOffset)
        XCTAssertNil(noCreationTime.timelineEndTimeOffset)

        let noPointTimes = InkStroke(
            points: [InkPoint(x: 1, y: 2, timeOffset: nil)],
            creationTimeOffset: 6
        )
        XCTAssertEqual(noPointTimes.timelineStartTimeOffset, 6)
        XCTAssertEqual(noPointTimes.timelineEndTimeOffset, 6)
    }

    func testPencilKitAdapterFeedsCanonicalPacketWithoutRecognitionCode() throws {
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let drawing = PKDrawing(strokes: [
            pencilStroke(
                points: [
                    (CGPoint(x: 2, y: 3), 0),
                    (CGPoint(x: 8, y: 13), 0.25)
                ],
                creationDate: origin,
                transform: CGAffineTransform(translationX: 10, y: -2)
            ),
            pencilStroke(
                points: [
                    (CGPoint(x: -4, y: 5), 0),
                    (CGPoint(x: 1, y: 9), 0.5)
                ],
                creationDate: origin.addingTimeInterval(0.75)
            )
        ])

        let prepared = PencilKitInkAdapter.inkStrokes(from: drawing)
        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: prepared)
        let decoded = try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(
            packet.canonicalData()
        )
        let restored = decoded.preparedStrokes()

        XCTAssertEqual(prepared.count, 2)
        XCTAssertEqual(prepared[0].points.map(\.x), [12, 18])
        XCTAssertEqual(prepared[0].points.map(\.y), [1, 11])
        XCTAssertEqual(prepared[0].points.map(\.timeOffset), [0, 0.25])
        XCTAssertEqual(prepared[0].creationTimeOffset, 0)
        XCTAssertEqual(prepared[1].creationTimeOffset, 0.75)
        XCTAssertEqual(restored, prepared)
    }

    private func assertSameGeometryAndTiming(
        _ actual: InkStroke,
        _ expected: InkStroke,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.points.count, expected.points.count, file: file, line: line)
        for (actualPoint, expectedPoint) in zip(actual.points, expected.points) {
            XCTAssertEqual(actualPoint.x.bitPattern, expectedPoint.x.bitPattern, file: file, line: line)
            XCTAssertEqual(actualPoint.y.bitPattern, expectedPoint.y.bitPattern, file: file, line: line)
            XCTAssertEqual(
                actualPoint.timeOffset?.bitPattern,
                expectedPoint.timeOffset?.bitPattern,
                file: file,
                line: line
            )
        }
        XCTAssertEqual(actual.bounds.minX.bitPattern, expected.bounds.minX.bitPattern, file: file, line: line)
        XCTAssertEqual(actual.bounds.minY.bitPattern, expected.bounds.minY.bitPattern, file: file, line: line)
        XCTAssertEqual(actual.bounds.maxX.bitPattern, expected.bounds.maxX.bitPattern, file: file, line: line)
        XCTAssertEqual(actual.bounds.maxY.bitPattern, expected.bounds.maxY.bitPattern, file: file, line: line)
        XCTAssertEqual(
            actual.creationTimeOffset?.bitPattern,
            expected.creationTimeOffset?.bitPattern,
            file: file,
            line: line
        )
    }

    private func pencilStroke(
        points: [(CGPoint, TimeInterval)],
        creationDate: Date,
        transform: CGAffineTransform = .identity
    ) -> PKStroke {
        PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(
                controlPoints: points.map { location, timeOffset in
                    PKStrokePoint(
                        location: location,
                        timeOffset: timeOffset,
                        size: CGSize(width: 3, height: 3),
                        opacity: 1,
                        force: 1,
                        azimuth: 0,
                        altitude: .pi / 2
                    )
                },
                creationDate: creationDate
            ),
            transform: transform,
            mask: nil
        )
    }
}
#endif
