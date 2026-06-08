import Foundation

struct ChartLayoutProfile: Hashable {
    var layoutStyle: ChartLayoutStyle
    var toolbarEmphasis: ChartLayoutToolbarEmphasis
    var primaryToolFocus: [ChartLayoutToolFocus]
    var setupPolicy: ChartLayoutSetupPolicy
    var measureDefaults: ChartLayoutMeasureDefaults
    var notationLanePolicy: ChartLayoutNotationLanePolicy
    var freehandSymbolLanes: Set<FreehandSymbolLane>
    var allowsUserFacingRhythmNoteEditing: Bool
    var rendererRoute: ChartLayoutRendererRoute
    var defaultStylePreset: StylePreset
    var defaultEngravingPreset: EngravingPreset

    var allowsFreehandSymbolInk: Bool {
        !freehandSymbolLanes.isEmpty
    }

    var allowsRhythmicNotationInk: Bool {
        primaryToolFocus.contains(.rhythmNotation)
    }
}

extension Chart {
    var librarySummaryText: String {
        if !hasCompletedInitialSetup {
            return "\(layoutStyle.displayText) · setup pending"
        }

        let measureSummary = measures.isEmpty ? "blank page" : "\(measures.count) measures"
        let visibleSetupParts = layoutStyle.visibleLibrarySetupSummaryParts(for: self)
        return ([layoutStyle.displayText] + visibleSetupParts + [measureSummary]).joined(separator: " · ")
    }
}

private extension ChartLayoutStyle {
    func visibleLibrarySetupSummaryParts(for chart: Chart) -> [String] {
        var parts = [String]()

        if profile.setupPolicy.includesKeySelection {
            parts.append(chart.documentKey.displayText)
        }

        if profile.setupPolicy.includesTimeSignatureSelection {
            parts.append(chart.defaultMeter.displayText)
        }

        return parts
    }
}

enum ChartLayoutToolbarEmphasis: String, Hashable {
    case chordRoadmap
    case rhythmAndHits
    case leadSheetPage
}

enum ChartLayoutToolFocus: String, Hashable {
    case pageSetup
    case measureLayout
    case chordEntry
    case rhythmNotation
    case sectionRoadmap
    case cueText
    case appearance
}

struct ChartLayoutSetupPolicy: Hashable {
    var includesKeySelection: Bool
    var includesTimeSignatureSelection: Bool
    var includesStartingMeasureSelection: Bool
    var clefOptions: [ChartClef]
}

enum ChartClef: String, Codable, CaseIterable, Hashable, Identifiable {
    case treble
    case bass

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .treble:
            return "Treble"
        case .bass:
            return "Bass"
        }
    }
}

struct ChartLayoutMeasureDefaults: Hashable {
    var initialMeasureCount: Int
    var preferredMeasuresPerSystem: Int
    var maximumMeasuresPerSystem: Int?
    var systemSpacingMode: SpacingMode
    var beatGridPreset: BeatGridPreset

    init(
        initialMeasureCount: Int,
        preferredMeasuresPerSystem: Int,
        maximumMeasuresPerSystem: Int? = nil,
        systemSpacingMode: SpacingMode,
        beatGridPreset: BeatGridPreset
    ) {
        self.initialMeasureCount = max(1, initialMeasureCount)
        self.preferredMeasuresPerSystem = max(1, preferredMeasuresPerSystem)
        self.maximumMeasuresPerSystem = maximumMeasuresPerSystem.map { max(1, $0) }
        self.systemSpacingMode = systemSpacingMode
        self.beatGridPreset = beatGridPreset
    }
}

enum ChartLayoutNotationLanePolicy: String, Hashable {
    case chordGrid
    case rhythmHits
    case leadSheetStaff
}

enum ChartLayoutRendererRoute: String, Hashable {
    case currentLeadSheetRenderer
}

extension ChartLayoutStyle {
    var profile: ChartLayoutProfile {
        switch self {
        case .simpleChordSheet:
            return ChartLayoutProfile(
                layoutStyle: self,
                toolbarEmphasis: .chordRoadmap,
                primaryToolFocus: [.chordEntry, .sectionRoadmap, .cueText, .measureLayout, .appearance],
                setupPolicy: ChartLayoutSetupPolicy(
                    includesKeySelection: false,
                    includesTimeSignatureSelection: true,
                    includesStartingMeasureSelection: true,
                    clefOptions: []
                ),
                measureDefaults: ChartLayoutMeasureDefaults(
                    initialMeasureCount: 1,
                    preferredMeasuresPerSystem: 4,
                    maximumMeasuresPerSystem: 20,
                    systemSpacingMode: .compact,
                    beatGridPreset: .simple
                ),
                notationLanePolicy: .chordGrid,
                freehandSymbolLanes: [.chartArea],
                allowsUserFacingRhythmNoteEditing: false,
                rendererRoute: .currentLeadSheetRenderer,
                defaultStylePreset: .cleanStudio,
                defaultEngravingPreset: .compact
            )

        case .rhythmSectionSheet:
            return ChartLayoutProfile(
                layoutStyle: self,
                toolbarEmphasis: .rhythmAndHits,
                primaryToolFocus: [.chordEntry, .rhythmNotation, .sectionRoadmap, .cueText, .measureLayout, .appearance],
                setupPolicy: ChartLayoutSetupPolicy(
                    includesKeySelection: false,
                    includesTimeSignatureSelection: true,
                    includesStartingMeasureSelection: true,
                    clefOptions: []
                ),
                measureDefaults: ChartLayoutMeasureDefaults(
                    initialMeasureCount: 8,
                    preferredMeasuresPerSystem: 3,
                    systemSpacingMode: .relaxed,
                    beatGridPreset: .eighthSubdivision
                ),
                notationLanePolicy: .rhythmHits,
                freehandSymbolLanes: [.belowMeasure],
                allowsUserFacingRhythmNoteEditing: false,
                rendererRoute: .currentLeadSheetRenderer,
                defaultStylePreset: .gigSheet,
                defaultEngravingPreset: .wide
            )

        case .leadSheet:
            return ChartLayoutProfile(
                layoutStyle: self,
                toolbarEmphasis: .leadSheetPage,
                primaryToolFocus: [.pageSetup, .chordEntry, .rhythmNotation, .appearance],
                setupPolicy: ChartLayoutSetupPolicy(
                    includesKeySelection: true,
                    includesTimeSignatureSelection: true,
                    includesStartingMeasureSelection: true,
                    clefOptions: [.treble, .bass]
                ),
                measureDefaults: ChartLayoutMeasureDefaults(
                    initialMeasureCount: 4,
                    preferredMeasuresPerSystem: 4,
                    systemSpacingMode: .automatic,
                    beatGridPreset: .simple
                ),
                notationLanePolicy: .leadSheetStaff,
                freehandSymbolLanes: [],
                allowsUserFacingRhythmNoteEditing: true,
                rendererRoute: .currentLeadSheetRenderer,
                defaultStylePreset: .cleanStudio,
                defaultEngravingPreset: .balanced
            )
        }
    }
}
