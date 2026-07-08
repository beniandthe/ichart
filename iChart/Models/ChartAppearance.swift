import CoreGraphics
import Foundation

struct SmuflEngravingDefaults: Codable, Hashable {
    var staffLineThickness: Double
    var stemThickness: Double
    var beamThickness: Double
    var thinBarlineThickness: Double
    var thickBarlineThickness: Double
    var barlineSeparation: Double
    var tieEndpointThickness: Double
    var tieMidpointThickness: Double
}

enum NotationFontPreset: String, Codable, CaseIterable, Hashable, Identifiable {
    case bravura
    case petaluma
    case leland
    case museJazz
    case finaleMaestro
    case finaleJazz
    case finaleBroadway
    case finaleEngraver
    case finaleAsh
    case finaleLegacy

    static let selectableCases: [NotationFontPreset] = [
        .bravura,
        .petaluma,
        .leland,
        .museJazz,
        .finaleMaestro,
        .finaleJazz,
        .finaleBroadway,
        .finaleEngraver,
        .finaleLegacy
    ]

    var id: String { rawValue }

    var releaseSafePreset: NotationFontPreset {
        self == .finaleAsh ? .finaleJazz : self
    }

    var displayText: String {
        switch self {
        case .bravura:
            return "Bravura"
        case .petaluma:
            return "Petaluma"
        case .leland:
            return "Leland"
        case .museJazz:
            return "MuseJazz"
        case .finaleMaestro:
            return "Finale Maestro"
        case .finaleJazz:
            return "Finale Jazz"
        case .finaleBroadway:
            return "Finale Broadway"
        case .finaleEngraver:
            return "Finale Engraver"
        case .finaleAsh:
            return "Finale Ash"
        case .finaleLegacy:
            return "Finale Legacy"
        }
    }

    var detailText: String {
        switch self {
        case .bravura:
            return "Clean engraved notation, close to Dorico defaults."
        case .petaluma:
            return "Handwritten jazz engraving with an organic real-book feel."
        case .leland:
            return "MuseScore-style engraving with broad, readable glyphs."
        case .museJazz:
            return "Open handwritten MuseScore jazz notation family."
        case .finaleMaestro:
            return "Classic Finale notation for polished studio charts."
        case .finaleJazz:
            return "Finale's handwritten jazz notation family."
        case .finaleBroadway:
            return "Bold theater-copyist notation character."
        case .finaleEngraver:
            return "Formal engraved Finale notation."
        case .finaleAsh:
            return "Looser handwritten Finale notation."
        case .finaleLegacy:
            return "Older Finale compatibility look."
        }
    }

    var notationPreviewSampleText: String {
        let four = NotationGlyphCatalog.timeSignatureDigit(4) ?? "4"
        let timeSignature = "\(four)\(four)"
        let flatNote = "\(NotationGlyphCatalog.accidentalFlat)\(NotationGlyphCatalog.noteheadBlack)"
        return [
            NotationGlyphCatalog.trebleClef,
            timeSignature,
            NotationGlyphCatalog.noteQuarterUp,
            NotationGlyphCatalog.eighthRest,
            flatNote,
            NotationGlyphCatalog.coda,
            NotationGlyphCatalog.segno
        ].joined(separator: "  ")
    }

    var postScriptName: String {
        switch self {
        case .bravura:
            return "Bravura"
        case .petaluma:
            return "Petaluma"
        case .leland:
            return "Leland"
        case .museJazz:
            return "MuseJazz"
        case .finaleMaestro:
            return "FinaleMaestro"
        case .finaleJazz:
            return "FinaleJazz"
        case .finaleBroadway:
            return "FinaleBroadway"
        case .finaleEngraver:
            return "FinaleEngraver"
        case .finaleAsh:
            return "FinaleAsh"
        case .finaleLegacy:
            return "FinaleLegacy"
        }
    }

    var textPostScriptName: String? {
        switch self {
        case .bravura:
            return "BravuraText"
        case .petaluma:
            return "PetalumaText"
        case .leland:
            return "LelandText"
        case .museJazz:
            return "MuseJazzText"
        case .finaleMaestro:
            return "FinaleMaestroText"
        case .finaleJazz:
            return "FinaleJazzText"
        case .finaleBroadway:
            return "FinaleBroadwayText"
        case .finaleAsh:
            return "FinaleAshText"
        case .finaleEngraver, .finaleLegacy:
            return nil
        }
    }

