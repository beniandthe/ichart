import Foundation

enum PitchSpellingPreference {
    case flats
    case sharps

    static func forAccidental(_ accidental: Accidental) -> PitchSpellingPreference {
        switch accidental {
        case .sharp:
            return .sharps
        case .flat, .natural:
            return .flats
        }
    }
}

struct ChordPitch: Codable, Hashable {
    var root: ChordRoot
    var accidental: Accidental

    var semitone: Int {
        let base: Int

        switch root {
        case .c:
            base = 0
        case .d:
            base = 2
        case .e:
            base = 4
        case .f:
            base = 5
        case .g:
            base = 7
        case .a:
            base = 9
        case .b:
            base = 11
        }

        let adjustment: Int
        switch accidental {
        case .natural:
            adjustment = 0
        case .sharp:
            adjustment = 1
        case .flat:
            adjustment = -1
        }

        return Self.normalized(base + adjustment)
    }

    var displayText: String {
        "\(root.rawValue)\(accidental.rawValue)"
    }

    func transposed(by semitones: Int) -> ChordPitch {
        ChordPitch.from(semitone: Self.normalized(semitone + semitones), preference: .flats)
    }

    func spelled(using preference: PitchSpellingPreference) -> ChordPitch {
        ChordPitch.from(semitone: semitone, preference: preference)
    }

    static func parse(_ text: String) -> ChordPitch? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }

        let rootChar = String(first).uppercased()
        let root: ChordRoot
        switch rootChar {
        case "A":
            root = .a
        case "B":
            root = .b
        case "C":
            root = .c
        case "D":
            root = .d
        case "E":
            root = .e
        case "F":
            root = .f
        case "G":
            root = .g
        default:
            return nil
        }

        let accidental: Accidental
        if trimmed.count == 1 {
            accidental = .natural
        } else if trimmed.count == 2 {
            let accidentalCharacter = trimmed[trimmed.index(after: trimmed.startIndex)]
            switch accidentalCharacter {
            case "#":
                accidental = .sharp
            case "b", "B":
                accidental = .flat
            default:
                return nil
            }
        } else {
            return nil
        }

        return ChordPitch(root: root, accidental: accidental)
    }

    static func from(semitone: Int, preference: PitchSpellingPreference) -> ChordPitch {
        switch preference {
        case .flats:
            switch normalized(semitone) {
            case 0: return ChordPitch(root: .c, accidental: .natural)
            case 1: return ChordPitch(root: .d, accidental: .flat)
            case 2: return ChordPitch(root: .d, accidental: .natural)
            case 3: return ChordPitch(root: .e, accidental: .flat)
            case 4: return ChordPitch(root: .e, accidental: .natural)
            case 5: return ChordPitch(root: .f, accidental: .natural)
            case 6: return ChordPitch(root: .g, accidental: .flat)
            case 7: return ChordPitch(root: .g, accidental: .natural)
            case 8: return ChordPitch(root: .a, accidental: .flat)
            case 9: return ChordPitch(root: .a, accidental: .natural)
            case 10: return ChordPitch(root: .b, accidental: .flat)
            default: return ChordPitch(root: .b, accidental: .natural)
            }
        case .sharps:
            switch normalized(semitone) {
            case 0: return ChordPitch(root: .c, accidental: .natural)
            case 1: return ChordPitch(root: .c, accidental: .sharp)
            case 2: return ChordPitch(root: .d, accidental: .natural)
            case 3: return ChordPitch(root: .d, accidental: .sharp)
            case 4: return ChordPitch(root: .e, accidental: .natural)
            case 5: return ChordPitch(root: .f, accidental: .natural)
            case 6: return ChordPitch(root: .f, accidental: .sharp)
            case 7: return ChordPitch(root: .g, accidental: .natural)
            case 8: return ChordPitch(root: .g, accidental: .sharp)
            case 9: return ChordPitch(root: .a, accidental: .natural)
            case 10: return ChordPitch(root: .a, accidental: .sharp)
            default: return ChordPitch(root: .b, accidental: .natural)
            }
        }
    }

    private static func normalized(_ semitone: Int) -> Int {
        let modulo = semitone % 12
        return modulo >= 0 ? modulo : modulo + 12
    }
}
