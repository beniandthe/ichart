import Foundation

/// Structural evidence describing which prepared ink fragments were assigned to
/// recognition targets. This metadata is deliberately independent of chord
/// labels, candidate scores, trust decisions, and writer identity.
struct ChordInkTargetOwnershipSnapshot: Codable, Hashable {
    enum IndexSpace: String, Codable, Hashable {
        case visibleFragmentsBeforeBarlineFilteringV1
    }

    struct TargetGroup: Codable, Hashable {
        var targetOrdinal: Int
        var visibleFragmentIndices: [Int]
    }

    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var indexSpace: IndexSpace
    var sourcePencilStrokeCount: Int
    var visibleFragmentSourceStrokeIndices: [Int]
    var barlineVisibleFragmentIndices: [Int]
    var targetGroups: [TargetGroup]
    var unassignedVisibleFragmentIndices: [Int]

    /// Builds a canonical, exhaustive partition of the visible-fragment index
    /// space. Invalid or overlapping ownership is rejected instead of being
    /// repaired, so an evaluator never receives ambiguous evidence.
    init?(
        sourcePencilStrokeCount: Int,
        visibleFragmentSourceStrokeIndices: [Int],
        barlineVisibleFragmentIndices: [Int],
        targetVisibleFragmentIndices: [[Int]]
    ) {
        guard sourcePencilStrokeCount >= 0,
              visibleFragmentSourceStrokeIndices.allSatisfy({
                  (0..<sourcePencilStrokeCount).contains($0)
              }) else {
            return nil
        }

        let visibleFragmentDomain = Set(visibleFragmentSourceStrokeIndices.indices)
        let canonicalBarlineIndices = barlineVisibleFragmentIndices.sorted()
        guard Set(canonicalBarlineIndices).count == canonicalBarlineIndices.count,
              canonicalBarlineIndices.allSatisfy(visibleFragmentDomain.contains) else {
            return nil
        }

        var claimedIndices = Set(canonicalBarlineIndices)
        var canonicalTargetGroups: [TargetGroup] = []
        canonicalTargetGroups.reserveCapacity(targetVisibleFragmentIndices.count)
        for (targetOrdinal, rawIndices) in targetVisibleFragmentIndices.enumerated() {
            let canonicalIndices = rawIndices.sorted()
            let targetIndexSet = Set(canonicalIndices)
            guard !canonicalIndices.isEmpty,
                  targetIndexSet.count == canonicalIndices.count,
                  canonicalIndices.allSatisfy(visibleFragmentDomain.contains),
                  claimedIndices.isDisjoint(with: targetIndexSet) else {
                return nil
            }
            claimedIndices.formUnion(targetIndexSet)
            canonicalTargetGroups.append(TargetGroup(
                targetOrdinal: targetOrdinal,
                visibleFragmentIndices: canonicalIndices
            ))
        }

        self.schemaVersion = Self.currentSchemaVersion
        self.indexSpace = .visibleFragmentsBeforeBarlineFilteringV1
        self.sourcePencilStrokeCount = sourcePencilStrokeCount
        self.visibleFragmentSourceStrokeIndices = visibleFragmentSourceStrokeIndices
        self.barlineVisibleFragmentIndices = canonicalBarlineIndices
        self.targetGroups = canonicalTargetGroups
        self.unassignedVisibleFragmentIndices = Array(
            visibleFragmentDomain.subtracting(claimedIndices)
        ).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case indexSpace
        case sourcePencilStrokeCount
        case visibleFragmentSourceStrokeIndices
        case barlineVisibleFragmentIndices
        case targetGroups
        case unassignedVisibleFragmentIndices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let decodedIndexSpace = try container.decode(IndexSpace.self, forKey: .indexSpace)
        let decodedSourcePencilStrokeCount = try container.decode(
            Int.self,
            forKey: .sourcePencilStrokeCount
        )
        let decodedVisibleFragmentSourceStrokeIndices = try container.decode(
            [Int].self,
            forKey: .visibleFragmentSourceStrokeIndices
        )
        let decodedBarlineVisibleFragmentIndices = try container.decode(
            [Int].self,
            forKey: .barlineVisibleFragmentIndices
        )
        let decodedTargetGroups = try container.decode(
            [TargetGroup].self,
            forKey: .targetGroups
        )
        let decodedUnassignedVisibleFragmentIndices = try container.decode(
            [Int].self,
            forKey: .unassignedVisibleFragmentIndices
        )

        guard decodedSchemaVersion == Self.currentSchemaVersion,
              decodedIndexSpace == .visibleFragmentsBeforeBarlineFilteringV1,
              decodedTargetGroups.map(\.targetOrdinal) == Array(decodedTargetGroups.indices),
              let snapshot = Self.init(
                  sourcePencilStrokeCount: decodedSourcePencilStrokeCount,
                  visibleFragmentSourceStrokeIndices: decodedVisibleFragmentSourceStrokeIndices,
                  barlineVisibleFragmentIndices: decodedBarlineVisibleFragmentIndices,
                  targetVisibleFragmentIndices: decodedTargetGroups.map(\.visibleFragmentIndices)
              ),
              snapshot.barlineVisibleFragmentIndices == decodedBarlineVisibleFragmentIndices,
              snapshot.targetGroups == decodedTargetGroups,
              snapshot.unassignedVisibleFragmentIndices
                == decodedUnassignedVisibleFragmentIndices else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid chord ink target-ownership snapshot."
                )
            )
        }

        self = snapshot
    }
}
