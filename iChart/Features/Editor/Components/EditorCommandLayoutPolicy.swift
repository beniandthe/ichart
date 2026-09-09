import Foundation

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
    case toolsMenu
}

struct EditorCommandLayoutPolicy {
    static let minimumTapTarget: CGFloat = 44
    static let maximumPrimaryControlCount = 5
    static let navigationColumnCount: CGFloat = 3

    static let primaryDestinations: [EditorCommandDestination] = [
        .select,
        .chords,
        .ink,
        .measures
    ]

    static func toolsDestinations(
        includesDedicatedRhythmTool: Bool
    ) -> [EditorCommandDestination] {
        var destinations: [EditorCommandDestination] = [
            .repeats,
            .timeSignature
        ]
        if includesDedicatedRhythmTool {
            destinations.append(.rhythm)
        }
        destinations.append(contentsOf: [.text, .formMarkers])
        return destinations
    }

    static func placement(
        of destination: EditorCommandDestination
    ) -> EditorCommandPlacement {
        switch destination {
        case .documentSettings:
            return .documentMenu
        case .select, .chords, .ink, .measures:
            return .primaryBar
        case .repeats, .timeSignature, .rhythm, .text, .formMarkers:
            return .toolsMenu
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
        case .repeatEdit, .timeSignatureEdit, .rhythmicNotationEdit, .textEdit, .headerEntry:
            return nil
        }
    }

    static func isToolsMenuActive(for mode: EditorCanvasMode) -> Bool {
        switch mode {
        case .repeatEdit, .timeSignatureEdit, .rhythmicNotationEdit, .textEdit:
            return true
        case .browse, .measureEdit, .headerEntry, .chordEntry, .noteEdit, .freeHand:
            return false
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
        primaryDestinations.count + 1 // The labeled Tools menu.
    }

    static func navigationColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth) / navigationColumnCount
    }
}
