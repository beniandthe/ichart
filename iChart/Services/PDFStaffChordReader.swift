import Foundation
import PDFKit

/// Assigns selectable chord labels to measures identified from the drawn staff.
enum PDFStaffChordReader {
    static func read(from page: PDFPage, systems: [PDFStaffSystemGeometry]) throws -> [[String]] {
        let glyphs = selectableGlyphs(in: page)
        let rows = try systems.map { system in
            let boundaries = system.barlineXs
            guard boundaries.count >= 2,
                  boundaries.allSatisfy(\.isFinite),
                  zip(boundaries, boundaries.dropFirst()).allSatisfy({ $0 < $1 }),
                  system.staffFrame.height > 0 else {
                throw PDFEditableChartDraftError.unsupportedStructure
            }
            let staff = system.staffFrame
            let sideAllowance = max(2, staff.height * 2)
            let band = CGRect(x: staff.minX - sideAllowance, y: staff.maxY + staff.height * 0.05,
                width: staff.width + sideAllowance * 2, height: max(30, staff.height * 1.8))
            let nearby = glyphs.filter { glyph in
                glyph.frame.minY >= band.minY && glyph.frame.maxY <= band.maxY
                    && glyph.frame.midX >= band.minX && glyph.frame.midX <= band.maxX
            }
            let lines = groupedLines(nearby)
            let chordLines = lines.compactMap { line -> [Token]? in
                let tokens = groupedTokens(line).filter { isPotentialChord($0.text) }
                guard !tokens.isEmpty else { return nil }
                // Labels and form headings occupy higher lanes. The chord
                // baseline is immediately above the top staff line.
                guard tokens.map(\.frame.minY).min()! <= staff.maxY + max(16, staff.height * 0.95) else {
                    return nil
                }
                return tokens
            }
            var measures = [[Token]](repeating: [], count: boundaries.count - 1)
            for token in chordLines.flatMap({ $0 }) {
                // Chord fonts can center their root a little before the bar.
                // Bound the centering allowance so a long slash chord keeps
                // its measure even when its label runs past the next rule.
                let anchorX = token.frame.minX + min(token.frame.width / 2, max(10, staff.height * 0.6))
                guard let index = (0..<(boundaries.count - 1)).first(where: {
                    anchorX >= boundaries[$0] && anchorX < boundaries[$0 + 1]
                }) else { continue }
                measures[index].append(token)
            }
            return measures.map { tokens in
                var preceding: (text: String, symbol: ChordSymbol)?
                return tokens.sorted { $0.frame.minX < $1.frame.minX }.map { token in
                    let text = normalizeChordGlyphs(token.text)
                    if text.hasPrefix("/"), let bass = ChordPitch.parse(String(text.dropFirst())) {
                        guard let previous = preceding else { return text }
                        var symbol = previous.symbol
                        symbol.slashBass = bass.displayText
                        let harmony: String
                        if previous.symbol.slashBass != nil, let slash = previous.text.lastIndex(of: "/") {
                            harmony = String(previous.text[..<slash])
                        } else {
                            harmony = previous.text
                        }
                        let resolved = harmony + "/" + bass.displayText
                        preceding = (resolved, symbol)
                        return resolved
                    }
                    guard let symbol = try? ChordSymbolParser.parse(text), symbol.kind == .rooted else {
                        preceding = nil
                        return text
                    }
                    preceding = (text, symbol)
                    return text
                }.joined(separator: " ")
            }
        }
        return rows
    }

    private struct Glyph {
        let text: String
        let frame: CGRect
    }

    private struct Token {
        var text: String
        var frame: CGRect
    }

    private static func selectableGlyphs(in page: PDFPage) -> [Glyph] {
        guard let string = page.string else { return [] }
        let text = string as NSString
        var glyphs: [Glyph] = []
        var offset = 0
        while offset < text.length {
            let range = text.rangeOfComposedCharacterSequence(at: offset)
            offset = NSMaxRange(range)
            let character = text.substring(with: range)
            guard !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            // PDFKit inserts line separators into its text. Character
            // selections retain the correct text-to-position relationship
            // for these PDFs while raw glyph indices can drift past them.
            guard let selection = page.selection(for: range) else { continue }
            let frame = selection.bounds(for: page).standardized
            guard !frame.isEmpty, !frame.isInfinite,
                  [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) else { continue }
            glyphs.append(Glyph(text: character, frame: frame))
        }
        return glyphs
    }

    private static func groupedLines(_ glyphs: [Glyph]) -> [[Glyph]] {
        var lines: [[Glyph]] = []
        for glyph in glyphs.sorted(by: { $0.frame.midY > $1.frame.midY }) {
            if let index = lines.firstIndex(where: { line in
                guard let reference = line.first else { return false }
                let overlap = min(reference.frame.maxY, glyph.frame.maxY)
                    - max(reference.frame.minY, glyph.frame.minY)
                return overlap >= min(reference.frame.height, glyph.frame.height) * 0.25
            }) {
                lines[index].append(glyph)
            } else {
                lines.append([glyph])
            }
        }
        return lines
    }

    private static func groupedTokens(_ glyphs: [Glyph]) -> [Token] {
        var tokens: [Token] = []
        for glyph in glyphs.sorted(by: { $0.frame.minX < $1.frame.minX }) {
            if let last = tokens.last,
               glyph.frame.minX - last.frame.maxX <= max(2, min(last.frame.height, glyph.frame.height) * 0.65) {
                tokens[tokens.count - 1].text += glyph.text
                tokens[tokens.count - 1].frame = last.frame.union(glyph.frame)
            } else {
                tokens.append(Token(text: glyph.text, frame: glyph.frame))
            }
        }
        return tokens
    }

    private static func isPotentialChord(_ raw: String) -> Bool {
        let text = normalizeChordGlyphs(raw)
        if let symbol = try? ChordSymbolParser.parse(text), symbol.kind == .rooted { return true }
        if text.hasPrefix("/") { return true }
        if ["N.C.", "NC", "%", "./."].contains(text.uppercased()) { return true }
        guard let first = text.first, first.isASCII, first.isUppercase else { return false }
        guard "ABCDEFG".contains(first) || text.dropFirst().first?.isNumber == true else { return false }
        // Whole words in a cue or heading are not chord labels. A chord-like
        // token with an unknown accidental/extension remains visible for review.
        return text.contains(where: { $0.isNumber || "#b♯♭ø°∆△?+-/()".contains($0) })
            && !["D.S.", "D.C.", "D.S.AL", "D.C.AL"].contains(text.uppercased())
    }

    private static func normalizeChordGlyphs(_ text: String) -> String {
        // Common chord-font encodings can expose these legacy Latin glyphs
        // through selectable PDF text while rendering musical signs.
        text.replacingOccurrences(of: "Œ„Š", with: "maj")
            .replacingOccurrences(of: "©", with: "#")
            .replacingOccurrences(of: "¨", with: "b")
            .replacingOccurrences(of: "‹", with: "m")
            .replacingOccurrences(of: "−", with: "-")
    }
}
