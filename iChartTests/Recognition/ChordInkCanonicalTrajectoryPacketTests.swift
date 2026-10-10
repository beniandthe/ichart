import Foundation
import XCTest
@testable import iChart

final class ChordInkCanonicalTrajectoryPacketTests: XCTestCase {
    func testPreservesEveryPointStrokeBoundaryAndSourceOrder() throws {
        let strokes = [
            InkStroke(
                points: [
                    InkPoint(x: 0, y: 0, timeOffset: 0),
                    InkPoint(x: 4, y: 0, timeOffset: 0.1),
                    InkPoint(x: 4, y: 0, timeOffset: 0.1),
                    InkPoint(x: 4, y: 3, timeOffset: 0.2)
                ],
                creationTimeOffset: 1
            ),
            InkStroke(
                points: [],
                bounds: InkBounds(minX: -2, minY: -3, maxX: -2, maxY: -3),
                creationTimeOffset: nil
            ),
            InkStroke(
                points: [
                    InkPoint(x: -5, y: 8, timeOffset: 0.4)
                ],
                creationTimeOffset: 2
            )
        ]

        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: strokes)

        XCTAssertEqual(packet.strokes.count, 3)
        XCTAssertEqual(packet.coordinateSpace, .transformedPreparedDrawing)
        XCTAssertEqual(packet.strokes.map(\.points.count), [4, 0, 1])
        XCTAssertEqual(
            packet.strokes.flatMap(\.points).map(\.x.bitPattern),
            strokes.flatMap(\.points).map(\.x.bitPattern)
        )
        XCTAssertEqual(
            packet.strokes.flatMap(\.points).map(\.y.bitPattern),
            strokes.flatMap(\.points).map(\.y.bitPattern)
        )
        XCTAssertEqual(packet.preparedStrokes().map(\.bounds), strokes.map(\.bounds))
        XCTAssertEqual(packet.strokes[0].points[1], packet.strokes[0].points[2])
    }

    func testRoundTripPreservesExactGeometryBoundsAndSignedZero() throws {
        let negativeZero = Double(bitPattern: 0x8000_0000_0000_0000)
        let strokes = [
            InkStroke(
                points: [
                    InkPoint(x: negativeZero, y: 1.25, timeOffset: nil),
                    InkPoint(x: 3.5, y: -9.75, timeOffset: 0.375)
                ],
                bounds: InkBounds(
                    minX: negativeZero,
                    minY: -9.75,
                    maxX: 3.5,
                    maxY: 1.25
                ),
                creationTimeOffset: 12.5
            )
        ]

        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: strokes)
        let decoded = try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(
            packet.canonicalData()
        )
        let restored = try XCTUnwrap(decoded.preparedStrokes().first)

        XCTAssertEqual(restored.points.count, 2)
        XCTAssertEqual(restored.points[0].x.bitPattern, negativeZero.bitPattern)
        XCTAssertEqual(restored.points[0].y.bitPattern, strokes[0].points[0].y.bitPattern)
        XCTAssertEqual(restored.points[1].x.bitPattern, strokes[0].points[1].x.bitPattern)
        XCTAssertEqual(restored.points[1].y.bitPattern, strokes[0].points[1].y.bitPattern)
        XCTAssertEqual(restored.bounds.minX.bitPattern, negativeZero.bitPattern)
        XCTAssertEqual(restored.creationTimeOffset?.bitPattern, 12.5.bitPattern)
    }

    func testTimingDistinguishesMissingFiniteAndNonFiniteWithoutImputation() throws {
        let payloadNaN = Double(bitPattern: 0x7ff8_0000_0000_0042)
        let strokes = [
            InkStroke(
                points: [
                    InkPoint(x: 0, y: 0, timeOffset: nil),
                    InkPoint(x: 1, y: 1, timeOffset: 0.25),
                    InkPoint(x: 2, y: 2, timeOffset: payloadNaN),
                    InkPoint(x: 3, y: 3, timeOffset: .infinity)
                ],
                creationTimeOffset: -.infinity
            )
        ]

        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: strokes)
        let stroke = try XCTUnwrap(packet.strokes.first)

        XCTAssertEqual(stroke.creationTimeOffset.state, .nonFinite)
        XCTAssertEqual(stroke.creationTimeOffset.bitPattern, (-Double.infinity).bitPattern)
        XCTAssertEqual(stroke.points.map(\.timeOffset.state), [
            .missing,
            .finite,
            .nonFinite,
            .nonFinite
        ])
        XCTAssertNil(stroke.points[0].timeOffset.value)
        XCTAssertEqual(stroke.points[1].timeOffset.value?.bitPattern, 0.25.bitPattern)
        XCTAssertEqual(stroke.points[2].timeOffset.value?.bitPattern, payloadNaN.bitPattern)
        XCTAssertEqual(stroke.points[3].timeOffset.value?.bitPattern, Double.infinity.bitPattern)

        let roundTrippedPacket = try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(
            packet.canonicalData()
        )
        let restored = try XCTUnwrap(roundTrippedPacket.preparedStrokes().first)
        XCTAssertNil(restored.points[0].timeOffset)
        XCTAssertEqual(restored.points[1].timeOffset?.bitPattern, 0.25.bitPattern)
        XCTAssertEqual(restored.points[2].timeOffset?.bitPattern, payloadNaN.bitPattern)
        XCTAssertEqual(restored.points[3].timeOffset?.bitPattern, Double.infinity.bitPattern)
        XCTAssertEqual(restored.creationTimeOffset?.bitPattern, (-Double.infinity).bitPattern)
    }

    func testTimingCoverageIsAvailabilityOnlyAndSeparateFromNumericalValidity() throws {
        let unavailable = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(points: [
                InkPoint(x: 0, y: 0, timeOffset: nil),
                InkPoint(x: 1, y: 1, timeOffset: nil)
            ])
        ])
        XCTAssertEqual(unavailable.pointTimingCoverage, .unavailable)
        XCTAssertEqual(unavailable.creationTimingCoverage, .unavailable)
        XCTAssertEqual(unavailable.timingCoverage, .unavailable)
        XCTAssertFalse(unavailable.containsNonFiniteTiming)

        let partialAndNonFinite = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [
                    InkPoint(x: 0, y: 0, timeOffset: nil),
                    InkPoint(x: 1, y: 1, timeOffset: .nan)
                ],
                creationTimeOffset: 9
            )
        ])
        XCTAssertEqual(partialAndNonFinite.pointTimingCoverage, .partial)
        XCTAssertEqual(partialAndNonFinite.creationTimingCoverage, .complete)
        XCTAssertEqual(partialAndNonFinite.timingCoverage, .partial)
        XCTAssertTrue(partialAndNonFinite.containsNonFiniteTiming)

        // Complete means every field was present; the packet deliberately does
        // not claim these decreasing offsets are chronologically valid.
        let completeButNonMonotonic = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [
                    InkPoint(x: 0, y: 0, timeOffset: 5),
                    InkPoint(x: 1, y: 1, timeOffset: 1)
                ],
                creationTimeOffset: -3
            )
        ])
        XCTAssertEqual(completeButNonMonotonic.pointTimingCoverage, .complete)
        XCTAssertEqual(completeButNonMonotonic.creationTimingCoverage, .complete)
        XCTAssertEqual(completeButNonMonotonic.timingCoverage, .complete)
        XCTAssertFalse(completeButNonMonotonic.containsNonFiniteTiming)
    }

    func testPreservesSubnormalExtremeFiniteGeometryAndExplicitNonEnclosingBounds() throws {
        let leastPositive = Double.leastNonzeroMagnitude
        let negativeExtreme = -Double.greatestFiniteMagnitude
        let explicitBounds = InkBounds(
            minX: negativeExtreme,
            minY: -100,
            maxX: Double.greatestFiniteMagnitude,
            maxY: 100
        )
        let source = InkStroke(
            points: [
                InkPoint(x: leastPositive, y: -leastPositive, timeOffset: nil),
                InkPoint(x: 8, y: 9, timeOffset: nil)
            ],
            bounds: explicitBounds
        )

        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: [source])
        let restored = try XCTUnwrap(
            ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(
                packet.canonicalData()
            ).preparedStrokes().first
        )

        XCTAssertEqual(restored.points[0].x.bitPattern, leastPositive.bitPattern)
        XCTAssertEqual(restored.points[0].y.bitPattern, (-leastPositive).bitPattern)
        XCTAssertEqual(restored.bounds.minX.bitPattern, negativeExtreme.bitPattern)
        XCTAssertEqual(
            restored.bounds.maxX.bitPattern,
            Double.greatestFiniteMagnitude.bitPattern
        )
        XCTAssertEqual(restored.bounds, explicitBounds)
        XCTAssertNotEqual(restored.bounds, InkBounds.enclosing(restored.points))
    }

    func testPreservesCreationOffsetsExactlyWithoutRebasingOrSorting() throws {
        let source = [
            InkStroke(
                points: [InkPoint(x: 0, y: 0, timeOffset: 0)],
                creationTimeOffset: 17.75
            ),
            InkStroke(
                points: [InkPoint(x: 1, y: 1, timeOffset: 0)],
                creationTimeOffset: -3.25
            )
        ]

        let restored = try ChordInkCanonicalTrajectoryPacket(strokes: source).preparedStrokes()

        XCTAssertEqual(
            restored.map { $0.creationTimeOffset?.bitPattern },
            source.map { $0.creationTimeOffset?.bitPattern }
        )
        XCTAssertEqual(restored.map(\.points.first?.x), [0, 1])
    }

    func testCanonicalEncodingHasStableAnalyticGoldenBytes() throws {
        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [
                    InkPoint(x: 0, y: 0, timeOffset: nil),
                    InkPoint(x: 1, y: -2, timeOffset: 0.25)
                ],
                creationTimeOffset: 4
            )
        ])
        let expected = #"{"coordinateSpace":"transformed-prepared-drawing","formatVersion":"ink-trajectory-packet-v1","strokes":[{"bounds":{"maxX":"3ff0000000000000","maxY":"0000000000000000","minX":"0000000000000000","minY":"c000000000000000"},"creationTimeOffset":{"bitPattern":"4010000000000000","state":"finite"},"points":[{"timeOffset":{"state":"missing"},"x":"0000000000000000","y":"0000000000000000"},{"timeOffset":{"bitPattern":"3fd0000000000000","state":"finite"},"x":"3ff0000000000000","y":"c000000000000000"}]}]}"#

        let first = try packet.canonicalData()
        let second = try packet.canonicalData()

        XCTAssertEqual(first, Data(expected.utf8))
        XCTAssertEqual(second, first)
        XCTAssertEqual(
            try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(first).canonicalData(),
            first
        )
    }

    func testRejectsNonFinitePointGeometryAndBounds() {
        XCTAssertThrowsError(try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [InkPoint(x: .nan, y: 0, timeOffset: nil)],
                bounds: .zero
            )
        ])) { error in
            XCTAssertEqual(
                error as? ChordInkCanonicalTrajectoryPacketError,
                .nonFiniteGeometry(strokeIndex: 0, pointIndex: 0, component: "point.x")
            )
        }

        XCTAssertThrowsError(try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [InkPoint(x: 0, y: 0, timeOffset: nil)],
                bounds: InkBounds(minX: 0, minY: 0, maxX: .infinity, maxY: 0)
            )
        ])) { error in
            XCTAssertEqual(
                error as? ChordInkCanonicalTrajectoryPacketError,
                .nonFiniteGeometry(strokeIndex: 0, pointIndex: nil, component: "bounds.maxX")
            )
        }
    }

    func testRejectsMalformedUnknownAndNonCanonicalData() throws {
        let unknownVersion = Data(
            #"{"coordinateSpace":"transformed-prepared-drawing","formatVersion":"ink-trajectory-packet-v2","strokes":[]}"#.utf8
        )
        XCTAssertThrowsError(
            try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(unknownVersion)
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCanonicalTrajectoryPacketError,
                .unsupportedFormatVersion("ink-trajectory-packet-v2")
            )
        }

        let malformedGeometry = Data(
            #"{"coordinateSpace":"transformed-prepared-drawing","formatVersion":"ink-trajectory-packet-v1","strokes":[{"bounds":{"maxX":"7ff0000000000000","maxY":"0000000000000000","minX":"0000000000000000","minY":"0000000000000000"},"creationTimeOffset":{"state":"missing"},"points":[]}]}"#.utf8
        )
        XCTAssertThrowsError(
            try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(malformedGeometry)
        )

        let valid = try ChordInkCanonicalTrajectoryPacket(strokes: []).canonicalData()
        let nonCanonical = Data(" \n".utf8) + valid
        XCTAssertThrowsError(
            try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(nonCanonical)
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCanonicalTrajectoryPacketError,
                .nonCanonicalData
            )
        }

        let uppercase = Data(
            #"{"coordinateSpace":"transformed-prepared-drawing","formatVersion":"ink-trajectory-packet-v1","strokes":[{"bounds":{"maxX":"3FF0000000000000","maxY":"0000000000000000","minX":"0000000000000000","minY":"0000000000000000"},"creationTimeOffset":{"state":"missing"},"points":[]}]}"#.utf8
        )
        XCTAssertThrowsError(
            try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(uppercase)
        )

        let validText = try XCTUnwrap(String(data: valid, encoding: .utf8))
        let extraKey = Data(
            validText.replacingOccurrences(
                of: "{",
                with: "{\"label\":\"forbidden\",",
                options: [],
                range: validText.startIndex..<validText.index(after: validText.startIndex)
            ).utf8
        )
        XCTAssertThrowsError(
            try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(extraKey)
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCanonicalTrajectoryPacketError,
                .nonCanonicalData
            )
        }
    }

    func testPacketSchemaContainsNoChordLabelCandidateOrTrustFields() throws {
        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(points: [InkPoint(x: 2, y: 3, timeOffset: nil)])
        ])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: packet.canonicalData()) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), ["coordinateSpace", "formatVersion", "strokes"])
        let strokes = try XCTUnwrap(object["strokes"] as? [[String: Any]])
        let stroke = try XCTUnwrap(strokes.first)
        XCTAssertEqual(Set(stroke.keys), ["bounds", "creationTimeOffset", "points"])
        let bounds = try XCTUnwrap(stroke["bounds"] as? [String: Any])
        XCTAssertEqual(Set(bounds.keys), ["minX", "minY", "maxX", "maxY"])
        let points = try XCTUnwrap(stroke["points"] as? [[String: Any]])
        let point = try XCTUnwrap(points.first)
        XCTAssertEqual(Set(point.keys), ["x", "y", "timeOffset"])
        let timing = try XCTUnwrap(point["timeOffset"] as? [String: Any])
        XCTAssertEqual(Set(timing.keys), ["state"])

        let encodedText = try XCTUnwrap(String(data: packet.canonicalData(), encoding: .utf8))
        for forbiddenField in [
            "label",
            "chord",
            "candidate",
            "confidence",
            "trust",
            "expected",
            "ownership",
            "target",
            "measure"
        ] {
            XCTAssertFalse(encodedText.lowercased().contains(forbiddenField))
        }
    }
}
