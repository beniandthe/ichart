import Foundation

extension ChordNotation {
    enum CanonicalParseError: Error, Equatable, Sendable {
        case empty
        case invalidRoot
        case invalidSlashBass
        case malformedAlteration
        case unsupportedDescriptor
        case invalidCombination(ValidationError)
        case nonCanonical(expected: String)
    }

    /// Parses only the canonical language emitted by `canonicalDisplay`.
    /// Aliases, whitespace, Unicode accidental lookalikes, and OCR repairs are
    /// intentionally rejected rather than silently normalized.
    static func parseCanonical(_ text: String) throws -> ChordNotation {
        guard !text.isEmpty else {
            throw CanonicalParseError.empty
        }

        if text == ChordNotation.chordRepeat.canonicalDisplay {
            return .chordRepeat
        }

        let split = try splitCanonicalSlashBass(from: text)
        let characters = Array(split.chordText)
        guard let first = characters.first,
              let rootLetter = Letter(rawValue: String(first)) else {
            throw CanonicalParseError.invalidRoot
        }

        var rootAccidental = Accidental.natural
        var descriptorStart = 1
        if characters.count > 1,
           let accidental = Accidental(rawValue: String(characters[1])),
           accidental != .natural {
            rootAccidental = accidental
            descriptorStart = 2
        }

        let descriptorAndAlterations = String(characters.dropFirst(descriptorStart))
        let parsedSuffix = try parseCanonicalDescriptorAndAlterations(descriptorAndAlterations)

        let rooted: Rooted
        do {
            rooted = try Rooted(
                root: Pitch(letter: rootLetter, accidental: rootAccidental),
                form: parsedSuffix.form,
                extensionTone: parsedSuffix.extensionTone,
                alterations: parsedSuffix.alterations,
                slashBass: split.slashBass
            )
        } catch let error as ValidationError {
            throw CanonicalParseError.invalidCombination(error)
        }

        let notation = ChordNotation.rooted(rooted)
        guard notation.canonicalDisplay == text else {
            throw CanonicalParseError.nonCanonical(expected: notation.canonicalDisplay)
        }
        return notation
    }

    private static func splitCanonicalSlashBass(
        from text: String
    ) throws -> (chordText: String, slashBass: Pitch?) {
        guard let slashIndex = text.lastIndex(of: "/") else {
            return (text, nil)
        }

        let bassStart = text.index(after: slashIndex)
        let possibleBass = String(text[bassStart...])
        if let bass = Pitch.parseCanonical(possibleBass) {
            return (String(text[..<slashIndex]), bass)
        }

        let previousIndex = slashIndex > text.startIndex
            ? text.index(before: slashIndex)
            : slashIndex
        let nextIndex = text.index(after: slashIndex)
        let isSixNineSeparator = previousIndex < slashIndex
            && text[previousIndex] == "6"
            && nextIndex < text.endIndex
            && text[nextIndex] == "9"
            && text[..<slashIndex].lastIndex(of: "/") == nil

        guard isSixNineSeparator else {
            throw CanonicalParseError.invalidSlashBass
        }
        return (text, nil)
    }

    private static func parseCanonicalDescriptorAndAlterations(
        _ text: String
    ) throws -> (form: Form, extensionTone: Extension?, alterations: [Alteration]) {
        let descriptor: String
        let alterationSuffix: Substring
        if let firstParenthesis = text.firstIndex(of: "(") {
            descriptor = String(text[..<firstParenthesis])
            alterationSuffix = text[firstParenthesis...]
        } else {
            descriptor = text
            alterationSuffix = ""
        }

        var descriptorMatch: (Form, Extension?)?
        for form in Form.allCases {
            for extensionTone in [nil] + Extension.allCases.map(Optional.some) {
                guard Rooted.isValid(form: form, extensionTone: extensionTone),
                      Rooted.canonicalDescriptor(form: form, extensionTone: extensionTone) == descriptor else {
                    continue
                }

                guard descriptorMatch == nil else {
                    // Canonical descriptors must remain one-to-one with the AST.
                    throw CanonicalParseError.unsupportedDescriptor
                }
                descriptorMatch = (form, extensionTone)
            }
        }

        guard let descriptorMatch else {
            throw CanonicalParseError.unsupportedDescriptor
        }

        var alterations: [Alteration] = []
        var remaining = alterationSuffix
        while !remaining.isEmpty {
            guard remaining.first == "(",
                  let closingParenthesis = remaining.firstIndex(of: ")") else {
                throw CanonicalParseError.malformedAlteration
            }

            let tokenStart = remaining.index(after: remaining.startIndex)
            let token = String(remaining[tokenStart..<closingParenthesis])
            guard let alteration = Alteration(rawValue: token) else {
                throw CanonicalParseError.malformedAlteration
            }
            alterations.append(alteration)

            let nextIndex = remaining.index(after: closingParenthesis)
            remaining = remaining[nextIndex...]
        }

        return (descriptorMatch.0, descriptorMatch.1, alterations)
    }
}

