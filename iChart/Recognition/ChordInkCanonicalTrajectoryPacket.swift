import Foundation

enum ChordInkCanonicalTrajectoryPacketError: Error, Equatable {
    case unsupportedFormatVersion(String)
    case nonFiniteGeometry(strokeIndex: Int, pointIndex: Int?, component: String)
    case nonCanonicalData
}

/// A lossless, model-independent representation of the prepared recognition
/// strokes. Coordinates remain verbatim in transformed prepared-drawing space:
/// PencilKit transforms and visible mask fragments have already been applied,
/// but this packet does not normalize, rebase, resample, or otherwise alter the
/// geometry. It preserves source order, empty strokes, duplicate points, stored
/// bounds, exact IEEE-754 values, and timing availability. Target ownership is a
/// separate contract and is intentionally absent.
struct ChordInkCanonicalTrajectoryPacket: Encodable, Hashable, Sendable {
    static let currentFormatVersion = "ink-trajectory-packet-v1"

    enum CoordinateSpace: String, Codable, Hashable, Sendable {
        case transformedPreparedDrawing = "transformed-prepared-drawing"
    }

    /// Coverage reports only whether source timing values are present. It does
    /// not claim that present values are finite, nonnegative, monotonic, or
    /// chronologically valid. `containsNonFiniteTiming` reports numerical
    /// invalidity separately without inventing replacement values.
    enum TimingCoverage: String, Codable, Hashable, Sendable {
        case unavailable
        case partial
        case complete
    }

    struct GeometryValue: Codable, Hashable, Sendable {
        let bitPattern: UInt64

        var value: Double {
            Double(bitPattern: bitPattern)
        }

        fileprivate init(finiteValue: Double) {
            precondition(finiteValue.isFinite)
            bitPattern = finiteValue.bitPattern
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let encoded = try container.decode(String.self)
            bitPattern = try ChordInkCanonicalTrajectoryPacket.decodeBitPattern(
                encoded,
                codingPath: decoder.codingPath
            )

            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Trajectory geometry must be finite."
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(
                ChordInkCanonicalTrajectoryPacket.encodedBitPattern(bitPattern)
            )
        }
    }

    struct TimingValue: Codable, Hashable, Sendable {
        enum State: String, Codable, Hashable, Sendable {
            case missing
            case finite
            case nonFinite
        }

        let state: State
        let bitPattern: UInt64?

        var value: Double? {
            bitPattern.map(Double.init(bitPattern:))
        }

        init(_ value: Double?) {
            guard let value else {
                state = .missing
                bitPattern = nil
                return
            }

            state = value.isFinite ? .finite : .nonFinite
            bitPattern = value.bitPattern
        }

        private enum CodingKeys: String, CodingKey {
            case state
            case bitPattern
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            state = try container.decode(State.self, forKey: .state)

            switch state {
            case .missing:
                guard !container.contains(.bitPattern) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .bitPattern,
                        in: container,
                        debugDescription: "Missing timing must not carry a bit pattern."
                    )
                }
                bitPattern = nil

