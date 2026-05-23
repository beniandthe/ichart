import Foundation

enum MeterParseError: Error {
    case invalidFormat
    case invalidValue
}

enum ChordSymbolParseError: Error {
    case invalidRoot
    case invalidSlashBass
    case unsupportedMajorQuality
    case unsupportedQuality
    case unsupportedExtension
    case unsupportedAlteration
}

enum MeterParser {
    static func parse(_ text: String) throws -> Meter {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: "/", maxSplits: 1).map(String.init)

        guard pieces.count == 2,
              let numerator = Int(pieces[0]),
              let denominator = Int(pieces[1]) else {
            throw MeterParseError.invalidFormat
        }

        let validDenominators = [1, 2, 4, 8, 16, 32]
        guard numerator > 0, validDenominators.contains(denominator) else {
            throw MeterParseError.invalidValue
        }

        return Meter(numerator: numerator, denominator: denominator)
    }
}

enum ChordSymbolParser {
    static func parse(_ text: String) throws -> ChordSymbol {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rootPitch = parseLeadingPitch(from: trimmed) else {
            throw ChordSymbolParseError.invalidRoot
        }

        let descriptorStart = descriptorStartIndex(in: trimmed)
        let descriptorText = String(trimmed[descriptorStart...])
        let pieces = descriptorText
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        let descriptor = pieces.first ?? ""
        let slashBass = pieces.count > 1 ? pieces[1] : nil

        let parsedSlashBass = slashBass.flatMap(ChordPitch.parse)

        if slashBass != nil,
           parsedSlashBass == nil {
            throw ChordSymbolParseError.invalidSlashBass
        }

        if isUnsupportedMajorDescriptor(descriptor) {
            throw ChordSymbolParseError.unsupportedMajorQuality
        }

        let parsedDescriptor = try parseDescriptor(descriptor)

        return ChordSymbol(
            root: rootPitch.root,
            accidental: rootPitch.accidental,
            quality: parsedDescriptor.quality,
            extensions: parsedDescriptor.extensions,
            alterations: parsedDescriptor.alterations,
            slashBass: parsedSlashBass?.displayText
        )
    }

    private static func parseLeadingPitch(from text: String) -> ChordPitch? {
        guard let first = text.first else { return nil }

        let root = String(first)
        if text.count > 1 {
            let nextIndex = text.index(after: text.startIndex)
            let second = text[nextIndex]

            if second == "#" || second == "b" || second == "B" {
                return ChordPitch.parse(root + String(second))
            }
        }

        return ChordPitch.parse(root)
    }

    private static func descriptorStartIndex(in text: String) -> String.Index {
        guard text.count > 1 else { return text.endIndex }

        let secondIndex = text.index(after: text.startIndex)
        let second = text[secondIndex]

        if second == "#" || second == "b" || second == "B" {
            return text.index(after: secondIndex)
        }

        return secondIndex
    }

    private static func parseDescriptor(_ descriptor: String) throws -> (quality: String, extensions: [String], alterations: [String]) {
        var quality = ""
        var extensions: [String] = []
        var alterations: [String] = []

        let descriptor = descriptor
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "＃", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "º", with: "°")
            .replacingOccurrences(of: "Ø", with: "ø")
            .replacingOccurrences(of: "⌀", with: "ø")
        let characters = Array(descriptor)
        var index = 0
        let lowercasedDescriptor = descriptor.lowercased()

