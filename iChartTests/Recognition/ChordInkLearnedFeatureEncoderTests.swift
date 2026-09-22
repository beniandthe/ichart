import XCTest
@testable import iChart

final class ChordInkLearnedFeatureEncoderTests: XCTestCase {
    func testCanonicalPacketAndPreparedStrokeInputsProduceSameFeatures() throws {
        let strokes = [
            stroke([(0, 0), (5, 10), (10, 0)]),
            stroke([(12, 4), (16, 8)])
        ]
        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: strokes)

        XCTAssertEqual(
            try ChordInkTrajectoryFeatureEncoder.encode(packet),
            try ChordInkTrajectoryFeatureEncoder.encode(strokes: strokes)
        )
        XCTAssertEqual(
            try ChordInkRasterizer.rasterize(packet),
            try ChordInkRasterizer.rasterize(strokes: strokes)
        )
    }

    func testGoldenHorizontalTrajectoryHasFrozenShapeAndChannels() throws {
        let tensor = try ChordInkTrajectoryFeatureEncoder.encode(strokes: [
            stroke([(0, 0), (10, 0)])
        ])

        XCTAssertEqual(tensor.shape, [1, 256, 10])
        XCTAssertEqual(tensor.values.count, 2_560)
        XCTAssertEqual(tensor[sample: 0, channel: .x], -0.5)
        XCTAssertEqual(tensor[sample: 0, channel: .y], 0)
        XCTAssertEqual(tensor[sample: 0, channel: .deltaX], 0)
        XCTAssertEqual(tensor[sample: 0, channel: .arcStep], 0)
        XCTAssertEqual(tensor[sample: 0, channel: .timingAvailable], 0)
        XCTAssertEqual(tensor[sample: 0, channel: .strokeStart], 1)
        XCTAssertEqual(tensor[sample: 0, channel: .strokeEnd], 0)
        XCTAssertEqual(tensor[sample: 0, channel: .valid], 1)

        XCTAssertEqual(
            tensor[sample: 1, channel: .x],
            Float(-0.5 + 1.0 / 255.0),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            tensor[sample: 1, channel: .deltaX],
            Float(1.0 / 255.0),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            tensor[sample: 1, channel: .arcStep],
            Float(1.0 / 255.0),
            accuracy: 0.000_001
        )
        XCTAssertEqual(tensor[sample: 255, channel: .x], 0.5)
        XCTAssertEqual(tensor[sample: 255, channel: .strokeStart], 0)
        XCTAssertEqual(tensor[sample: 255, channel: .strokeEnd], 1)
        XCTAssertEqual(tensor[sample: 255, channel: .valid], 1)
    }

    func testTrajectoryAndRasterAreTranslationAndScaleInvariant() throws {
        let original = [
            stroke([(0, 0), (5, 10), (10, 0)]),
            stroke([(12, 4), (16, 8)])
        ]
        let transformed = [
            stroke([(100, -50), (110, -30), (120, -50)]),
            stroke([(124, -42), (132, -34)])
        ]

        let originalTensor = try ChordInkTrajectoryFeatureEncoder.encode(strokes: original)
        let transformedTensor = try ChordInkTrajectoryFeatureEncoder.encode(strokes: transformed)
        XCTAssertEqual(originalTensor, transformedTensor)

        let originalRaster = try ChordInkRasterizer.rasterize(strokes: original)
        let transformedRaster = try ChordInkRasterizer.rasterize(strokes: transformed)
        XCTAssertEqual(originalRaster, transformedRaster)
    }

    func testMissingAndInvalidTimingUseExplicitFallbackWithoutChangingGeometry() throws {
        let unavailable = stroke([(0, 0), (10, 0)])
        let invalid = InkStroke(points: [
            InkPoint(x: 0, y: 0, timeOffset: .nan),
            InkPoint(x: 10, y: 0, timeOffset: .infinity)
        ])
        let available = InkStroke(points: [
            InkPoint(x: 0, y: 0, timeOffset: 0),
            InkPoint(x: 10, y: 0, timeOffset: 0.255)
        ])

        let unavailableTensor = try ChordInkTrajectoryFeatureEncoder.encode(strokes: [unavailable])
        let invalidTensor = try ChordInkTrajectoryFeatureEncoder.encode(strokes: [invalid])
        let availableTensor = try ChordInkTrajectoryFeatureEncoder.encode(strokes: [available])

        for sample in 0..<256 {
            XCTAssertEqual(
                unavailableTensor[sample: sample, channel: .x],
                invalidTensor[sample: sample, channel: .x]
            )
            XCTAssertEqual(unavailableTensor[sample: sample, channel: .normalizedDeltaTime], 0)
            XCTAssertEqual(unavailableTensor[sample: sample, channel: .timingAvailable], 0)
            XCTAssertEqual(invalidTensor[sample: sample, channel: .normalizedDeltaTime], 0)
            XCTAssertEqual(invalidTensor[sample: sample, channel: .timingAvailable], 0)
        }
        XCTAssertEqual(availableTensor[sample: 0, channel: .timingAvailable], 0)
        XCTAssertEqual(availableTensor[sample: 1, channel: .timingAvailable], 1)
        XCTAssertEqual(
            availableTensor[sample: 1, channel: .normalizedDeltaTime],
            0.004,
            accuracy: 0.000_001
        )
    }

    func testNonmonotonicStrokeTimingDisablesTimingForTheWholeStroke() throws {
        let tensor = try ChordInkTrajectoryFeatureEncoder.encode(strokes: [
            InkStroke(points: [
                InkPoint(x: 0, y: 0, timeOffset: 0),
                InkPoint(x: 5, y: 5, timeOffset: 0.2),
                InkPoint(x: 10, y: 0, timeOffset: 0.1)
            ])
        ])

        for sample in 0..<ChordInkFeatureSchema.trajectorySampleCount {
            XCTAssertEqual(tensor[sample: sample, channel: .normalizedDeltaTime], 0)
            XCTAssertEqual(tensor[sample: sample, channel: .timingAvailable], 0)
        }
    }

    func testWithinStrokeAndPenUpTimingUseDifferentFrozenCaps() throws {
        let first = InkStroke(
            points: [
                InkPoint(x: 0, y: 0, timeOffset: 0),
                InkPoint(x: 1, y: 0, timeOffset: 0.25)
            ],
            creationTimeOffset: 10
        )
        let second = InkStroke(
            points: [
                InkPoint(x: 2, y: 0, timeOffset: 0),
                InkPoint(x: 3, y: 0, timeOffset: 0.25)
            ],
            creationTimeOffset: 11.25
        )

        let tensor = try ChordInkTrajectoryFeatureEncoder.encode(strokes: [first, second])
        let secondStrokeStart = (0..<ChordInkFeatureSchema.trajectorySampleCount)
            .dropFirst()
            .first { tensor[sample: $0, channel: .strokeStart] == 1 }
        let index = try XCTUnwrap(secondStrokeStart)

        XCTAssertEqual(tensor[sample: index, channel: .normalizedDeltaTime], 1)
        XCTAssertEqual(tensor[sample: index, channel: .timingAvailable], 1)
        XCTAssertGreaterThan(index, 0)
        XCTAssertEqual(tensor[sample: index - 1, channel: .strokeEnd], 1)
    }

    func testStrokeBoundariesResetDeltasAndLargestRemainderIsStable() throws {
        let tensor = try ChordInkTrajectoryFeatureEncoder.encode(strokes: [
            stroke([(0, 0), (1, 0)]),
            stroke([(10, 0), (11, 0)]),
            stroke([(20, 0), (22, 0)])
        ])

        // Minimums consume six samples. The remaining 250 split by 1:1:2;
        // the tied half-sample goes to the earlier stroke.
        XCTAssertEqual(tensor[sample: 0, channel: .strokeStart], 1)
        XCTAssertEqual(tensor[sample: 64, channel: .strokeEnd], 1)
        XCTAssertEqual(tensor[sample: 65, channel: .strokeStart], 1)
        XCTAssertEqual(tensor[sample: 65, channel: .deltaX], 0)
        XCTAssertEqual(tensor[sample: 128, channel: .strokeEnd], 1)
        XCTAssertEqual(tensor[sample: 129, channel: .strokeStart], 1)
        XCTAssertEqual(tensor[sample: 129, channel: .deltaX], 0)
        XCTAssertEqual(tensor[sample: 255, channel: .strokeEnd], 1)
    }

    func testZeroLengthStrokeIsStableAndLeavesUnusedSamplesMasked() throws {
        let tensor = try ChordInkTrajectoryFeatureEncoder.encode(strokes: [
            stroke([(4, 7), (4, 7)])
        ])

        XCTAssertEqual(tensor[sample: 0, channel: .x], 0)
        XCTAssertEqual(tensor[sample: 0, channel: .y], 0)
        XCTAssertEqual(tensor[sample: 0, channel: .strokeStart], 1)
        XCTAssertEqual(tensor[sample: 0, channel: .valid], 1)
        XCTAssertEqual(tensor[sample: 1, channel: .strokeEnd], 1)
        XCTAssertEqual(tensor[sample: 1, channel: .valid], 1)
        XCTAssertEqual(tensor[sample: 2, channel: .valid], 0)
        XCTAssertTrue(tensor.values.allSatisfy(\.isFinite))
    }

    func testRepresentationOverflowFailsClosedInsteadOfDroppingStrokes() {
        let strokes = (0..<257).map { index in
            stroke([(Double(index), 0)])
        }

        XCTAssertThrowsError(try ChordInkTrajectoryFeatureEncoder.encode(strokes: strokes)) {
            XCTAssertEqual(
                $0 as? ChordInkFeatureEncodingError,
                .noRead(
                    .representationCannotFit(
                        requiredMinimumSamples: 257,
                        capacity: 256
                    )
                )
            )
        }
    }

    func testInputComplexityAndNonFiniteGeometryFailClosed() {
        let excessivePoints = (0...ChordInkFeatureSchema.maximumInputPointCount).map {
            (Double($0), 0.0)
        }
        XCTAssertThrowsError(
            try ChordInkTrajectoryFeatureEncoder.encode(strokes: [stroke(excessivePoints)])
        ) {
            XCTAssertEqual(
                $0 as? ChordInkFeatureEncodingError,
                .noRead(
                    .pointComplexityExceeded(
                        limit: ChordInkFeatureSchema.maximumInputPointCount,
                        actual: ChordInkFeatureSchema.maximumInputPointCount + 1
                    )
                )
            )
        }

        let nonFinite = InkStroke(points: [InkPoint(x: .nan, y: 0, timeOffset: nil)])
        XCTAssertThrowsError(try ChordInkRasterizer.rasterize(strokes: [nonFinite])) {
            XCTAssertEqual(
                $0 as? ChordInkFeatureEncodingError,
                .noRead(
                    .nonFiniteGeometry(
                        strokeIndex: 0,
                        pointIndex: nil,
                        component: "bounds.minX"
                    )
                )
            )
        }
    }

    func testGoldenRasterIsDeterministic() throws {
        let raster = try ChordInkRasterizer.rasterize(strokes: [
            stroke([(0, 0), (10, 0)])
        ])
        let repeated = try ChordInkRasterizer.rasterize(strokes: [
            stroke([(0, 0), (10, 0)])
        ])

        XCTAssertEqual(raster.width, 256)
        XCTAssertEqual(raster.height, 96)
        XCTAssertEqual(raster, repeated)
        XCTAssertEqual(fnv1a64(raster.pixels), 6_717_323_988_239_542_465)
    }

    func testRasterNeverConnectsSeparateStrokes() throws {
        let raster = try ChordInkRasterizer.rasterize(strokes: [
            stroke([(0, 0), (20, 0)]),
            stroke([(80, 0), (100, 0)])
        ])

        XCTAssertTrue((8..<70).contains { raster[x: $0, y: 48] == 255 })
        XCTAssertTrue((186..<248).contains { raster[x: $0, y: 48] == 255 })
        for y in 44...52 {
            for x in 90...166 {
                XCTAssertEqual(raster[x: x, y: y], 0)
            }
        }
    }

    private func stroke(_ points: [(Double, Double)]) -> InkStroke {
        InkStroke(points: points.map { InkPoint(x: $0.0, y: $0.1, timeOffset: nil) })
    }

    private func fnv1a64(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