/// A semantic-token grammar for constrained decoding. Recognition models can
/// advance one component at a time, prune a beam immediately on `nil`, and
/// commit only states that accept `.end`.
struct ChordNotationGrammar {
    enum TokenKind: CaseIterable, Hashable, Sendable {
        case chordRepeat
        case rootLetter
        case rootAccidental
        case form
        case extensionTone
        case alteration
        case slash
        case bassLetter
        case bassAccidental
        case end
    }

    enum ComponentToken: Hashable, Codable, Sendable {
        case chordRepeat
        case rootLetter(ChordNotation.Letter)
        case rootAccidental(ChordNotation.Accidental)
        case form(ChordNotation.Form)
        case extensionTone(ChordNotation.Extension)
        case alteration(ChordNotation.Alteration)
        case slash
        case bassLetter(ChordNotation.Letter)
        case bassAccidental(ChordNotation.Accidental)
        case end

        var kind: TokenKind {
            switch self {
            case .chordRepeat: return .chordRepeat
            case .rootLetter: return .rootLetter
            case .rootAccidental: return .rootAccidental
            case .form: return .form
            case .extensionTone: return .extensionTone
            case .alteration: return .alteration
            case .slash: return .slash
            case .bassLetter: return .bassLetter
            case .bassAccidental: return .bassAccidental
            case .end: return .end
            }
        }
    }

    fileprivate enum Phase: Hashable, Sendable {
        case start
        case root
        case descriptor
        case alterations
        case slash
        case bass
        case repeatSeen
        case ended
    }

    struct State: Hashable, Sendable {
        fileprivate var phase: Phase = .start
        fileprivate var root: ChordNotation.Pitch?
        fileprivate var form = ChordNotation.Form.plain
        fileprivate var didConsumeForm = false
        fileprivate var extensionTone: ChordNotation.Extension?
        fileprivate var alterations: [ChordNotation.Alteration] = []
        fileprivate var slashBass: ChordNotation.Pitch?
        fileprivate var finalizedNotation: ChordNotation?

        var canEnd: Bool {
            guard phase == .root || phase == .descriptor || phase == .alterations || phase == .bass else {
                return false
            }
            return candidateNotation != nil
        }

        var completedNotation: ChordNotation? {
            phase == .ended ? finalizedNotation : nil
        }

        var isTerminal: Bool {
            phase == .ended
        }

        fileprivate var candidateNotation: ChordNotation? {
            guard let root,
                  let chord = try? ChordNotation.Rooted(
                    root: root,
                    form: form,
                    extensionTone: extensionTone,
                    alterations: alterations,
                    slashBass: slashBass
                  ) else {
                return nil
            }
            return .rooted(chord)
        }
    }

    static let start = State()

    static func transition(from state: State, consuming token: ComponentToken) -> State? {
        guard state.phase != .ended else { return nil }

        var next = state
        switch (state.phase, token) {
        case (.start, .chordRepeat):
            next.phase = .repeatSeen

        case (.start, .rootLetter(let letter)):
            next.root = ChordNotation.Pitch(letter: letter)
            next.phase = .root

        case (.repeatSeen, .end):
            next.finalizedNotation = .chordRepeat
            next.phase = .ended

        case (.root, .rootAccidental(let accidental)):
            guard accidental != .natural, let root = state.root else { return nil }
            next.root = ChordNotation.Pitch(letter: root.letter, accidental: accidental)
            next.phase = .descriptor

        case (.root, .form(let form)), (.descriptor, .form(let form)):
            guard !state.didConsumeForm,
                  form != .plain else {
                return nil
            }

            if let extensionTone = state.extensionTone {
                guard extensionTone == .seven,
                      form == .suspended || form == .altered else {
                    return nil
                }
            } else if form == .altered {
                // `7alt` is canonical, so the extension precedes the form token.
                return nil
            }

            next.form = form
            next.didConsumeForm = true
            guard isPotentiallyValid(form: form, extensionTone: next.extensionTone) else {
                return nil
            }
            next.phase = .descriptor

        case (.root, .extensionTone(let extensionTone)),
             (.descriptor, .extensionTone(let extensionTone)):
            guard state.extensionTone == nil else { return nil }

            if state.didConsumeForm,
               state.form == .suspended,
               extensionTone == .seven {
                // Suspended seventh is spelled `7sus`, not `sus7`.
                return nil
            }
            if state.didConsumeForm, state.form == .altered {
                return nil
            }

            next.extensionTone = extensionTone
            guard isPotentiallyValid(form: state.form, extensionTone: extensionTone) else {
                return nil
            }
            next.phase = .descriptor

        case (.root, .alteration(let alteration)),
             (.descriptor, .alteration(let alteration)),
             (.alterations, .alteration(let alteration)):
            guard state.candidateNotation != nil,
                  ChordNotation.Rooted.allowsAlterations(form: state.form),
                  canAppendCanonical(alteration, to: state.alterations) else {
                return nil
            }
            next.alterations.append(alteration)
            next.phase = .alterations

        case (.root, .slash), (.descriptor, .slash), (.alterations, .slash):
            guard state.candidateNotation != nil else { return nil }
            next.phase = .slash

        case (.slash, .bassLetter(let letter)):
            next.slashBass = ChordNotation.Pitch(letter: letter)
            next.phase = .bass

        case (.bass, .bassAccidental(let accidental)):
            guard accidental != .natural,
                  let bass = state.slashBass,
                  bass.accidental == .natural else {
                return nil
            }
            next.slashBass = ChordNotation.Pitch(letter: bass.letter, accidental: accidental)

        case (.root, .end), (.descriptor, .end), (.alterations, .end), (.bass, .end):
            guard let notation = state.candidateNotation else { return nil }
            next.finalizedNotation = notation
            next.phase = .ended

        default:
            return nil
        }

        return next
    }

