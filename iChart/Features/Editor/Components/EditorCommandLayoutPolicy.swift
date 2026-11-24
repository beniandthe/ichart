import Foundation

enum EditorChordDraftPreviewUpdatePolicy {
    static func allowsUpdate(
        mode: EditorCanvasMode,
        hasSingleReview: Bool,
        hasBatchReview: Bool,
        hasCorrection: Bool,
        isManualDraftReview: Bool = false
    ) -> Bool {
        mode == .chordEntry && !hasSingleReview && !hasCorrection && (!hasBatchReview || isManualDraftReview)
    }
}

enum EditorCommandDestination: String, CaseIterable, Hashable, Identifiable {
    case documentSettings
    case select
    case chords
    case ink
    case measures
    case repeats
    case timeSignature
    case rhythm
    case text
    case formMarkers

    var id: String { rawValue }
}

enum EditorCommandPlacement: Hashable {
    case documentMenu
    case primaryBar
    case sidebar
}

struct EditorCommandLayoutPolicy {
    static let minimumTapTarget: CGFloat = 44
    static let maximumPrimaryControlCount = 5
    static let navigationColumnCount: CGFloat = 3

    static let primaryDestinations: [EditorCommandDestination] = [
        .select,
        .chords,
        .ink,
        .measures,
        .repeats
    ]

    static func sidebarDestinations(
        includesDedicatedRhythmTool: Bool
    ) -> [EditorCommandDestination] {
        var destinations: [EditorCommandDestination] = [.text, .formMarkers, .timeSignature]
        if includesDedicatedRhythmTool {
            destinations.append(.rhythm)
        }
        return destinations
    }

    static func placement(
        of destination: EditorCommandDestination
    ) -> EditorCommandPlacement {
        switch destination {
        case .documentSettings:
            return .documentMenu
        case .select, .chords, .ink, .measures, .repeats:
            return .primaryBar
        case .timeSignature, .rhythm, .text, .formMarkers:
            return .sidebar
        }
    }

    static func primaryDestination(
        for mode: EditorCanvasMode
    ) -> EditorCommandDestination? {
        switch mode {
        case .browse, .noteEdit:
            return .select
        case .measureEdit:
            return .measures
        case .chordEntry:
            return .chords
        case .freeHand:
            return .ink
        case .repeatEdit:
            return .repeats
        case .timeSignatureEdit, .rhythmicNotationEdit, .textEdit, .formMarkerEdit, .headerEntry:
            return nil
        }
    }

    static func sidebarDestination(for mode: EditorCanvasMode) -> EditorCommandDestination? {
        switch mode {
        case .textEdit:
            return .text
        case .formMarkerEdit:
            return .formMarkers
        case .timeSignatureEdit:
            return .timeSignature
        case .rhythmicNotationEdit:
            return .rhythm
        default:
            return nil
        }
    }

    static func canActivate(
        _ destination: EditorCommandDestination,
        chartIsReady: Bool,
        from mode: EditorCanvasMode
    ) -> Bool {
        switch destination {
        case .select:
            return true
        case .documentSettings:
            return !mode.locksDocumentActions
        case .chords, .ink, .measures, .repeats, .timeSignature, .rhythm, .text, .formMarkers:
            return chartIsReady
        }
    }

    static var primaryControlCount: Int {
        primaryDestinations.count
    }

    static func navigationColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth) / navigationColumnCount
    }
}
