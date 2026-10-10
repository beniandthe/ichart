import Foundation

/// A lossless, typed representation of the chord language accepted by the
/// recognition pipeline. This type deliberately contains no OCR cleanup or
/// handwriting heuristics; those belong before grammar decoding.
enum ChordNotation: Hashable, Codable, Sendable {
    case rooted(Rooted)
    case chordRepeat

    enum Letter: String, CaseIterable, Codable, Hashable, Sendable {
        case a = "A"
        case b = "B"
        case c = "C"
        case d = "D"
        case e = "E"
        case f = "F"
        case g = "G"
    }

    enum Accidental: String, CaseIterable, Codable, Hashable, Sendable {
        case natural = ""
        case sharp = "#"
        case flat = "b"
    }

    struct Pitch: Hashable, Codable, Sendable {
        let letter: Letter
        let accidental: Accidental

        init(letter: Letter, accidental: Accidental = .natural) {
            self.letter = letter
            self.accidental = accidental
        }

        var canonicalDisplay: String {
            letter.rawValue + accidental.rawValue
        }

        static func parseCanonical(_ text: String) -> Pitch? {
            let characters = Array(text)
            guard characters.count == 1 || characters.count == 2,
                  let letter = Letter(rawValue: String(characters[0])) else {
                return nil
            }

            if characters.count == 1 {
                return Pitch(letter: letter)
            }

            guard let accidental = Accidental(rawValue: String(characters[1])),
                  accidental != .natural else {
                return nil
            }

            return Pitch(letter: letter, accidental: accidental)
        }
    }

    enum Form: String, CaseIterable, Codable, Hashable, Sendable {
        case plain
        case minor
        case explicitMajor
        case minorMajor
        case augmented
        case diminished
        case halfDiminished
        case suspended
        case addedTone
        case altered
    }

    enum Extension: String, CaseIterable, Codable, Hashable, Sendable {
        case two = "2"
        case four = "4"
        case six = "6"
        case seven = "7"
        case nine = "9"
        case eleven = "11"
        case thirteen = "13"
        case sixNine = "6/9"
    }

    enum Alteration: String, CaseIterable, Codable, Hashable, Sendable, Comparable {
        case flatThree = "b3"
        case flatFive = "b5"
        case sharpFive = "#5"
        case flatNine = "b9"
        case sharpNine = "#9"
        case sharpEleven = "#11"
        case flatThirteen = "b13"

        var degree: Int {
            switch self {
            case .flatThree:
                return 3
            case .flatFive, .sharpFive:
                return 5
            case .flatNine, .sharpNine:
                return 9
            case .sharpEleven:
                return 11
            case .flatThirteen:
                return 13
            }
        }

        private var accidentalOrder: Int {
            rawValue.first == "b" ? 0 : 1
        }

        static func < (lhs: Alteration, rhs: Alteration) -> Bool {
            if lhs.degree != rhs.degree {
                return lhs.degree < rhs.degree
            }
            return lhs.accidentalOrder < rhs.accidentalOrder
        }
    }

    enum ValidationError: Error, Equatable, Sendable {
        case unsupportedExtension(form: Form, extensionTone: Extension?)
        case alterationsNotAllowed(form: Form)
        case duplicateAlterationDegree(Int)
    }

    struct Rooted: Hashable, Codable, Sendable {
        let root: Pitch
        let form: Form
        let extensionTone: Extension?
        let alterations: [Alteration]
        let slashBass: Pitch?

        init(
            root: Pitch,
            form: Form = .plain,
            extensionTone: Extension? = nil,
            alterations: [Alteration] = [],
            slashBass: Pitch? = nil
        ) throws {
            try Self.validate(form: form, extensionTone: extensionTone, alterations: alterations)

            self.root = root
            self.form = form
            self.extensionTone = extensionTone
            self.alterations = alterations.sorted()
            self.slashBass = slashBass
        }

