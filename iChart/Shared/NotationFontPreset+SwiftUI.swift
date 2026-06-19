import SwiftUI

extension NotationFontPreset {
    func notationPreviewFont(size: CGFloat) -> Font {
        #if canImport(UIKit)
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        #endif
        return .custom(postScriptName, size: size)
    }

    func textPreviewFont(size: CGFloat) -> Font {
        #if canImport(UIKit)
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        #endif

        guard let textPostScriptName else {
            return .system(size: size, weight: .semibold)
        }

        return .custom(textPostScriptName, size: size)
    }

    func chordTextPreviewFont(size: CGFloat) -> Font {
        #if canImport(UIKit)
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        #endif

        guard let chordTextPostScriptName else {
            return .system(size: size, weight: .semibold)
        }

        return .custom(chordTextPostScriptName, size: size)
    }
}

extension ChartFontFamilyPreset {
    func textPreviewFont(size: CGFloat) -> Font {
        notationFont.textPreviewFont(size: size)
    }

    func chordTextPreviewFont(size: CGFloat) -> Font {
        notationFont.chordTextPreviewFont(size: size)
    }

    func notationPreviewFont(size: CGFloat) -> Font {
        notationFont.notationPreviewFont(size: size)
    }
}
