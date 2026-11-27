import Foundation
import PDFKit

/// Assigns selectable chord labels to measures identified from the drawn staff.
enum PDFStaffChordReader {
    static func read(from page: PDFPage, systems: [PDFStaffSystemGeometry]) throws -> [[String]] {
        let source = page.string ?? ""
        let glyphs = try selectableGlyphs(in: page, text: source)
        let readableGlyphs = removingOverprints(from: glyphs, text: source, page: page)
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
            let nearby = readableGlyphs.filter { glyph in
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
                    let text = PDFEditableChartDraft.normalizedChordToken(token.text)
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
                    guard let symbol = PDFEditableChartDraft.parsedChordToken(text) else {
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
        let sourceRange: NSRange
    }

    private struct Token {
        var text: String
        var frame: CGRect
    }

    static func textRemovingOverprintedGlyphs(_ source: String, from page: PDFPage) throws -> String {
        let glyphs = try selectableGlyphs(in: page, text: source)
        let retained = removingOverprints(from: glyphs, text: source, page: page)
        guard glyphs.count != retained.count else { return source }
        let retainedOffsets = Set(retained.flatMap { $0.sourceRange.location..<NSMaxRange($0.sourceRange) })
        let text = NSMutableString(string: source)
        for glyph in glyphs.reversed() where !retainedOffsets.contains(glyph.sourceRange.location) {
            text.deleteCharacters(in: glyph.sourceRange)
        }
        return text as String
    }

    private static func selectableGlyphs(in page: PDFPage, text string: String) throws -> [Glyph] {
        let text = string as NSString
        var glyphs: [Glyph] = []
        var offset = 0
        while offset < text.length {
            let range = text.rangeOfComposedCharacterSequence(at: offset)
            if glyphs.count.isMultiple(of: 128) { try Task.checkCancellation() }
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
            glyphs.append(Glyph(text: character, frame: frame, sourceRange: range))
        }
        return glyphs
    }

    private static func removingOverprints(from glyphs: [Glyph], text: String, page: PDFPage) -> [Glyph] {
        let overprintedRuns = repeatedChordRuns(in: text, page: page)
        let collapsed = glyphs.filter { glyph in
            !overprintedRuns.contains { NSLocationInRange(glyph.sourceRange.location, $0.replacedRange) }
        } + overprintedRuns.map(\.chord)
        let ordered = collapsed.sorted { $0.frame.minX < $1.frame.minX }
        var retained: [Glyph] = []
        for glyph in ordered {
            let box = glyph.frame
            let nearby = retained.indices.reversed().prefix { box.minX - retained[$0].frame.minX <= 1 }
            if let index = nearby.first(where: { index in
                let previous = retained[index]
                guard previous.text == glyph.text else { return false }
                let overlap = box.intersection(previous.frame)
                return overlap.width >= max(box.width, previous.frame.width) * 0.9
                    && overlap.height >= max(box.height, previous.frame.height) * 0.9
            }) {
                // An overprint shares the glyph's position. Repeated letters
                // or digits at separate positions remain part of the chord.
                if glyph.sourceRange.location < retained[index].sourceRange.location {
                    retained[index] = Glyph(text: glyph.text, frame: retained[index].frame,
                        sourceRange: glyph.sourceRange)
                }
            } else {
                retained.append(glyph)
            }
        }
        return retained
    }

    private struct OverprintedChord {
        let chord: Glyph
        let replacedRange: NSRange
    }

    private static let textRun = try! NSRegularExpression(pattern: #"[^\s|]+"#)

    private static func repeatedChordRuns(in text: String, page: PDFPage) -> [OverprintedChord] {
        let source = text as NSString
        let ranges = textRun.matches(in: text, range: NSRange(location: 0, length: source.length)).map(\.range)
        var result: [OverprintedChord] = []
        for (index, range) in ranges.enumerated() {
            if let last = result.last, NSLocationInRange(range.location, last.replacedRange) { continue }
            if range.length >= 2, range.length.isMultiple(of: 2) {
                let first = NSRange(location: range.location, length: range.length / 2)
                let copy = NSRange(location: NSMaxRange(first), length: first.length)
                if let overprint = repeatedChord(first, copy, in: source, page: page) {
                    result.append(overprint)
                    continue
                }
            }
            // PDFKit versions can put a synthesized space between the runs.
            guard let next = ranges.dropFirst(index + 1).first else { continue }
            let separator = NSRange(location: NSMaxRange(range), length: next.location - NSMaxRange(range))
            guard source.substring(with: separator).allSatisfy(\.isWhitespace),
                  let overprint = repeatedChord(range, next, in: source, page: page) else { continue }
            result.append(overprint)
        }
        return result
    }

    private static func repeatedChord(
        _ first: NSRange, _ copy: NSRange, in source: NSString, page: PDFPage
    ) -> OverprintedChord? {
        guard first.length == copy.length else { return nil }
        let chord = source.substring(with: first)
        guard chord == source.substring(with: copy),
              PDFEditableChartDraft.parsedChordToken(chord) != nil,
              let firstFrame = page.selection(for: first)?.bounds(for: page).standardized,
              let copyFrame = page.selection(for: copy)?.bounds(for: page).standardized,
              !firstFrame.isEmpty, !copyFrame.isEmpty else { return nil }

        // Compare both runs as units because PDFKit can warp individual
        // glyph bounds where the run's x coordinate resets.
        let overlap = firstFrame.intersection(copyFrame)
        guard overlap.width >= max(firstFrame.width, copyFrame.width) * 0.55,
              overlap.height >= max(firstFrame.height, copyFrame.height) * 0.9 else { return nil }
        let replacedRange = NSRange(location: first.location, length: NSMaxRange(copy) - first.location)
        return OverprintedChord(chord: Glyph(text: chord, frame: firstFrame.union(copyFrame), sourceRange: first),
            replacedRange: replacedRange)
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
        let text = PDFEditableChartDraft.normalizedChordToken(raw)
        if PDFEditableChartDraft.parsedChordToken(text) != nil { return true }
        if text.hasPrefix("/") { return true }
        if ["N.C.", "NC", "%", "./."].contains(text.uppercased()) { return true }
        guard let first = text.first, first.isASCII, first.isUppercase else { return false }
        guard "ABCDEFG".contains(first) || text.dropFirst().first?.isNumber == true else { return false }
        // Whole words in a cue or heading are not chord labels. A chord-like
        // token with an unknown accidental/extension remains visible for review.
        return text.contains(where: { $0.isNumber || "#b♯♭ø°∆△?+-/()".contains($0) })
            && !["D.S.", "D.C.", "D.S.AL", "D.C.AL"].contains(text.uppercased())
    }
}
