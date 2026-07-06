import Foundation

struct SectionLabel: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var type: SectionLabelType
    var anchorMeasureID: UUID
    var anchorSystemID: UUID
    var rawInput: String?
}

enum SectionLabelType: String, Codable, CaseIterable, Hashable {
    case sectionName
    case rehearsalMark
}

struct CueText: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var anchorMeasureID: UUID
    var position: CuePosition
    var emphasis: CueEmphasis
    var scale: Double
    var beatFraction: Double?
    var verticalOffset: Double
    var rawInput: String?

    init(
        id: UUID,
        text: String,
        anchorMeasureID: UUID,
        position: CuePosition,
        emphasis: CueEmphasis,
        scale: Double = Self.defaultScale,
        beatFraction: Double? = nil,
        verticalOffset: Double = 0,
        rawInput: String? = nil
    ) {
        self.id = id
        self.text = text
        self.anchorMeasureID = anchorMeasureID
        self.position = position
        self.emphasis = emphasis
        self.scale = Self.clampedScale(scale)
        self.beatFraction = Self.clampedBeatFraction(beatFraction)
        self.verticalOffset = Self.clampedVerticalOffset(verticalOffset)
        self.rawInput = rawInput
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case anchorMeasureID
        case position
        case emphasis
        case scale
        case beatFraction
        case verticalOffset
        case rawInput
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        anchorMeasureID = try container.decode(UUID.self, forKey: .anchorMeasureID)
        position = try container.decode(CuePosition.self, forKey: .position)
        emphasis = try container.decode(CueEmphasis.self, forKey: .emphasis)
        scale = Self.clampedScale(try container.decodeIfPresent(Double.self, forKey: .scale) ?? Self.defaultScale)
        beatFraction = Self.clampedBeatFraction(try container.decodeIfPresent(Double.self, forKey: .beatFraction))
        verticalOffset = Self.clampedVerticalOffset(
            try container.decodeIfPresent(Double.self, forKey: .verticalOffset) ?? 0
        )
        rawInput = try container.decodeIfPresent(String.self, forKey: .rawInput)
    }

    static let defaultScale: Double = 1
    static let minimumScale: Double = 0.75
    static let maximumScale: Double = 1.8
    static let scaleStep: Double = 0.125
    static let minimumVerticalOffset: Double = -72
    static let maximumVerticalOffset: Double = 72

    static func clampedScale(_ scale: Double) -> Double {
        guard scale.isFinite else {
            return defaultScale
        }

        return min(max(scale, minimumScale), maximumScale)
    }

    static func clampedBeatFraction(_ fraction: Double?) -> Double? {
        guard let fraction,
              fraction.isFinite else {
            return nil
        }

        return min(max(fraction, 0), 0.9999)
    }

    static func clampedVerticalOffset(_ offset: Double) -> Double {
        guard offset.isFinite else {
            return 0
        }

        return min(max(offset, minimumVerticalOffset), maximumVerticalOffset)
    }
}

enum CuePosition: String, Codable, CaseIterable, Hashable {
    case above
    case below
    case leadingEdge
    case trailingEdge
}

enum CueEmphasis: String, Codable, CaseIterable, Hashable {
    case subtle
    case normal
    case strong
}

struct RoadmapObject: Identifiable, Codable, Hashable {
    var id: UUID
    var type: RoadmapType
    var startMeasureID: UUID
    var endMeasureID: UUID?
    var anchorSystemID: UUID?
    var placement: RoadmapPlacement
    var displayText: String?
    var count: Int?
    var linkedTargetID: UUID?
    var rawInput: String?
    var horizontalOffsetWithinMeasure: Double? = nil

    var resolvedDisplayText: String {
        displayText ?? type.defaultDisplayText
    }

    var resolvedHorizontalOffsetWithinMeasure: Double {
        Self.clampedHorizontalOffset(horizontalOffsetWithinMeasure ?? 0)
    }

    static func clampedHorizontalOffset(_ offset: Double) -> Double {
        guard offset.isFinite else {
            return 0
        }

        return min(max(offset, 0), 1)
    }
}

