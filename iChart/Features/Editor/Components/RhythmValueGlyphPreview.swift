import SwiftUI

struct RhythmValueGlyphPreview: View {
    let value: RhythmValue
    let notationFont: NotationFontPreset

    var body: some View {
        ZStack {
            if value == .measureRepeat {
                Text(ChordSymbol.chordRepeatDisplayText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .offset(y: 2)
            } else if let restSymbol {
                glyphText(restSymbol, size: restPointSize)
                    .offset(y: restYOffset)
            } else {
                glyphText(noteheadSymbol, size: 24)
                    .offset(x: noteheadXOffset, y: 3)

                if showsStem {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 1.4, height: 25)
                        .offset(x: 8, y: 8)
                }

                if value == .eighth || value == .dottedEighth || value == .sixteenth {
                    glyphText(value == .sixteenth ? NotationGlyphCatalog.flag16thDown : NotationGlyphCatalog.flag8thDown, size: 21)
                        .offset(x: 14, y: 14)
                }

                if value.isDottedReferenceValue {
                    glyphText(NotationGlyphCatalog.augmentationDot, size: 13)
                        .offset(x: 17, y: 3)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(value.referenceDisplayTitle)
    }

    private var restSymbol: String? {
        switch value {
        case .wholeRest:
            return NotationGlyphCatalog.wholeRest
        case .halfRest:
            return NotationGlyphCatalog.halfRest
        case .quarterRest:
            return NotationGlyphCatalog.quarterRest
        case .sixteenthRest:
            return NotationGlyphCatalog.sixteenthRest
        case .eighthRest:
            return NotationGlyphCatalog.eighthRest
        case .slash, .sixteenth, .eighth, .dottedEighth, .quarter, .dottedQuarter, .half, .dottedHalf, .whole, .measureRepeat, .tiedContinuation:
            return nil
        }
    }

    private var noteheadSymbol: String {
        switch value {
        case .whole:
            return NotationGlyphCatalog.slashWholeNotehead
        case .half, .dottedHalf:
            return NotationGlyphCatalog.slashHalfNotehead
        case .slash, .sixteenth, .eighth, .dottedEighth, .quarter, .dottedQuarter:
            return NotationGlyphCatalog.slashNotehead
        case .sixteenthRest, .eighthRest, .quarterRest, .halfRest, .wholeRest, .measureRepeat, .tiedContinuation:
            return NotationGlyphCatalog.slashNotehead
        }
    }

    private var noteheadXOffset: CGFloat {
        value.isDottedReferenceValue ? -6 : -8
    }

    private var showsStem: Bool {
        switch value {
        case .slash, .whole, .wholeRest, .halfRest, .quarterRest, .sixteenthRest, .eighthRest, .measureRepeat, .tiedContinuation:
            return false
        case .sixteenth, .eighth, .dottedEighth, .quarter, .dottedQuarter, .half, .dottedHalf:
            return true
        }
    }

    private var restPointSize: CGFloat {
        switch value {
        case .quarterRest:
            return 29
        case .sixteenthRest:
            return 27
        case .eighthRest:
            return 27
        case .wholeRest, .halfRest:
            return 24
        case .slash, .sixteenth, .eighth, .dottedEighth, .quarter, .dottedQuarter, .half, .dottedHalf, .whole, .measureRepeat, .tiedContinuation:
            return 24
        }
    }

    private var restYOffset: CGFloat {
        switch value {
        case .quarterRest:
            return 0
        case .sixteenthRest:
            return -4
        case .eighthRest:
            return 1
        case .wholeRest:
            return -3
        case .halfRest:
            return 2
        case .slash, .sixteenth, .eighth, .dottedEighth, .quarter, .dottedQuarter, .half, .dottedHalf, .whole, .measureRepeat, .tiedContinuation:
            return 0
        }
    }

    private func glyphText(_ glyph: String, size: CGFloat) -> Text {
        Text(glyph)
            .font(notationFont.notationPreviewFont(size: size))
    }
}
