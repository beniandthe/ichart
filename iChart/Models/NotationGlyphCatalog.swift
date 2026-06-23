import CoreGraphics
import Foundation

enum NotationGlyphCatalog {
    enum Symbol: Hashable {
        case trebleClef
        case bassClef
        case noteheadWhole
        case noteheadHalf
        case noteheadBlack
        case noteWhole
        case noteHalfUp
        case noteQuarterUp
        case note8thUp
        case slashNotehead
        case slashWholeNotehead
        case slashHalfNotehead
        case augmentationDot
        case flag8thUp
        case flag8thDown
        case wholeRest
        case halfRest
        case quarterRest
        case eighthRest
        case accidentalFlat
        case accidentalSharp
        case coda
        case segno
        case timeSignatureDigit(Int)
    }

    static let trebleClef = "\u{E050}"
    static let bassClef = "\u{E062}"
    static let noteheadWhole = "\u{E0A2}"
    static let noteheadHalf = "\u{E0A3}"
    static let noteheadBlack = "\u{E0A4}"
    static let noteWhole = "\u{E1D2}"
    static let noteHalfUp = "\u{E1D3}"
    static let noteQuarterUp = "\u{E1D5}"
    static let note8thUp = "\u{E1D7}"
    static let slashNotehead = "\u{E100}"
    static let slashWholeNotehead = "\u{E102}"
    static let slashHalfNotehead = "\u{E103}"
    static let augmentationDot = "\u{E1E7}"
    static let flag8thUp = "\u{E240}"
    static let flag8thDown = "\u{E241}"
    static let wholeRest = "\u{E4E3}"
    static let halfRest = "\u{E4E4}"
    static let quarterRest = "\u{E4E5}"
    static let eighthRest = "\u{E4E6}"
    static let accidentalFlat = "\u{E260}"
    static let accidentalSharp = "\u{E262}"
    static let coda = "\u{E048}"
    static let segno = "\u{E047}"

    static func timeSignatureDigit(_ value: Int) -> String? {
        guard (0...9).contains(value),
              let scalar = UnicodeScalar(0xE080 + value) else {
            return nil
        }

        return String(scalar)
    }

    static func glyph(for symbol: Symbol) -> String? {
        switch symbol {
        case .trebleClef:
            return trebleClef
        case .bassClef:
            return bassClef
        case .noteheadWhole:
            return noteheadWhole
        case .noteheadHalf:
            return noteheadHalf
        case .noteheadBlack:
            return noteheadBlack
        case .noteWhole:
            return noteWhole
        case .noteHalfUp:
            return noteHalfUp
        case .noteQuarterUp:
            return noteQuarterUp
        case .note8thUp:
            return note8thUp
        case .slashNotehead:
            return slashNotehead
        case .slashWholeNotehead:
            return slashWholeNotehead
        case .slashHalfNotehead:
            return slashHalfNotehead
        case .augmentationDot:
            return augmentationDot
        case .flag8thUp:
            return flag8thUp
        case .flag8thDown:
            return flag8thDown
        case .wholeRest:
            return wholeRest
        case .halfRest:
            return halfRest
        case .quarterRest:
            return quarterRest
        case .eighthRest:
            return eighthRest
        case .accidentalFlat:
            return accidentalFlat
        case .accidentalSharp:
            return accidentalSharp
        case .coda:
            return coda
        case .segno:
            return segno
        case let .timeSignatureDigit(value):
            return timeSignatureDigit(value)
        }
    }

    static func smuflGlyphName(for symbol: Symbol) -> String? {
        symbol.smuflGlyphName
    }

    static func pointSize(for symbol: Symbol, staffSpace: CGFloat) -> CGFloat {
        max(1, staffSpace * CGFloat(staffSpaceScale(for: symbol)))
    }

    private static func staffSpaceScale(for symbol: Symbol) -> Double {
        switch symbol {
        case .trebleClef, .bassClef:
            return 4.0
        case .timeSignatureDigit:
            return 2.57
        case .noteheadWhole, .noteheadHalf, .noteheadBlack:
            return 2.19
        case .noteWhole:
            return 2.52
        case .noteHalfUp, .noteQuarterUp:
            return 4.9
        case .note8thUp:
            return 5.05
        case .slashNotehead, .slashWholeNotehead, .slashHalfNotehead:
            return 2.29
        case .augmentationDot:
            return 1.24
        case .flag8thUp, .flag8thDown:
            return 2.1
        case .wholeRest, .halfRest:
            return 2.19
        case .quarterRest:
            return 2.67
        case .eighthRest:
            return 2.48
        case .accidentalFlat, .accidentalSharp:
            return 2.1
        case .coda:
            return 3.35
        case .segno:
            return 2.7
        }
    }
}

extension NotationGlyphCatalog.Symbol {
    var smuflGlyphName: String? {
        switch self {
        case .trebleClef:
            return "gClef"
        case .bassClef:
            return "fClef"
        case .noteheadWhole:
            return "noteheadWhole"
        case .noteheadHalf:
            return "noteheadHalf"
        case .noteheadBlack:
            return "noteheadBlack"
        case .noteWhole:
            return "noteWhole"
        case .noteHalfUp:
            return "noteHalfUp"
        case .noteQuarterUp:
            return "noteQuarterUp"
        case .note8thUp:
            return "note8thUp"
        case .slashNotehead:
            return "noteheadSlashVerticalEnds"
        case .slashWholeNotehead:
            return "noteheadSlashWhiteWhole"
        case .slashHalfNotehead:
            return "noteheadSlashWhiteHalf"
        case .augmentationDot:
            return "augmentationDot"
        case .flag8thUp:
            return "flag8thUp"
        case .flag8thDown:
            return "flag8thDown"
        case .wholeRest:
            return "restWhole"
        case .halfRest:
            return "restHalf"
        case .quarterRest:
            return "restQuarter"
        case .eighthRest:
            return "rest8th"
        case .accidentalFlat:
            return "accidentalFlat"
        case .accidentalSharp:
            return "accidentalSharp"
        case .coda:
            return "coda"
        case .segno:
            return "segno"
        case let .timeSignatureDigit(value):
            guard (0...9).contains(value) else {
                return nil
            }

            return "timeSig\(value)"
        }
    }
}
