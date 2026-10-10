import Foundation

/// The complete prepared source for one opt-in evaluation observation.
///
/// `normalizedDrawingData` is the color-normalized PencilKit serialization
/// supplied to recognition. It is not the raw pre-normalization drawing and it
/// does not retain every PencilKit path property in `visibleStrokes`.
struct PersonalInkEvaluationSourceSnapshot: Codable, Equatable {
    struct Page: Codable, Equatable {
        var index: Int
        var frame: CGRect
    }

    struct Measure: Codable, Equatable {
        /// Unique visual layout identity for this concrete measure occurrence.
        var measureID: UUID
        /// Optional routed chart target. Open/filler layouts may intentionally
        /// repeat this value across distinct visual measure occurrences.
        var targetMeasureID: UUID? = nil
        var index: Int
        var chordWritingFrame: CGRect
    }

    static let currentSchemaVersion = 1
    static let maximumDrawingByteCount = 1_000_000
    static let maximumCanonicalTrajectoryByteCount = 8_000_000
    static let maximumVisibleStrokeCount = 512
    static let maximumPointCount = 65_536
    static let maximumTargetCount = 64
    static let supportedOutcomes: Set<String> = [
        "ready",
        "noVisibleStrokes",
        "noRecognitionData",
        "skippedWeakBatchTargets",
        "skippedSingleTarget",
        "noTarget"
    ]

    var schemaVersion: Int
    var requestID: UUID
    var inkRevision: UInt64
    var normalizedDrawingData: Data
    /// Canonical lossless bytes for the full visible-fragment trajectory array.
    /// This is derived from `visibleStrokes`; callers cannot supply a competing
    /// representation.
    var canonicalVisibleTrajectoryData: Data
    var chordFrame: CGRect
    var pageBounds: CGRect?
    var pages: [Page]
    var measures: [Measure]
    var visibleStrokes: [InkStroke]
    var recognitionVisibleFragmentIndices: [Int]
    var ownership: ChordInkTargetOwnershipSnapshot
    var outcome: String

    init(
        requestID: UUID,
        inkRevision: UInt64,
        normalizedDrawingData: Data,
        chordFrame: CGRect,
        pageBounds: CGRect?,
        pages: [Page],
        measures: [Measure],
        visibleStrokes: [InkStroke],
        recognitionVisibleFragmentIndices: [Int],
        ownership: ChordInkTargetOwnershipSnapshot,
        outcome: String
    ) throws {
        guard !normalizedDrawingData.isEmpty,
              normalizedDrawingData.count <= Self.maximumDrawingByteCount,
              visibleStrokes.count <= Self.maximumVisibleStrokeCount,
              Self.hasBoundedPointCount(visibleStrokes),
              visibleStrokes.allSatisfy(Self.isFinite),
              let canonicalVisibleTrajectoryData = try? ChordInkCanonicalTrajectoryPacket(
                  strokes: visibleStrokes
              ).canonicalData(),
              canonicalVisibleTrajectoryData.count
                <= Self.maximumCanonicalTrajectoryByteCount else {
            throw PersonalInkEvaluationSourceError.invalid
        }
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.inkRevision = inkRevision
        self.normalizedDrawingData = normalizedDrawingData
        self.canonicalVisibleTrajectoryData = canonicalVisibleTrajectoryData
        self.chordFrame = chordFrame
        self.pageBounds = pageBounds
        self.pages = pages
        self.measures = measures
        self.visibleStrokes = visibleStrokes
        self.recognitionVisibleFragmentIndices = recognitionVisibleFragmentIndices
        self.ownership = ownership
        self.outcome = outcome
        try validate()
    }

    var recognitionStrokes: [InkStroke] {
        recognitionVisibleFragmentIndices.map { visibleStrokes[$0] }
    }

