import Foundation

/// Explicit edit shortcuts, not additional handwriting recognition evidence.
/// These never enter a chord's saved source candidate signature.
enum ChordInkCorrectionQualityPolicy {
    static func choiceTexts(for currentText: String, excluding excludedTexts: Set<String> = []) -> [String] {
        guard let current = ChordRecognitionCompendium.match(currentText),
              current.symbol.kind == .rooted else { return [] }

        let source = current.symbol
        var seen = excludedTexts
        seen.insert(current.displayText)
        return ["△", "", "-", "ø", "°", "-△"].compactMap { quality in
            var changed = source
            changed.quality = quality
            guard let match = ChordRecognitionCompendium.match(changed.displayText),
                  match.symbol.kind == .rooted,
                  match.symbol.root == source.root,
                  match.symbol.accidental == source.accidental,
                  match.symbol.extensions == source.extensions,
                  match.symbol.alterations == source.alterations,
                  match.symbol.slashBass == source.slashBass,
                  seen.insert(match.displayText).inserted else { return nil }
            return match.displayText
        }
    }
}