enum RoadmapType: String, Codable, CaseIterable, Hashable {
    case repeatSpan
    case ending1
    case ending2
    case codaMarker
    case toCoda
    case segno
    case ds
    case dsAlCoda
    case dc
    case dcAlFine
    case fine
    case noChord
    case vampCount

    var defaultDisplayText: String {
        switch self {
        case .repeatSpan:
            return "Repeat"
        case .ending1:
            return "1st Ending"
        case .ending2:
            return "2nd Ending"
        case .codaMarker:
            return NotationGlyphCatalog.coda
        case .toCoda:
            return "To \(NotationGlyphCatalog.coda)"
        case .segno:
            return NotationGlyphCatalog.segno
        case .ds:
            return "D.S."
        case .dsAlCoda:
            return "D.S. al \(NotationGlyphCatalog.coda)"
        case .dc:
            return "D.C."
        case .dcAlFine:
            return "D.C. al Fine"
        case .fine:
            return "Fine"
        case .noChord:
            return "N.C."
        case .vampCount:
            return "Vamp"
        }
    }

    var editorMenuDisplayText: String {
        switch self {
        case .codaMarker:
            return "Coda"
        case .toCoda:
            return "To Coda"
        case .segno:
            return "Segno"
        case .dsAlCoda:
            return "D.S. al Coda"
        case .repeatSpan, .ending1, .ending2, .ds, .dc, .dcAlFine, .fine, .noChord, .vampCount:
            return defaultDisplayText
        }
    }

    var editorMenuSystemImageName: String {
        switch self {
        case .codaMarker, .toCoda:
            return "scope"
        case .segno:
            return "signature"
        case .ds, .dsAlCoda, .dc, .dcAlFine:
            return "textformat"
        case .fine:
            return "flag.checkered"
        case .noChord:
            return "nosign"
        case .repeatSpan, .ending1, .ending2, .vampCount:
            return "signpost.right"
        }
    }

    var isEnding: Bool {
        switch self {
        case .ending1, .ending2:
            return true
        default:
            return false
        }
    }

    var isPointMarker: Bool {
        switch self {
        case .codaMarker, .toCoda, .segno, .ds, .dsAlCoda, .dc, .dcAlFine, .fine, .noChord:
            return true
        default:
            return false
        }
    }

    var isStandaloneNotationMarker: Bool {
        switch self {
        case .codaMarker, .segno:
            return true
        default:
            return false
        }
    }

    var containsNotationMarkerGlyph: Bool {
        switch self {
        case .codaMarker, .toCoda, .segno, .dsAlCoda:
            return true
        default:
            return false
        }
    }

    var linkTargetTypes: [RoadmapType] {
        switch self {
        case .toCoda:
            return [.codaMarker]
        case .ds, .dsAlCoda:
            return [.segno]
        case .dcAlFine:
            return [.fine]
        default:
            return []
        }
    }

    var linkTargetSearchDirection: RoadmapLinkTargetSearchDirection {
        switch self {
        case .toCoda:
            return .after
        case .ds, .dsAlCoda, .dcAlFine:
            return .before
        default:
            return .nearest
        }
    }

    var usesStructuredLayout: Bool {
        self == .repeatSpan || isEnding || isPointMarker
    }

    static let navigationPointMarkerTypes: [RoadmapType] = [
        .codaMarker,
        .toCoda,
        .segno,
        .ds,
        .dsAlCoda,
        .dc,
        .dcAlFine,
        .fine,
        .noChord
    ]

    var compactEndingDisplayText: String? {
        switch self {
        case .ending1:
            return "1."
        case .ending2:
            return "2."
        default:
            return nil
        }
    }
}

enum RoadmapLinkTargetSearchDirection: Hashable {
    case before
    case after
    case nearest
}

enum RoadmapPlacement: String, Codable, CaseIterable, Hashable {
    case floatingTop
    case snappedTop
    case snappedBottom
    case inline
}