        var canonicalDisplay: String {
            let descriptor = Self.canonicalDescriptor(form: form, extensionTone: extensionTone)
            let alterationText = alterations.map { "(\($0.rawValue))" }.joined()
            let bassText = slashBass.map { "/\($0.canonicalDisplay)" } ?? ""
            return root.canonicalDisplay + descriptor + alterationText + bassText
        }

        private enum CodingKeys: String, CodingKey {
            case root
            case form
            case extensionTone
            case alterations
            case slashBass
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let root = try container.decode(Pitch.self, forKey: .root)
            let form = try container.decode(Form.self, forKey: .form)
            let extensionTone = try container.decodeIfPresent(Extension.self, forKey: .extensionTone)
            let alterations = try container.decode([Alteration].self, forKey: .alterations)
            let slashBass = try container.decodeIfPresent(Pitch.self, forKey: .slashBass)

            try self.init(
                root: root,
                form: form,
                extensionTone: extensionTone,
                alterations: alterations,
                slashBass: slashBass
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(root, forKey: .root)
            try container.encode(form, forKey: .form)
            try container.encodeIfPresent(extensionTone, forKey: .extensionTone)
            try container.encode(alterations, forKey: .alterations)
            try container.encodeIfPresent(slashBass, forKey: .slashBass)
        }

        static func isValid(form: Form, extensionTone: Extension?) -> Bool {
            switch form {
            case .plain, .minor, .explicitMajor, .augmented:
                return extensionTone == nil || [
                    .six, .seven, .nine, .eleven, .thirteen, .sixNine
                ].contains(extensionTone)

            case .minorMajor:
                return extensionTone.map {
                    [.seven, .nine, .eleven, .thirteen].contains($0)
                } ?? false

            case .diminished:
                return extensionTone == nil || extensionTone == .seven

            case .halfDiminished:
                return extensionTone == .seven

            case .suspended:
                return extensionTone == nil || [
                    .two, .four, .seven, .nine, .thirteen
                ].contains(extensionTone)

            case .addedTone:
                return extensionTone.map {
                    [.two, .four, .nine, .eleven].contains($0)
                } ?? false

            case .altered:
                return extensionTone == .seven
            }
        }

        static func allowsAlterations(form: Form) -> Bool {
            switch form {
            case .plain, .minor, .explicitMajor, .suspended:
                return true
            case .minorMajor, .augmented, .diminished, .halfDiminished, .addedTone, .altered:
                return false
            }
        }

        static func canonicalDescriptor(form: Form, extensionTone: Extension?) -> String {
            let extensionText = extensionTone?.rawValue ?? ""

            switch form {
            case .plain:
                return extensionText
            case .minor:
                return "-" + extensionText
            case .explicitMajor:
                return "△" + extensionText
            case .minorMajor:
                return "-△" + extensionText
            case .augmented:
                return "+" + extensionText
            case .diminished:
                return "°" + extensionText
            case .halfDiminished:
                return "ø" + extensionText
            case .suspended:
                if extensionTone == .seven {
                    return "7sus"
                }
                return "sus" + extensionText
            case .addedTone:
                return "add" + extensionText
            case .altered:
                return "7alt"
            }
        }

        private static func validate(
            form: Form,
            extensionTone: Extension?,
            alterations: [Alteration]
        ) throws {
            guard isValid(form: form, extensionTone: extensionTone) else {
                throw ValidationError.unsupportedExtension(
                    form: form,
                    extensionTone: extensionTone
                )
            }

            guard alterations.isEmpty || allowsAlterations(form: form) else {
                throw ValidationError.alterationsNotAllowed(form: form)
            }

            var encounteredDegrees = Set<Int>()
            for alteration in alterations {
                guard encounteredDegrees.insert(alteration.degree).inserted else {
                    throw ValidationError.duplicateAlterationDegree(alteration.degree)
                }
            }
        }
    }

    var canonicalDisplay: String {
        switch self {
        case .rooted(let chord):
            return chord.canonicalDisplay
        case .chordRepeat:
            return "•/•"
        }
    }
}
