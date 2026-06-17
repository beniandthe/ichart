import Foundation
import CoreGraphics

enum ChordTypographyTokenRole: String, Hashable {
    case primaryText
    case suffixText
    case slashBassText
    case musicSymbol
}

struct ChordTypographyToken: Hashable {
    var text: String
    var role: ChordTypographyTokenRole
}

struct ChartTypographyResolver: Hashable {
    static let simpleChordPrimaryFontSize: CGFloat = 46
    static let simpleChordSuffixScale: CGFloat = 0.54
    static let simpleChordSlashBassScale: CGFloat = 0.56
    static let simpleChordTokenGapWidth: CGFloat = 2
    static let simpleChordEstimatedWidthScale: CGFloat = 0.90
    static let structuredChordPrimaryFontSize: CGFloat = 18
    static let structuredChordSuffixScale: CGFloat = 0.68
    static let structuredChordSlashBassScale: CGFloat = 0.70

    var settings: ChartTypographySettings
    var notationFont: NotationFontPreset

    init(settings: ChartTypographySettings, notationFont: NotationFontPreset) {
        self.settings = settings
        self.notationFont = notationFont
    }

    init(chart: Chart) {
        self.init(settings: chart.typography, notationFont: chart.notationFont)
    }

    var chordFamily: ChartFontFamilyPreset {
        settings.resolvedChordFont
    }

    var headerFamily: ChartFontFamilyPreset {
        settings.resolvedHeaderFont
    }

    var textFamily: ChartFontFamilyPreset {
        settings.resolvedTextFont
    }

    func chordTokens(for symbol: ChordSymbol) -> [ChordTypographyToken] {
        Self.chordTokens(for: symbol)
    }

    static func simpleChordSuffixFontSize(primarySize: CGFloat = simpleChordPrimaryFontSize) -> CGFloat {
        primarySize * simpleChordSuffixScale
    }

    static func simpleChordSlashBassFontSize(primarySize: CGFloat = simpleChordPrimaryFontSize) -> CGFloat {
        primarySize * simpleChordSlashBassScale
    }

    static func structuredChordSuffixFontSize(primarySize: CGFloat = structuredChordPrimaryFontSize) -> CGFloat {
        primarySize * structuredChordSuffixScale
    }

    static func structuredChordSlashBassFontSize(primarySize: CGFloat = structuredChordPrimaryFontSize) -> CGFloat {
        primarySize * structuredChordSlashBassScale
    }

    static func chordTokens(for symbol: ChordSymbol) -> [ChordTypographyToken] {
        let qualityText = normalizedQualityText(for: symbol.quality)
        var tokens: [ChordTypographyToken] = [
            ChordTypographyToken(
                text: "\(symbol.root.rawValue)\(symbol.accidental.rawValue)",
                role: .primaryText
            )
        ]

        if qualityText == "sus", symbol.extensions == ["7"] {
            appendTextToken("7sus", role: .suffixText, to: &tokens)
            appendAlterationAndSlashBassTokens(for: symbol, to: &tokens)
            return tokens
        }

        if qualityText == "alt", symbol.extensions.isEmpty || symbol.extensions == ["7"] {
            appendTextToken("7alt", role: .suffixText, to: &tokens)
            appendSlashBassToken(for: symbol, to: &tokens)
            return tokens
        }

        if qualityText == "-△", symbol.extensions == ["7"], symbol.alterations.isEmpty {
            appendQualityTokens("-△", to: &tokens)
            appendTextToken("7", role: .suffixText, to: &tokens)
            appendSlashBassToken(for: symbol, to: &tokens)
            return tokens
        }

        if qualityText == "-", symbol.extensions == ["6"], symbol.alterations.isEmpty {
            appendTextToken("m6", role: .suffixText, to: &tokens)
            appendSlashBassToken(for: symbol, to: &tokens)
            return tokens
        }

        appendQualityTokens(qualityText, to: &tokens)
        if !symbol.extensions.isEmpty {
            appendTextToken(symbol.extensions.joined(), role: .suffixText, to: &tokens)
        }
        appendAlterationAndSlashBassTokens(for: symbol, to: &tokens)

        return tokens
    }

    private static func appendAlterationAndSlashBassTokens(
        for symbol: ChordSymbol,
        to tokens: inout [ChordTypographyToken]
    ) {
        for alteration in symbol.alterations {
            appendTextToken("(\(alteration))", role: .suffixText, to: &tokens)
        }
        appendSlashBassToken(for: symbol, to: &tokens)
    }

    private static func appendSlashBassToken(
        for symbol: ChordSymbol,
        to tokens: inout [ChordTypographyToken]
    ) {
        guard let slashBass = symbol.slashBass else {
            return
        }

        appendTextToken("/\(slashBass)", role: .slashBassText, to: &tokens)
    }