        if let halfDiminishedPrefixLength = halfDiminishedPrefixLength(in: lowercasedDescriptor) {
            quality = "ø"
            index = halfDiminishedPrefixLength
        } else if let diminishedPrefixLength = diminishedPrefixLength(in: lowercasedDescriptor) {
            quality = "°"
            index = diminishedPrefixLength
        } else if let firstCharacter = characters.first,
           firstCharacter.isHalfDiminishedQuality {
            quality = "ø"
            index = 1
        } else if let firstCharacter = characters.first,
                  firstCharacter.isDiminishedQuality {
            quality = "°"
            index = 1
        } else if lowercasedDescriptor.hasPrefix("altered") {
            quality = "alt"
            extensions = ["7"]
            index = 7
        } else if lowercasedDescriptor.hasPrefix("alt") {
            quality = "alt"
            extensions = ["7"]
            index = 3
        } else if let firstCharacter = characters.first,
                  firstCharacter.isAugmentedQuality {
            quality = "+"
            index = 1
        } else if lowercasedDescriptor.hasPrefix("augmented") {
            quality = "+"
            index = 9
        } else if lowercasedDescriptor.hasPrefix("aug") {
            quality = "+"
            index = 3
        } else if let firstCharacter = characters.first,
           firstCharacter.isMajorTriangleQuality {
            quality = "△"
            index = 1
        } else if lowercasedDescriptor.hasPrefix("suspended") {
            quality = "sus"
            index = 9
        } else if lowercasedDescriptor.hasPrefix("sus") {
            quality = "sus"
            index = 3
        } else if lowercasedDescriptor.hasPrefix("minor") {
            quality = "-"
            index = 5
        } else if lowercasedDescriptor.hasPrefix("min") {
            quality = "-"
            index = 3
        } else if descriptor.hasPrefix("m") {
            quality = "-"
            index = 1
        } else if lowercasedDescriptor.hasPrefix("-") {
            quality = "-"
            index = 1
        }

        while index < characters.count {
            let character = characters[index]

            if character == "#" || character == "b" {
                var token = String(character)
                index += 1

                while index < characters.count, characters[index].isNumber {
                    token.append(characters[index])
                    index += 1
                }

                guard isSupportedAlteration(token) else {
                    throw ChordSymbolParseError.unsupportedAlteration
                }

                alterations.append(token)
            } else if character.isNumber {
                var token = String(character)
                index += 1

                while index < characters.count, characters[index].isNumber {
                    token.append(characters[index])
                    index += 1
                }

                guard isSupportedExtension(token, quality: quality) else {
                    throw ChordSymbolParseError.unsupportedExtension
                }

                extensions.append(token)

                if token == "7",
                   quality.isEmpty,
                   let suspendedSuffixEndIndex = namedSuffixEndIndex(
                       in: characters,
                       startIndex: index,
                       longForm: "suspended",
                       shortForm: "sus"
                   ) {
                    quality = "sus"
                    index = suspendedSuffixEndIndex
                } else if token == "7",
                   quality.isEmpty,
                   let alteredSuffixEndIndex = namedSuffixEndIndex(
                       in: characters,
                       startIndex: index,
                       longForm: "altered",
                       shortForm: "alt"
                   ) {
                    quality = "alt"
                    index = alteredSuffixEndIndex
                }
            } else if character == "(" {
                let parsedParenthetical = try parseParenthesizedAlterations(
                    in: characters,
                    startIndex: index
                )
                alterations.append(contentsOf: parsedParenthetical.alterations)
                index = parsedParenthetical.nextIndex
            } else if character == ")" {
                throw ChordSymbolParseError.unsupportedQuality
            } else if character.isMajorTriangleQuality {
                if quality == "-",
                   extensions.isEmpty,
                   alterations.isEmpty {
                    quality = "-△"
                    index += 1
                    continue
                }

                if (!quality.isEmpty && quality != "△") || !extensions.isEmpty || !alterations.isEmpty {
                    throw ChordSymbolParseError.unsupportedQuality
                }

                quality = "△"
                index += 1
            } else if !character.isWhitespace {
                throw ChordSymbolParseError.unsupportedQuality
            } else {
                index += 1
            }
        }

        normalizeDiminishedAliases(
            quality: &quality,
            extensions: &extensions,
            alterations: &alterations
        )
        try validateSupportedQualityCombination(
            quality: quality,
            extensions: extensions,
            alterations: alterations
        )