    static func allowedNextTokenKinds(from state: State) -> Set<TokenKind> {
        Set(allCandidateTokens.compactMap { token in
            transition(from: state, consuming: token) == nil ? nil : token.kind
        })
    }

    static func tokens(for notation: ChordNotation) -> [ComponentToken] {
        switch notation {
        case .chordRepeat:
            return [.chordRepeat, .end]

        case .rooted(let chord):
            var tokens: [ComponentToken] = [.rootLetter(chord.root.letter)]
            if chord.root.accidental != .natural {
                tokens.append(.rootAccidental(chord.root.accidental))
            }

            switch chord.form {
            case .plain:
                if let extensionTone = chord.extensionTone {
                    tokens.append(.extensionTone(extensionTone))
                }

            case .suspended where chord.extensionTone == .seven,
                 .altered:
                if let extensionTone = chord.extensionTone {
                    tokens.append(.extensionTone(extensionTone))
                }
                tokens.append(.form(chord.form))

            default:
                tokens.append(.form(chord.form))
                if let extensionTone = chord.extensionTone {
                    tokens.append(.extensionTone(extensionTone))
                }
            }

            tokens.append(contentsOf: chord.alterations.map(ComponentToken.alteration))
            if let slashBass = chord.slashBass {
                tokens.append(.slash)
                tokens.append(.bassLetter(slashBass.letter))
                if slashBass.accidental != .natural {
                    tokens.append(.bassAccidental(slashBass.accidental))
                }
            }
            tokens.append(.end)
            return tokens
        }
    }

    private static func isPotentiallyValid(
        form: ChordNotation.Form,
        extensionTone: ChordNotation.Extension?
    ) -> Bool {
        if ChordNotation.Rooted.isValid(form: form, extensionTone: extensionTone) {
            return true
        }

        guard extensionTone == nil else { return false }
        return form == .minorMajor || form == .halfDiminished || form == .addedTone
    }

    private static func canAppendCanonical(
        _ alteration: ChordNotation.Alteration,
        to existing: [ChordNotation.Alteration]
    ) -> Bool {
        guard existing.allSatisfy({ $0.degree != alteration.degree }) else {
            return false
        }
        guard let last = existing.last else { return true }
        return last < alteration
    }

    private static var allCandidateTokens: [ComponentToken] {
        var tokens: [ComponentToken] = [.chordRepeat, .slash, .end]
        tokens.append(contentsOf: ChordNotation.Letter.allCases.map(ComponentToken.rootLetter))
        tokens.append(contentsOf: ChordNotation.Accidental.allCases.map(ComponentToken.rootAccidental))
        tokens.append(contentsOf: ChordNotation.Form.allCases.map(ComponentToken.form))
        tokens.append(contentsOf: ChordNotation.Extension.allCases.map(ComponentToken.extensionTone))
        tokens.append(contentsOf: ChordNotation.Alteration.allCases.map(ComponentToken.alteration))
        tokens.append(contentsOf: ChordNotation.Letter.allCases.map(ComponentToken.bassLetter))
        tokens.append(contentsOf: ChordNotation.Accidental.allCases.map(ComponentToken.bassAccidental))
        return tokens
    }
}