    static func estimatedChordTokenWidth(
        for symbol: ChordSymbol,
        primaryFontSize: CGFloat,
        suffixFontSize: CGFloat,
        slashBassFontSize: CGFloat? = nil
    ) -> CGFloat {
        let tokens = chordTokens(for: symbol)
        let resolvedSlashBassFontSize = slashBassFontSize
            ?? simpleChordSlashBassFontSize(primarySize: primaryFontSize)
        let gapWidth = tokens.count > 1 ? CGFloat(tokens.count - 1) * simpleChordTokenGapWidth : 0
        let rawWidth = tokens.reduce(CGFloat(0)) { partialWidth, token in
            let fontSize: CGFloat
            switch token.role {
            case .primaryText:
                fontSize = primaryFontSize
            case .suffixText, .musicSymbol:
                fontSize = suffixFontSize
            case .slashBassText:
                fontSize = resolvedSlashBassFontSize
            }
            return partialWidth + token.text.reduce(CGFloat(0)) { characterWidth, character in
                characterWidth + estimatedChordCharacterWidth(character) * (fontSize / 18)
            }
        }

        return max(16, rawWidth * simpleChordEstimatedWidthScale + gapWidth)
    }

    private static func normalizedQualityText(for quality: String) -> String {
        if quality == "△" || quality == "Δ" || quality == "∆" {
            return "△"
        }

        if quality == "maj" || quality == "major" || quality == "M" {
            return "△"
        }

        if quality == "-△" || quality == "-Δ" || quality == "-∆" {
            return "-△"
        }

        if quality.hasPrefix("maj") {
            return "△" + String(quality.dropFirst(3))
        }

        return quality
    }

    private static func appendQualityTokens(_ quality: String, to tokens: inout [ChordTypographyToken]) {
        var textBuffer = ""
        for character in quality {
            if Self.isMusicChordSymbol(character) {
                appendTextToken(textBuffer, role: .suffixText, to: &tokens)
                textBuffer = ""
                tokens.append(ChordTypographyToken(text: String(character), role: .musicSymbol))
            } else {
                textBuffer.append(character)
            }
        }
        appendTextToken(textBuffer, role: .suffixText, to: &tokens)
    }

    private static func appendTextToken(
        _ text: String,
        role: ChordTypographyTokenRole,
        to tokens: inout [ChordTypographyToken]
    ) {
        guard !text.isEmpty else {
            return
        }

        if tokens.last?.role == role {
            tokens[tokens.count - 1].text += text
        } else {
            tokens.append(ChordTypographyToken(text: text, role: role))
        }
    }

    private static func isMusicChordSymbol(_ character: Character) -> Bool {
        character == "△" || character == "Δ" || character == "∆" || character == "°" || character == "ø"
    }

    private static func estimatedChordCharacterWidth(_ character: Character) -> CGFloat {
        if character == "/" { return 5 }
        if character == "(" || character == ")" { return 4 }
        if character == "△" || character == "Δ" || character == "∆" { return 10 }
        if character == "°" { return 6 }
        if character == "ø" { return 9 }
        if character.isNumber { return 8 }
        if character == "b" || character == "#" || character == "♭" || character == "♯" { return 6 }
        if character == "-" { return 5 }
        if character.isLetter { return 10 }
        return 7
    }
}

#if canImport(UIKit)
import UIKit

extension ChartTypographyResolver {
    func chordTextUIFont(size: CGFloat, fallback: UIFont) -> UIFont {
        font(
            named: chordFamily.chordTextPostScriptName,
            size: size,
            fallback: fallback
        )
    }

    func chordSymbolUIFont(size: CGFloat, fallback: UIFont) -> UIFont {
        font(
            named: chordFamily.symbolPostScriptName,
            size: size,
            fallback: notationFont.uiFont(size: size, fallback: fallback)
        )
    }

    func headerUIFont(size: CGFloat, weight: UIFont.Weight, fallback: UIFont) -> UIFont {
        font(
            named: headerFamily.textPostScriptName,
            size: size,
            fallback: fallback.withSize(size).withWeight(weight)
        )
    }

    func textUIFont(size: CGFloat, weight: UIFont.Weight, fallback: UIFont) -> UIFont {
        font(
            named: textFamily.textPostScriptName,
            size: size,
            fallback: fallback.withSize(size).withWeight(weight)
        )
    }

    private func font(named postScriptName: String?, size: CGFloat, fallback: UIFont) -> UIFont {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        guard let postScriptName else {
            return fallback
        }

        return UIFont(name: postScriptName, size: size) ?? fallback
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
#endif