            case .finite, .nonFinite:
                let encoded = try container.decode(String.self, forKey: .bitPattern)
                let decodedBitPattern = try ChordInkCanonicalTrajectoryPacket.decodeBitPattern(
                    encoded,
                    codingPath: decoder.codingPath + [CodingKeys.bitPattern]
                )
                let decodedValue = Double(bitPattern: decodedBitPattern)
                guard decodedValue.isFinite == (state == .finite) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .bitPattern,
                        in: container,
                        debugDescription: "Timing state does not match its IEEE-754 value."
                    )
                }
                bitPattern = decodedBitPattern
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(state, forKey: .state)
            if let bitPattern {
                try container.encode(
                    ChordInkCanonicalTrajectoryPacket.encodedBitPattern(bitPattern),
                    forKey: .bitPattern
                )
            }
        }
    }

    struct Point: Codable, Hashable, Sendable {
        let x: GeometryValue
        let y: GeometryValue
        let timeOffset: TimingValue
    }

    struct Bounds: Codable, Hashable, Sendable {
        let minX: GeometryValue
        let minY: GeometryValue
        let maxX: GeometryValue
        let maxY: GeometryValue
    }

    struct Stroke: Codable, Hashable, Sendable {
        let points: [Point]
        let bounds: Bounds
        let creationTimeOffset: TimingValue
    }

    let formatVersion: String
    let coordinateSpace: CoordinateSpace
    let strokes: [Stroke]

    var pointTimingCoverage: TimingCoverage {
        Self.coverage(of: strokes.flatMap(\.points).map(\.timeOffset))
    }

    var creationTimingCoverage: TimingCoverage {
        Self.coverage(of: strokes.map(\.creationTimeOffset))
    }

    var timingCoverage: TimingCoverage {
        Self.coverage(
            of: strokes.flatMap { stroke in
                [stroke.creationTimeOffset] + stroke.points.map(\.timeOffset)
            }
        )
    }

    var containsNonFiniteTiming: Bool {
        strokes.contains { stroke in
            stroke.creationTimeOffset.state == .nonFinite
                || stroke.points.contains { $0.timeOffset.state == .nonFinite }
        }
    }

    init(strokes sourceStrokes: [InkStroke]) throws {
        formatVersion = Self.currentFormatVersion
        coordinateSpace = .transformedPreparedDrawing
        strokes = try sourceStrokes.enumerated().map { strokeIndex, stroke in
            let bounds = try Bounds(
                minX: Self.geometryValue(
                    stroke.bounds.minX,
                    strokeIndex: strokeIndex,
                    pointIndex: nil,
                    component: "bounds.minX"
                ),
                minY: Self.geometryValue(
                    stroke.bounds.minY,
                    strokeIndex: strokeIndex,
                    pointIndex: nil,
                    component: "bounds.minY"
                ),
                maxX: Self.geometryValue(
                    stroke.bounds.maxX,
                    strokeIndex: strokeIndex,
                    pointIndex: nil,
                    component: "bounds.maxX"
                ),
                maxY: Self.geometryValue(
                    stroke.bounds.maxY,
                    strokeIndex: strokeIndex,
                    pointIndex: nil,
                    component: "bounds.maxY"
                )
            )
            let points = try stroke.points.enumerated().map { pointIndex, point in
                Point(
                    x: try Self.geometryValue(
                        point.x,
                        strokeIndex: strokeIndex,
                        pointIndex: pointIndex,
                        component: "point.x"
                    ),
                    y: try Self.geometryValue(
                        point.y,
                        strokeIndex: strokeIndex,
                        pointIndex: pointIndex,
                        component: "point.y"
                    ),
                    timeOffset: TimingValue(point.timeOffset)
                )
            }

            return Stroke(
                points: points,
                bounds: bounds,
                creationTimeOffset: TimingValue(stroke.creationTimeOffset)
            )
        }
    }

    private init(
        formatVersion: String,
        coordinateSpace: CoordinateSpace,
        strokes: [Stroke]
    ) {
        self.formatVersion = formatVersion
        self.coordinateSpace = coordinateSpace
        self.strokes = strokes
    }

    func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Canonical here means one byte representation for these exact stored
    /// values. It does not make geometrically equivalent paths, signed zero,
    /// or alternate stored bounds semantically identical. A digest of these
    /// bytes must not be used as a leakage/deduplication identity.
    ///
    /// This type has no transport or persistence integration. Any future
    /// untrusted-data consumer must enforce an independently specified byte,
    /// stroke, and point budget before decoding to avoid unbounded allocation.
    static func decodeCanonicalData(_ data: Data) throws -> Self {
        let decoded = try JSONDecoder().decode(DecodedRepresentation.self, from: data)
        guard decoded.formatVersion == Self.currentFormatVersion else {
            throw ChordInkCanonicalTrajectoryPacketError.unsupportedFormatVersion(
                decoded.formatVersion
            )
        }
        let packet = Self(
            formatVersion: decoded.formatVersion,
            coordinateSpace: decoded.coordinateSpace,
            strokes: decoded.strokes
        )
        guard try packet.canonicalData() == data else {
            throw ChordInkCanonicalTrajectoryPacketError.nonCanonicalData
        }
        return packet
    }

    func preparedStrokes() -> [InkStroke] {
        strokes.map { stroke in
            InkStroke(
                points: stroke.points.map { point in
                    InkPoint(
                        x: point.x.value,
                        y: point.y.value,
                        timeOffset: point.timeOffset.value
                    )
                },
                bounds: InkBounds(
                    minX: stroke.bounds.minX.value,
                    minY: stroke.bounds.minY.value,
                    maxX: stroke.bounds.maxX.value,
                    maxY: stroke.bounds.maxY.value
                ),
                creationTimeOffset: stroke.creationTimeOffset.value
            )
        }
    }

    private static func geometryValue(
        _ value: Double,
        strokeIndex: Int,
        pointIndex: Int?,
        component: String
    ) throws -> GeometryValue {
        guard value.isFinite else {
            throw ChordInkCanonicalTrajectoryPacketError.nonFiniteGeometry(
                strokeIndex: strokeIndex,
                pointIndex: pointIndex,
                component: component
            )
        }
        return GeometryValue(finiteValue: value)
    }

    private static func coverage(of values: [TimingValue]) -> TimingCoverage {
        guard !values.isEmpty else {
            return .unavailable
        }

        let availableCount = values.reduce(into: 0) { count, value in
            if value.state != .missing {
                count += 1
            }
        }
        if availableCount == 0 {
            return .unavailable
        }
        if availableCount == values.count {
            return .complete
        }
        return .partial
    }

    private static func encodedBitPattern(_ bitPattern: UInt64) -> String {
        String(format: "%016llx", bitPattern)
    }

    private static func decodeBitPattern(
        _ encoded: String,
        codingPath: [CodingKey]
    ) throws -> UInt64 {
        let isCanonical = encoded.count == 16
            && encoded == encoded.lowercased()
            && encoded.allSatisfy { character in
                character.isNumber || ("a"..."f").contains(character)
            }
        guard isCanonical,
              let bitPattern = UInt64(encoded, radix: 16) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected a 16-digit lowercase IEEE-754 bit pattern."
                )
            )
        }
        return bitPattern
    }

    private struct DecodedRepresentation: Decodable {
        let formatVersion: String
        let coordinateSpace: CoordinateSpace
        let strokes: [Stroke]
    }
}