    var chordTextPostScriptName: String? {
        switch self {
        case .museJazz:
            return "MuseJazzText"
        case .finaleJazz:
            return "FinaleJazzTextLowercase"
        default:
            return textPostScriptName
        }
    }

    var smuflMetadataDirectoryName: String {
        switch self {
        case .bravura:
            return "Bravura"
        case .petaluma:
            return "Petaluma"
        case .leland:
            return "Leland"
        case .museJazz:
            return "MuseJazz"
        case .finaleMaestro:
            return "Finale Maestro"
        case .finaleJazz:
            return "Finale Jazz"
        case .finaleBroadway:
            return "Finale Broadway"
        case .finaleEngraver:
            return "Finale Engraver"
        case .finaleAsh:
            return "Finale Ash"
        case .finaleLegacy:
            return "Finale Legacy"
        }
    }

    var smuflMetadataFileName: String {
        "\(smuflMetadataDirectoryName).json"
    }

    var smuflEngravingDefaults: SmuflEngravingDefaults {
        SmuflFontMetadataStore.metadata(for: self)?.engravingDefaults ?? fallbackSmuflEngravingDefaults
    }

    private var fallbackSmuflEngravingDefaults: SmuflEngravingDefaults {
        switch self {
        case .bravura, .petaluma:
            return SmuflEngravingDefaults(
                staffLineThickness: 0.13,
                stemThickness: 0.12,
                beamThickness: 0.5,
                thinBarlineThickness: 0.16,
                thickBarlineThickness: 0.5,
                barlineSeparation: 0.4,
                tieEndpointThickness: 0.1,
                tieMidpointThickness: 0.22
            )
        case .leland, .museJazz:
            return SmuflEngravingDefaults(
                staffLineThickness: 0.11,
                stemThickness: 0.1,
                beamThickness: 0.5,
                thinBarlineThickness: 0.18,
                thickBarlineThickness: 0.55,
                barlineSeparation: 0.37,
                tieEndpointThickness: 0.05,
                tieMidpointThickness: 0.21
            )
        case .finaleMaestro:
            return SmuflEngravingDefaults(
                staffLineThickness: 0.091,
                stemThickness: 0.091,
                beamThickness: 0.5,
                thinBarlineThickness: 0.1,
                thickBarlineThickness: 0.5,
                barlineSeparation: 0.5,
                tieEndpointThickness: 0.05,
                tieMidpointThickness: 0.25
            )
        case .finaleJazz, .finaleBroadway, .finaleAsh:
            return SmuflEngravingDefaults(
                staffLineThickness: 0.15,
                stemThickness: 0.15,
                beamThickness: 0.5,
                thinBarlineThickness: 0.15,
                thickBarlineThickness: 0.5,
                barlineSeparation: 0.5,
                tieEndpointThickness: 0.07,
                tieMidpointThickness: 0.33
            )
        case .finaleEngraver, .finaleLegacy:
            return SmuflEngravingDefaults(
                staffLineThickness: 0.07,
                stemThickness: 0.07,
                beamThickness: 0.5,
                thinBarlineThickness: 0.07,
                thickBarlineThickness: 0.5,
                barlineSeparation: 0.5,
                tieEndpointThickness: 0.04,
                tieMidpointThickness: 0.25
            )
        }
    }
}

enum ChartFontFamilyPreset: String, Codable, CaseIterable, Hashable, Identifiable {
    case bravura
    case petaluma
    case leland
    case museJazz
    case finaleMaestro
    case finaleJazz
    case finaleBroadway
    case finaleAsh

    static let selectableCases: [ChartFontFamilyPreset] = [
        .bravura,
        .petaluma,
        .leland,
        .museJazz,
        .finaleMaestro,
        .finaleJazz,
        .finaleBroadway
    ]

    var id: String { rawValue }

    var releaseSafeTextFamily: ChartFontFamilyPreset {
        self == .finaleAsh ? .finaleJazz : self
    }

    var displayText: String {
        switch self {
        case .bravura:
            return "Bravura"
        case .petaluma:
            return "Petaluma"
        case .leland:
            return "Leland"
        case .museJazz:
            return "MuseJazz"
        case .finaleMaestro:
            return "Finale Maestro"
        case .finaleJazz:
            return "Finale Jazz"
        case .finaleBroadway:
            return "Finale Broadway"
        case .finaleAsh:
            return "Finale Ash"
        }
    }

