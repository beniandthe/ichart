import Foundation

struct Meter: Codable, Hashable {
    var numerator: Int
    var denominator: Int

    var displayText: String {
        "\(numerator)/\(denominator)"
    }

    var beatUnitWholeNoteLength: Double {
        1 / Double(denominator)
    }

    var measureLengthInWholeNotes: Double {
        Double(numerator) / Double(denominator)
    }
}

enum TimeSignatureApplicationScope: Hashable {
    case fixedMeasureCount(Int)
    case toEndOfPiece
    case toNextTimeSignature
}

struct TimeSignatureChange: Identifiable, Codable, Hashable {
    var id: UUID
    var afterMeasureID: UUID
    var meter: Meter
}

struct BeatPosition: Codable, Hashable {
    var beat: Int
    var subdivision: Int
    var subdivisionsPerBeat: Int

    var displayText: String {
        guard subdivision > 0 else { return "\(beat)" }

        let marker: String
        if subdivisionsPerBeat == 2 {
            marker = subdivision == 1 ? "&" : ".\(subdivision)"
        } else if subdivisionsPerBeat == 4 {
            let markers = ["", "e", "&", "a"]
            marker = subdivision < markers.count ? markers[subdivision] : ".\(subdivision)"
        } else {
            marker = ".\(subdivision)"
        }
        let safeMarker = marker
        return "\(beat)\(safeMarker)"
    }

    func startOffset(in meter: Meter) -> Double? {
        guard beat >= 1,
              beat <= meter.numerator,
              subdivision >= 0,
              subdivisionsPerBeat > 0,
              subdivision < subdivisionsPerBeat else {
            return nil
        }

        let beatLength = meter.measureLengthInWholeNotes / Double(meter.numerator)
        let subdivisionOffset = Double(subdivision) / Double(subdivisionsPerBeat)
        return (Double(beat - 1) + subdivisionOffset) * beatLength
    }
}

enum MeasurePlacementGrid {
    static let subdivisionsPerBeat = 2

    static func snappedFraction(_ fraction: Double, in meter: Meter) -> Double {
        let subdivisionIndex = snappedSubdivisionIndex(for: fraction, in: meter)
        return Double(subdivisionIndex) / Double(subdivisionCount(in: meter))
    }

    static func beatPosition(for fraction: Double, in meter: Meter) -> BeatPosition {
        let subdivisionIndex = snappedSubdivisionIndex(for: fraction, in: meter)
        let beat = subdivisionIndex / subdivisionsPerBeat + 1
        let subdivision = subdivisionIndex % subdivisionsPerBeat

        return BeatPosition(
            beat: beat,
            subdivision: subdivision,
            subdivisionsPerBeat: subdivisionsPerBeat
        )
    }

    private static func snappedSubdivisionIndex(for fraction: Double, in meter: Meter) -> Int {
        let clampedFraction = fraction.isFinite ? min(max(fraction, 0), 0.9999) : 0
        let subdivisionCount = subdivisionCount(in: meter)
        let rawSubdivisionIndex = Int((clampedFraction * Double(subdivisionCount)).rounded())
        return min(max(0, rawSubdivisionIndex), subdivisionCount - 1)
    }

    private static func subdivisionCount(in meter: Meter) -> Int {
        max(1, meter.numerator * subdivisionsPerBeat)
    }
}

extension BeatPosition {
    init?(offsetInWholeNotes offset: Double, meter: Meter) {
        let beatLength = meter.measureLengthInWholeNotes / Double(meter.numerator)
        guard beatLength > 0 else {
            return nil
        }

        let beatOffset = offset / beatLength
        let wholeBeats = Int(floor(beatOffset + 0.0001))
        let remainder = beatOffset - Double(wholeBeats)

        if abs(remainder) < 0.0001 {
            self.init(beat: wholeBeats + 1, subdivision: 0, subdivisionsPerBeat: 1)
            return
        }

        if abs(remainder - 0.5) < 0.0001 {
            self.init(beat: wholeBeats + 1, subdivision: 1, subdivisionsPerBeat: 2)
            return
        }

        if abs(remainder - 0.25) < 0.0001 {
            self.init(beat: wholeBeats + 1, subdivision: 1, subdivisionsPerBeat: 4)
            return
        }

        if abs(remainder - 0.75) < 0.0001 {
            self.init(beat: wholeBeats + 1, subdivision: 3, subdivisionsPerBeat: 4)
            return
        }

        return nil
    }
}

enum RhythmValue: String, Codable, CaseIterable, Hashable {
    case slash
    case sixteenth
    case sixteenthRest
    case eighth
    case eighthRest
    case dottedEighth
    case quarter
    case quarterRest
    case dottedQuarter
    case half
    case halfRest
    case dottedHalf
    case whole
    case wholeRest
    case tiedContinuation

    var displayText: String {
        switch self {
        case .slash:
            return "slash"
        case .sixteenth:
            return "sixteenth"
        case .sixteenthRest:
            return "sixteenth rest"
        case .eighth:
            return "eighth"
        case .eighthRest:
            return "eighth rest"
        case .dottedEighth:
            return "dotted eighth"
        case .quarter:
            return "quarter"
        case .quarterRest:
            return "quarter rest"
        case .dottedQuarter:
            return "dotted quarter"
        case .half:
            return "half"
        case .halfRest:
            return "half rest"
        case .dottedHalf:
            return "dotted half"
        case .whole:
            return "whole"
        case .wholeRest:
            return "whole rest"
        case .tiedContinuation:
            return "tie"
        }
    }

    var wholeNoteLength: Double {
        switch self {
        case .slash:
            return 0.25
        case .sixteenth:
            return 0.0625
        case .sixteenthRest:
            return 0.0625
        case .eighth:
            return 0.125
        case .eighthRest:
            return 0.125
        case .dottedEighth:
            return 0.1875
        case .quarter:
            return 0.25
        case .quarterRest:
            return 0.25
        case .dottedQuarter:
            return 0.375
        case .half:
            return 0.5
        case .halfRest:
            return 0.5
        case .dottedHalf:
            return 0.75
        case .whole:
            return 1.0
        case .wholeRest:
            return 1.0
        case .tiedContinuation:
            return 0.0
        }
    }

    func wholeNoteLength(in meter: Meter) -> Double {
        switch self {
        case .slash:
            return meter.beatUnitWholeNoteLength
        case .sixteenth, .sixteenthRest, .eighth, .eighthRest, .dottedEighth, .quarter, .quarterRest, .dottedQuarter,
             .half, .halfRest, .dottedHalf, .whole, .wholeRest, .tiedContinuation:
            return wholeNoteLength
        }
    }

    var isRest: Bool {
        switch self {
        case .sixteenthRest, .eighthRest, .quarterRest, .halfRest, .wholeRest:
            return true
        case .slash, .sixteenth, .eighth, .dottedEighth, .quarter, .dottedQuarter, .half, .dottedHalf, .whole, .tiedContinuation:
            return false
        }
    }
}

enum RhythmPlacement: String, Codable, CaseIterable, Hashable {
    case aboveChord
    case belowChord
    case inline
    case hidden
}

enum HitStyle: String, Codable, CaseIterable, Hashable {
    case none
    case accent
    case stab
    case slash
}
