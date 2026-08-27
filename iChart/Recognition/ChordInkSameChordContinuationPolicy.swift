import Foundation

enum ChordInkSameChordContinuationPolicy {
    static func allowsContinuation(from previousText: String?, to newText: String?) -> Bool {
        guard let previousText = normalized(previousText),
              let newText = normalized(newText),
              previousText != newText,
              let previousMatch = ChordRecognitionCompendium.match(previousText),
              let newMatch = ChordRecognitionCompendium.match(newText) else {
            return false
        }

        let previousSymbol = previousMatch.symbol
        let newSymbol = newMatch.symbol
        guard previousSymbol.kind == .rooted,
              newSymbol.kind == .rooted,
              previousSymbol.root == newSymbol.root,
              previousSymbol.accidental == newSymbol.accidental,
              previousSymbol.slashBass == newSymbol.slashBass,
              previousSymbol.alterations == newSymbol.alterations else {
            return false
        }

        guard let previousSuffix = suffixText(for: previousSymbol),
              let newSuffix = suffixText(for: newSymbol),
              !previousSuffix.isEmpty,
              !newSuffix.isEmpty,
              newSuffix != previousSuffix else {
            return false
        }

        return isSupportedSuffixCompletion(from: previousSuffix, to: newSuffix)
    }

    private static func isSupportedSuffixCompletion(from previousSuffix: String, to newSuffix: String) -> Bool {
        if newSuffix.hasPrefix(previousSuffix) {
            let addedText = String(newSuffix.dropFirst(previousSuffix.count))
            return supportedTrailingCompletions.contains(addedText)
        }

        return supportedCanonicalSuffixPairs.contains(
            ChordInkSameChordSuffixPair(previous: previousSuffix, new: newSuffix)
        )
    }

    private static func suffixText(for symbol: ChordSymbol) -> String? {
        let rootText = symbol.root.rawValue + symbol.accidental.rawValue
        let displayText = symbol.displayText
        guard displayText.hasPrefix(rootText) else {
            return nil
        }

        return String(displayText.dropFirst(rootText.count))
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let supportedTrailingCompletions: Set<String> = [
        "4",
        "7"
    ]

    private static let supportedCanonicalSuffixPairs: Set<ChordInkSameChordSuffixPair> = [
        ChordInkSameChordSuffixPair(previous: "7", new: "7sus"),
        ChordInkSameChordSuffixPair(previous: "7", new: "7sus4"),
        ChordInkSameChordSuffixPair(previous: "7sus", new: "7sus4")
    ]
}

private struct ChordInkSameChordSuffixPair: Hashable {
    var previous: String
    var new: String
}