    var detailText: String {
        switch self {
        case .bravura:
            return "Clean engraved text with broad music-symbol support."
        case .petaluma:
            return "Handwritten real-book family with matching text and symbols."
        case .leland:
            return "Broad MuseScore-style notation with readable text support."
        case .museJazz:
            return "Open handwritten jazz family from MuseScore."
        case .finaleMaestro:
            return "Classic Finale studio-copyist look."
        case .finaleJazz:
            return "Finale handwritten jazz family with lowercase-safe chords."
        case .finaleBroadway:
            return "Bold theater-copyist family."
        case .finaleAsh:
            return "Loose handwritten Finale family."
        }
    }

    var notationFont: NotationFontPreset {
        switch self {
        case .bravura:
            return .bravura
        case .petaluma:
            return .petaluma
        case .leland:
            return .leland
        case .museJazz:
            return .museJazz
        case .finaleMaestro:
            return .finaleMaestro
        case .finaleJazz:
            return .finaleJazz
        case .finaleBroadway:
            return .finaleBroadway
        case .finaleAsh:
            return .finaleJazz
        }
    }

    init(notationFont: NotationFontPreset) {
        switch notationFont {
        case .bravura:
            self = .bravura
        case .petaluma:
            self = .petaluma
        case .leland:
            self = .leland
        case .museJazz:
            self = .museJazz
        case .finaleMaestro:
            self = .finaleMaestro
        case .finaleJazz:
            self = .finaleJazz
        case .finaleBroadway:
            self = .finaleBroadway
        case .finaleAsh:
            self = .finaleJazz
        case .finaleEngraver, .finaleLegacy:
            self = .bravura
        }
    }

    var textPostScriptName: String? {
        notationFont.textPostScriptName
    }

    var chordTextPostScriptName: String? {
        notationFont.chordTextPostScriptName
    }

    var symbolPostScriptName: String {
        notationFont.postScriptName
    }
}

struct ChartTypographySettings: Codable, Hashable {
    var matchedSet: ChartFontFamilyPreset
    var chordOverride: ChartFontFamilyPreset?
    var headerOverride: ChartFontFamilyPreset?
    var textOverride: ChartFontFamilyPreset?

    init(
        matchedSet: ChartFontFamilyPreset,
        chordOverride: ChartFontFamilyPreset? = nil,
        headerOverride: ChartFontFamilyPreset? = nil,
        textOverride: ChartFontFamilyPreset? = nil
    ) {
        self.matchedSet = matchedSet.releaseSafeTextFamily
        self.chordOverride = chordOverride?.releaseSafeTextFamily
        self.headerOverride = headerOverride?.releaseSafeTextFamily
        self.textOverride = textOverride?.releaseSafeTextFamily
    }

    private enum CodingKeys: String, CodingKey {
        case matchedSet
        case chordOverride
        case headerOverride
        case textOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            matchedSet: try container.decodeIfPresent(ChartFontFamilyPreset.self, forKey: .matchedSet) ?? .petaluma,
            chordOverride: try container.decodeIfPresent(ChartFontFamilyPreset.self, forKey: .chordOverride),
            headerOverride: try container.decodeIfPresent(ChartFontFamilyPreset.self, forKey: .headerOverride),
            textOverride: try container.decodeIfPresent(ChartFontFamilyPreset.self, forKey: .textOverride)
        )
    }

    static func `default`(for notationFont: NotationFontPreset = .petaluma) -> ChartTypographySettings {
        ChartTypographySettings(matchedSet: ChartFontFamilyPreset(notationFont: notationFont))
    }

    var resolvedChordFont: ChartFontFamilyPreset {
        chordOverride ?? matchedSet
    }

    var resolvedHeaderFont: ChartFontFamilyPreset {
        headerOverride ?? matchedSet
    }

    var resolvedTextFont: ChartFontFamilyPreset {
        textOverride ?? matchedSet
    }
}

enum EngravingPreset: String, Codable, CaseIterable, Hashable, Identifiable {
    case compact
    case balanced
    case wide
    case bold

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .compact:
            return "Compact"
        case .balanced:
            return "Balanced"
        case .wide:
            return "Wide"
        case .bold:
            return "Bold"
        }
    }

    var detailText: String {
        switch self {
        case .compact:
            return "Tighter spacing for dense lead sheets."
        case .balanced:
            return "Default real-book spacing and staff weight."
        case .wide:
            return "More horizontal room for handwriting and rhythms."
        case .bold:
            return "Heavier staff, barlines, stems, and glyphs."
        }
    }

    var glyphScale: Double {
        switch self {
        case .compact:
            return 0.94
        case .balanced, .wide:
            return 1
        case .bold:
            return 1.12
        }
    }
}

