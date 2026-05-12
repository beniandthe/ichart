import Foundation
#if canImport(PencilKit)
import PencilKit
#endif

enum ChordInkFixtureExportError: Error, Equatable {
    case emptyInk
    case unsupportedChord(String)
    case encodingFailed
}

enum ChordInkFixtureExporter {
    static func fixtureDocument(
        name: String? = nil,
        expectedDisplayText: String,
        strokes: [InkStroke]
    ) throws -> InkFixtureDocument {
        guard !strokes.isEmpty else {
            throw ChordInkFixtureExportError.emptyInk
        }

        guard let match = ChordRecognitionCompendium.match(expectedDisplayText) else {
            throw ChordInkFixtureExportError.unsupportedChord(expectedDisplayText)
        }

        let displayText = match.displayText
        let expectedTopGlyphs = glyphs(
            forWrittenText: expectedDisplayText,
            canonicalDisplayText: displayText
        )

        return InkFixtureDocument(
            name: name ?? fixtureName(for: expectedDisplayText),
            expectedDisplayText: displayText,
            expectedClusterCount: expectedTopGlyphs.count,
            expectedTopGlyphs: expectedTopGlyphs,
            strokes: strokes
        )
    }

    static func fixtureJSONString(
        name: String? = nil,
        expectedDisplayText: String,
        strokes: [InkStroke]
    ) throws -> String {
        let document = try fixtureDocument(
            name: name,
            expectedDisplayText: expectedDisplayText,
            strokes: strokes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)

        guard let string = String(data: data, encoding: .utf8) else {
            throw ChordInkFixtureExportError.encodingFailed
        }

        return string
    }

    #if canImport(PencilKit)
    static func fixtureJSONString(
        name: String? = nil,
        expectedDisplayText: String,
        drawingData: Data
    ) throws -> String {
        try fixtureJSONString(
            name: name,
            expectedDisplayText: expectedDisplayText,
            strokes: PencilKitInkAdapter.inkStrokes(from: drawingData)
        )
    }
    #endif

    static func fixtureName(for displayText: String) -> String {
        let expanded = displayText
            .replacingOccurrences(of: "#", with: "Sharp")
            .replacingOccurrences(of: "♯", with: "Sharp")
            .replacingOccurrences(of: "b", with: "Flat")
            .replacingOccurrences(of: "♭", with: "Flat")
            .replacingOccurrences(of: "+", with: "Augmented")
            .replacingOccurrences(of: "-", with: "Minor")
            .replacingOccurrences(of: "/", with: "Slash")
            .replacingOccurrences(of: "△", with: "Major")
            .replacingOccurrences(of: "Δ", with: "Major")
            .replacingOccurrences(of: "∆", with: "Major")
            .replacingOccurrences(of: "°", with: "Diminished")
            .replacingOccurrences(of: "º", with: "Diminished")
            .replacingOccurrences(of: "ø", with: "HalfDiminished")
            .replacingOccurrences(of: "Ø", with: "HalfDiminished")
            .replacingOccurrences(of: "⌀", with: "HalfDiminished")

        let sanitized = expanded.filter { character in
            character.isLetter || character.isNumber
        }

        return sanitized.isEmpty ? "ChordInkFixture" : sanitized
    }

    static func glyphs(for displayText: String) -> [String] {
        displayText.map { character in
            if character == "Δ" || character == "∆" {
                return "△"
            }

            return String(character)
        }
    }

    private static func glyphs(
        forWrittenText writtenText: String,
        canonicalDisplayText: String
    ) -> [String] {
        let normalizedWrittenText = normalizedWrittenGlyphText(writtenText)
        let supportedGlyphs = Set(["A", "B", "C", "D", "E", "F", "G", "#", "b", "+", "△", "°", "ø", "m", "-", "6", "7", "9", "1", "3", "5", "/"])
        let writtenGlyphs = normalizedWrittenText
            .map(String.init)
            .filter { supportedGlyphs.contains($0) }

        return writtenGlyphs.isEmpty ? glyphs(for: canonicalDisplayText) : writtenGlyphs
    }

    private static func normalizedWrittenGlyphText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "＃", with: "#")
            .replacingOccurrences(of: "sharp", with: "#", options: [.caseInsensitive])
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "flat", with: "b", options: [.caseInsensitive])
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "half-diminished", with: "ø", options: [.caseInsensitive])
            .replacingOccurrences(of: "half diminished", with: "ø", options: [.caseInsensitive])
            .replacingOccurrences(of: "halfdiminished", with: "ø", options: [.caseInsensitive])
            .replacingOccurrences(of: "half-dim", with: "ø", options: [.caseInsensitive])
            .replacingOccurrences(of: "half dim", with: "ø", options: [.caseInsensitive])
            .replacingOccurrences(of: "halfdim", with: "ø", options: [.caseInsensitive])
            .replacingOccurrences(of: "augmented", with: "+", options: [.caseInsensitive])
            .replacingOccurrences(of: "aug", with: "+", options: [.caseInsensitive])
            .replacingOccurrences(of: "diminished", with: "°", options: [.caseInsensitive])
            .replacingOccurrences(of: "dim", with: "°", options: [.caseInsensitive])
            .replacingOccurrences(of: "minor", with: "m", options: [.caseInsensitive])
            .replacingOccurrences(of: "min", with: "m", options: [.caseInsensitive])
            .replacingOccurrences(of: "Δ", with: "△")
            .replacingOccurrences(of: "∆", with: "△")
            .replacingOccurrences(of: "º", with: "°")
            .replacingOccurrences(of: "Ø", with: "ø")
            .replacingOccurrences(of: "⌀", with: "ø")
            .filter { !$0.isWhitespace }
    }
}
