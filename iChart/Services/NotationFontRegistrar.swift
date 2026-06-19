#if canImport(UIKit)
import CoreText
import Foundation
import UIKit

enum NotationFontRegistrar {
    private static var hasRegisteredFonts = false

    static let bundledFontFileNames = [
        "Bravura.otf",
        "BravuraText.otf",
        "Petaluma.otf",
        "PetalumaScript.otf",
        "PetalumaText.otf",
        "Leland.otf",
        "LelandText.otf",
        "MuseJazz.otf",
        "MuseJazzText.otf",
        "FinaleAsh.otf",
        "FinaleAshText.otf",
        "FinaleBroadway.otf",
        "FinaleBroadwayLegacyText.otf",
        "FinaleBroadwayText.otf",
        "FinaleEngraver.otf",
        "FinaleJazz.otf",
        "FinaleJazzText.otf",
        "FinaleJazzTextLowercase.otf",
        "FinaleLegacy.otf",
        "FinaleMaestro.otf",
        "FinaleMaestroText-Regular.otf",
        "FinaleMaestroText-Bold.otf",
        "FinaleMaestroText-Italic.otf",
        "FinaleMaestroText-BoldItalic.otf"
    ]

    static func registerBundledFontsIfNeeded() {
        guard !hasRegisteredFonts else {
            return
        }

        hasRegisteredFonts = true

        for fileName in bundledFontFileNames {
            let resourceName = (fileName as NSString).deletingPathExtension
            let fileExtension = (fileName as NSString).pathExtension
            let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: fileExtension,
                subdirectory: "Fonts"
            ) ?? Bundle.main.url(
                forResource: resourceName,
                withExtension: fileExtension
            )
            guard let url else {
                continue
            }

            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension NotationFontPreset {
    func uiFont(size: CGFloat, fallback: UIFont) -> UIFont {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        return UIFont(name: postScriptName, size: size) ?? fallback
    }

    func textUIFont(size: CGFloat, fallback: UIFont) -> UIFont {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        guard let textPostScriptName else {
            return fallback
        }

        return UIFont(name: textPostScriptName, size: size) ?? fallback
    }

    func chordTextUIFont(size: CGFloat, fallback: UIFont) -> UIFont {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        guard let chordTextPostScriptName else {
            return fallback
        }

        return UIFont(name: chordTextPostScriptName, size: size) ?? fallback
    }
}
#endif
