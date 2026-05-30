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
    var rawInput: String?
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

    var resolvedDisplayText: String {
        displayText ?? type.defaultDisplayText
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
            return "Coda"
        case .toCoda:
            return "To Coda"
        case .segno:
            return "Segno"
        case .ds:
            return "D.S."
        case .dsAlCoda:
            return "D.S. al Coda"
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