    func recognitionStrokes(forTargetOrdinal targetOrdinal: Int) -> [InkStroke]? {
        guard let group = ownership.targetGroups.first(where: {
            $0.targetOrdinal == targetOrdinal
        }) else {
            return nil
        }
        return group.visibleFragmentIndices.map { visibleStrokes[$0] }
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              !normalizedDrawingData.isEmpty,
              normalizedDrawingData.count <= Self.maximumDrawingByteCount,
              !canonicalVisibleTrajectoryData.isEmpty,
              canonicalVisibleTrajectoryData.count <= Self.maximumCanonicalTrajectoryByteCount,
              Self.isFinite(chordFrame),
              pageBounds.map(Self.isFinite) ?? true,
              pages.allSatisfy({ $0.index >= 0 && Self.isFinite($0.frame) }),
              measures.allSatisfy({ $0.index >= 0 && Self.isFinite($0.chordWritingFrame) }),
              pages.map(\.index) == pages.map(\.index).sorted(),
              Set(pages.map(\.index)).count == pages.count,
              Set(measures.map(\.measureID)).count == measures.count,
              visibleStrokes.count <= Self.maximumVisibleStrokeCount,
              Self.hasBoundedPointCount(visibleStrokes),
              visibleStrokes.allSatisfy(Self.isFinite),
              ownership.targetGroups.count <= Self.maximumTargetCount,
              Self.isValidOwnership(ownership, visibleStrokeCount: visibleStrokes.count),
              Self.supportedOutcomes.contains(outcome),
              (outcome == "ready") == !ownership.targetGroups.isEmpty else {
            throw PersonalInkEvaluationSourceError.invalid
        }

        guard let decodedPacket = try? ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(
            canonicalVisibleTrajectoryData
        ),
              let regeneratedData = try? ChordInkCanonicalTrajectoryPacket(
                strokes: visibleStrokes
              ).canonicalData(),
              decodedPacket.strokes.count == visibleStrokes.count,
              regeneratedData == canonicalVisibleTrajectoryData else {
            throw PersonalInkEvaluationSourceError.invalid
        }

        let visibleDomain = Set(visibleStrokes.indices)
        let recognitionIndices = recognitionVisibleFragmentIndices
        let recognitionSet = Set(recognitionIndices)
        guard recognitionIndices == recognitionIndices.sorted(),
              recognitionSet.count == recognitionIndices.count,
              recognitionSet.isSubset(of: visibleDomain),
              recognitionSet == visibleDomain.subtracting(
                Set(ownership.barlineVisibleFragmentIndices)
              ),
              ownership.targetGroups.allSatisfy({ group in
                  Set(group.visibleFragmentIndices).isSubset(of: recognitionSet)
              }),
              Set(ownership.unassignedVisibleFragmentIndices).isSubset(of: recognitionSet) else {
            throw PersonalInkEvaluationSourceError.invalid
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestID
        case inkRevision
        case normalizedDrawingData
        case canonicalVisibleTrajectoryData
        case chordFrame
        case pageBounds
        case pages
        case measures
        case visibleStrokes
        case recognitionVisibleFragmentIndices
        case ownership
        case outcome
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        inkRevision = try container.decode(UInt64.self, forKey: .inkRevision)
        normalizedDrawingData = try container.decode(Data.self, forKey: .normalizedDrawingData)
        canonicalVisibleTrajectoryData = try container.decode(
            Data.self,
            forKey: .canonicalVisibleTrajectoryData
        )
        chordFrame = try container.decode(CGRect.self, forKey: .chordFrame)
        pageBounds = try container.decodeIfPresent(CGRect.self, forKey: .pageBounds)
        pages = try container.decode([Page].self, forKey: .pages)
        measures = try container.decode([Measure].self, forKey: .measures)
        visibleStrokes = try container.decode([InkStroke].self, forKey: .visibleStrokes)
        recognitionVisibleFragmentIndices = try container.decode(
            [Int].self,
            forKey: .recognitionVisibleFragmentIndices
        )
        ownership = try container.decode(
            ChordInkTargetOwnershipSnapshot.self,
            forKey: .ownership
        )
        outcome = try container.decode(String.self, forKey: .outcome)
        do {
            try validate()
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid personal ink evaluation source snapshot."
                )
            )
        }
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        let values = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
        return values.allSatisfy(\.isFinite)
            && rect.size.width >= 0
            && rect.size.height >= 0
            && (rect.origin.x + rect.size.width).isFinite
            && (rect.origin.y + rect.size.height).isFinite
    }

    private static func hasBoundedPointCount(_ strokes: [InkStroke]) -> Bool {
        var count = 0
        for stroke in strokes {
            guard stroke.points.count <= maximumPointCount - count else {
                return false
            }
            count += stroke.points.count
        }
        return true
    }

    private static func isValidOwnership(
        _ ownership: ChordInkTargetOwnershipSnapshot,
        visibleStrokeCount: Int
    ) -> Bool {
        guard ownership.schemaVersion == ChordInkTargetOwnershipSnapshot.currentSchemaVersion,
              ownership.indexSpace == .visibleFragmentsBeforeBarlineFilteringV1,
              ownership.sourcePencilStrokeCount >= 0,
              ownership.visibleFragmentSourceStrokeIndices.count == visibleStrokeCount,
              ownership.visibleFragmentSourceStrokeIndices.allSatisfy({
                  (0..<ownership.sourcePencilStrokeCount).contains($0)
              }) else {
            return false
        }
        let visibleDomain = Set(0..<visibleStrokeCount)
        let barlineIndices = ownership.barlineVisibleFragmentIndices
        guard barlineIndices == barlineIndices.sorted(),
              Set(barlineIndices).count == barlineIndices.count,
              Set(barlineIndices).isSubset(of: visibleDomain),
              ownership.targetGroups.map(\.targetOrdinal)
                == Array(ownership.targetGroups.indices) else {
            return false
        }
        var claimed = Set(barlineIndices)
        for group in ownership.targetGroups {
            let indices = group.visibleFragmentIndices
            let indexSet = Set(indices)
            guard !indices.isEmpty,
                  indices == indices.sorted(),
                  indexSet.count == indices.count,
                  indexSet.isSubset(of: visibleDomain),
                  claimed.isDisjoint(with: indexSet) else {
                return false
            }
            claimed.formUnion(indexSet)
        }
        return ownership.unassignedVisibleFragmentIndices
            == Array(visibleDomain.subtracting(claimed)).sorted()
    }

    private static func isFinite(_ stroke: InkStroke) -> Bool {
        let bounds = stroke.bounds
        guard !stroke.points.isEmpty,
              [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY].allSatisfy(\.isFinite),
              bounds.minX <= bounds.maxX,
              bounds.minY <= bounds.maxY,
              (bounds.maxX - bounds.minX).isFinite,
              (bounds.maxY - bounds.minY).isFinite,
              stroke.creationTimeOffset.map(\.isFinite) ?? true else {
            return false
        }
        return stroke.points.allSatisfy { point in
            point.x.isFinite && point.y.isFinite
                && (point.timeOffset.map(\.isFinite) ?? true)
                && bounds.minX <= point.x && point.x <= bounds.maxX
                && bounds.minY <= point.y && point.y <= bounds.maxY
        }
    }
}

enum PersonalInkEvaluationSourceError: LocalizedError {
    case invalid

    var errorDescription: String? {
        "The prepared handwriting source is invalid or too large, so it was not saved. Return to Write & Render and try the capture again."
    }
}