extension StylePreset: Identifiable {
    var id: String { rawValue }

    var displayText: String {
        sheetDisplayText(for: .simpleChordSheet)
    }

    var detailText: String {
        sheetDetailText(for: .simpleChordSheet)
    }

    static func sheetPresets(for layoutStyle: ChartLayoutStyle) -> [StylePreset] {
        switch layoutStyle {
        case .simpleChordSheet, .leadSheet:
            return [.cleanStudio, .gigSheet, .plainWhite, .rehearsalDraft]
        case .rhythmSectionSheet:
            return [.cleanStudio, .gigSheet, .rehearsalDraft]
        }
    }

    func sheetDisplayText(for layoutStyle: ChartLayoutStyle) -> String {
        switch layoutStyle {
        case .simpleChordSheet, .leadSheet:
            switch self {
            case .cleanStudio:
                return "Real Book"
            case .gigSheet:
                return "Staff Paper"
            case .plainWhite:
                return "White"
            case .rehearsalDraft:
                return "White Staff"
            }
        case .rhythmSectionSheet:
            switch self {
            case .cleanStudio:
                return "Paper"
            case .gigSheet:
                return "Warm Paper"
            case .plainWhite:
                return "White"
            case .rehearsalDraft:
                return "White"
            }
        }
    }

    func sheetDetailText(for layoutStyle: ChartLayoutStyle) -> String {
        switch layoutStyle {
        case .simpleChordSheet, .leadSheet:
            switch self {
            case .cleanStudio:
                return "Warm real-book paper for chord-first charts."
            case .gigSheet:
                return "Natural staff paper for chord charts that need lines."
            case .plainWhite:
                return "Plain white page with no background staff lines."
            case .rehearsalDraft:
                return "White staff paper for clean rehearsal copies."
            }
        case .rhythmSectionSheet:
            switch self {
            case .cleanStudio:
                return "Plain paper with standard rhythm staff weight."
            case .gigSheet:
                return "Warmer plain paper with stronger rhythm staff weight."
            case .plainWhite:
                return "Plain white paper with standard rhythm staff weight."
            case .rehearsalDraft:
                return "Plain white paper with lighter rhythm staff weight."
            }
        }
    }
}

enum LeadSheetBarlineMetrics {
    static func thinWidth(staffSpace: CGFloat, strokeScale: CGFloat) -> CGFloat {
        max(CGFloat(1.05), staffSpace * 0.075) * strokeScale
    }

    static func thickWidth(staffSpace: CGFloat, strokeScale: CGFloat) -> CGFloat {
        max(CGFloat(1.9), staffSpace * 0.17) * strokeScale
    }

    static func repeatLineWidth(
        staffSpace: CGFloat,
        strokeScale: CGFloat,
        layoutStyle: ChartLayoutStyle
    ) -> CGFloat {
        let structuralWidth = thinWidth(staffSpace: staffSpace, strokeScale: strokeScale)
        if layoutStyle == .simpleChordSheet {
            return max(structuralWidth * 1.65, 1.55 * strokeScale)
        }

        return structuralWidth
    }

    static func separation(staffSpace: CGFloat) -> CGFloat {
        max(CGFloat(2.4), staffSpace * 0.4)
    }

    static func repeatSeparation(staffSpace: CGFloat, layoutStyle: ChartLayoutStyle) -> CGFloat {
        if layoutStyle == .simpleChordSheet {
            return max(CGFloat(2.8), staffSpace * 0.23)
        }

        return max(separation(staffSpace: staffSpace) * 1.55, staffSpace * 0.46)
    }

    static func repeatDotRadius(staffSpace: CGFloat, layoutStyle: ChartLayoutStyle) -> CGFloat {
        if layoutStyle == .simpleChordSheet {
            return max(CGFloat(1.55), staffSpace * 0.135)
        }

        return max(CGFloat(1.45), staffSpace * 0.16)
    }

    static func repeatDotOffset(
        thinLineWidth: CGFloat,
        dotRadius: CGFloat,
        staffSpace: CGFloat,
        layoutStyle: ChartLayoutStyle
    ) -> CGFloat {
        let clearance = layoutStyle == .simpleChordSheet
            ? max(CGFloat(0.65), staffSpace * 0.035)
            : max(CGFloat(0.8), staffSpace * 0.05)
        return thinLineWidth / 2 + dotRadius + clearance
    }
}
