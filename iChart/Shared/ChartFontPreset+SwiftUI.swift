import SwiftUI

extension ChartFontPreset {
    private var design: Font.Design {
        switch self {
        case .classic:
            return .default
        case .rounded:
            return .rounded
        case .serif:
            return .serif
        case .mono:
            return .monospaced
        }
    }

    var chordFont: Font {
        .system(.title3, design: design).weight(.semibold)
    }

    var sectionLabelFont: Font {
        .system(.caption, design: design).weight(.bold)
    }

    var cueFont: Font {
        .system(.caption, design: design)
    }

    var metadataFont: Font {
        .system(.subheadline, design: design)
    }
}
