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
    case finaleMaestro
    case finaleJazz
    case finaleBroadway
    case finaleEngraver
    case finaleAsh
    case finaleLegacy

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .bravura:
            return "Bravura"
        case .petaluma:
            return "Petaluma"
        case .leland:
            return "Leland"
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

    var postScriptName: String {
        switch self {
        case .bravura:
            return "Bravura"
        case .petaluma:
            return "Petaluma"
        case .leland:
            return "Leland"
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

    var smuflMetadataDirectoryName: String {
        switch self {
        case .bravura:
            return "Bravura"
        case .petaluma:
            return "Petaluma"
        case .leland:
            return "Leland"
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
        case .leland:
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
        switch self {
        case .cleanStudio:
            return "Classic Real Book"
        case .gigSheet:
            return "Gig Sheet"
        case .rehearsalDraft:
            return "Rehearsal Draft"
        }
    }

    var detailText: String {
        switch self {
        case .cleanStudio:
            return "Centered title, clean paper, and polished chart hierarchy."
        case .gigSheet:
            return "Looser handwritten title treatment for jazz chart sketches."
        case .rehearsalDraft:
            return "Plain working-copy style for fast revisions."
        }
    }
}