        return (quality, extensions, alterations)
    }

    private static func namedSuffixEndIndex(
        in characters: [Character],
        startIndex: Int,
        longForm: String,
        shortForm: String
    ) -> Int? {
        var index = startIndex
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }

        let remainingText = String(characters[index...]).lowercased()
        if remainingText.hasPrefix(longForm) {
            return index + longForm.count
        }

        if remainingText.hasPrefix(shortForm) {
            return index + shortForm.count
        }

        return nil
    }

    private static func parseParenthesizedAlterations(
        in characters: [Character],
        startIndex: Int
    ) throws -> (alterations: [String], nextIndex: Int) {
        var alterations: [String] = []
        var index = startIndex + 1

        while index < characters.count {
            let character = characters[index]

            if character == ")" {
                guard !alterations.isEmpty else {
                    throw ChordSymbolParseError.unsupportedAlteration
                }

                return (alterations, index + 1)
            }

            if character.isWhitespace {
                index += 1
                continue
            }

            guard character == "#" || character == "b" else {
                throw ChordSymbolParseError.unsupportedAlteration
            }

            var token = String(character)
            index += 1

            while index < characters.count, characters[index].isNumber {
                token.append(characters[index])
                index += 1
            }

            guard isSupportedAlteration(token) else {
                throw ChordSymbolParseError.unsupportedAlteration
            }

            alterations.append(token)
        }

        throw ChordSymbolParseError.unsupportedAlteration
    }

    private static func halfDiminishedPrefixLength(in lowercasedDescriptor: String) -> Int? {
        [
            "half-diminished",
            "half diminished",
            "halfdiminished",
            "half-dim",
            "half dim",
            "halfdim",
            "hdim"
        ]
        .first { lowercasedDescriptor.hasPrefix($0) }
        .map(\.count)
    }

    private static func diminishedPrefixLength(in lowercasedDescriptor: String) -> Int? {
        ["diminished", "dim"].first { lowercasedDescriptor.hasPrefix($0) }?.count
    }

    private static func normalizeDiminishedAliases(
        quality: inout String,
        extensions: inout [String],
        alterations: inout [String]
    ) {
        if quality == "ø", extensions.isEmpty {
            extensions = ["7"]
        }

        if quality == "-",
           extensions == ["7"],
           alterations == ["b5"] {
            quality = "ø"
            alterations = []
        }
    }

    private static func validateSupportedQualityCombination(
        quality: String,
        extensions: [String],
        alterations: [String]
    ) throws {
        if quality == "°" {
            guard alterations.isEmpty,
                  extensions.isEmpty || extensions == ["7"] else {
                throw ChordSymbolParseError.unsupportedQuality
            }
        }

        if quality == "ø" {
            guard extensions == ["7"],
                  alterations.isEmpty else {
                throw ChordSymbolParseError.unsupportedQuality
            }
        }

        if quality == "+" {
            guard alterations.isEmpty else {
                throw ChordSymbolParseError.unsupportedQuality
            }
        }

        if quality == "alt" {
            guard extensions == ["7"],
                  alterations.isEmpty else {
                throw ChordSymbolParseError.unsupportedQuality
            }
        }

        if quality == "-△" {
            guard extensions == ["7"],
                  alterations.isEmpty else {
                throw ChordSymbolParseError.unsupportedQuality
            }
        }

        if quality == "sus" {
            guard (extensions.isEmpty || extensions == ["4"] || extensions == ["7"]),
                  alterations.isEmpty else {
                throw ChordSymbolParseError.unsupportedQuality
            }
        }
    }

    private static func isSupportedExtension(_ token: String, quality: String) -> Bool {
        if quality == "sus" {
            return token == "4"
        }

        return ["6", "7", "9", "11", "13"].contains(token)
    }

    private static func isSupportedAlteration(_ token: String) -> Bool {
        ["b5", "#5", "b9", "#9", "#11", "b13"].contains(token)
    }

    private static func isUnsupportedMajorDescriptor(_ descriptor: String) -> Bool {
        let trimmedDescriptor = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedDescriptor = trimmedDescriptor.lowercased()

        if trimmedDescriptor == "M" {
            return true
        }

        if trimmedDescriptor.first == "M" {
            let suffix = trimmedDescriptor.dropFirst()
            if suffix.allSatisfy(\.isNumber) {
                return true
            }
        }

        return lowercasedDescriptor.hasPrefix("maj")
            || lowercasedDescriptor.hasPrefix("major")
    }
}

private extension Character {
    var isMajorTriangleQuality: Bool {
        self == "△" || self == "Δ" || self == "∆"
    }

    var isDiminishedQuality: Bool {
        self == "°" || self == "º"
    }

    var isHalfDiminishedQuality: Bool {
        self == "ø" || self == "Ø" || self == "⌀"
    }

    var isAugmentedQuality: Bool {
        self == "+"
    }
}
