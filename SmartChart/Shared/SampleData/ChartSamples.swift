import Foundation

enum ChartSamples {
    static let previewCharts: [Chart] = [
        straightAheadSwing
    ]

    static var syncopatedFunkGroove: Chart {
        let grooveCueID = UUID()
        let dsAlCodaID = UUID()

        let measure1 = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .eighthSubdivision,
            barlineAfter: .single,
            chordEvents: [
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .e, accidental: .flat, quality: "maj", extensions: ["7"], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .dottedQuarter,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: "Ebmaj7"
                ),
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .a, accidental: .flat, quality: "7", extensions: [], alterations: ["#11"], slashBass: nil),
                    startPosition: BeatPosition(beat: 4, subdivision: 1, subdivisionsPerBeat: 2),
                    duration: .eighth,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .accent,
                    rawInput: "Ab7#11"
                )
            ],
            cueTextIDs: [],
            roadmapObjectIDs: [dsAlCodaID]
        )

        let measure2 = Measure(
            id: UUID(),
            index: 2,
            meterOverride: nil,
            beatGridPreset: .eighthSubdivision,
            barlineAfter: .single,
            chordEvents: [
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .d, accidental: .flat, quality: "-", extensions: ["9"], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .half,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .slash,
                    rawInput: "Db-9"
                )
            ],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let measure3 = Measure(
            id: UUID(),
            index: 3,
            meterOverride: nil,
            beatGridPreset: .eighthSubdivision,
            barlineAfter: .single,
            chordEvents: [
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .g, accidental: .natural, quality: "13", extensions: [], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .quarter,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .stab,
                    rawInput: "G13"
                ),
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .c, accidental: .natural, quality: "7", extensions: [], alterations: ["b9"], slashBass: nil),
                    startPosition: BeatPosition(beat: 3, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .quarter,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .accent,
                    rawInput: "C7(b9)"
                )
            ],
            cueTextIDs: [grooveCueID],
            roadmapObjectIDs: []
        )

        let measure4 = Measure(
            id: UUID(),
            index: 4,
            meterOverride: nil,
            beatGridPreset: .eighthSubdivision,
            barlineAfter: .double,
            chordEvents: [
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .f, accidental: .natural, quality: "maj", extensions: ["9"], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .whole,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: "Fmaj9"
                )
            ],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let system = ChartSystem(
            id: UUID(),
            index: 0,
            spacingMode: .automatic,
            lineBreakRule: .automatic,
            measures: [measure1, measure2, measure3, measure4]
        )

        return Chart(
            id: UUID(),
            title: "Late Night Pocket",
            chartType: .chordChart,
            documentKey: .eFlatMajor,
            documentFont: .classic,
            defaultTranspositionView: .concert,
            defaultMeter: Meter(numerator: 4, denominator: 4),
            systems: [system],
            sectionLabels: [
                SectionLabel(
                    id: UUID(),
                    text: "Intro",
                    type: .sectionName,
                    anchorMeasureID: measure1.id,
                    anchorSystemID: system.id,
                    rawInput: "Intro"
                )
            ],
            cueTexts: [
                CueText(
                    id: grooveCueID,
                    text: "hits tight with drums",
                    anchorMeasureID: measure3.id,
                    position: .below,
                    emphasis: .normal,
                    rawInput: "hits tight"
                )
            ],
            roadmapObjects: [
                RoadmapObject(
                    id: dsAlCodaID,
                    type: .dsAlCoda,
                    startMeasureID: measure1.id,
                    endMeasureID: nil,
                    anchorSystemID: system.id,
                    placement: .floatingTop,
                    displayText: nil,
                    count: nil,
                    linkedTargetID: nil,
                    rawInput: "D.S. al Coda"
                )
            ],
            stylePreset: .cleanStudio,
            createdAt: .now,
            updatedAt: .now
        )
    }

    static var straightAheadSwing: Chart {
        let measure1 = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .swung,
            barlineAfter: .single,
            chordEvents: [
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .b, accidental: .flat, quality: "maj", extensions: ["7"], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .half,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: "Bbmaj7"
                ),
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .g, accidental: .natural, quality: "-", extensions: ["7"], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 3, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .half,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: "G-7"
                )
            ],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let measure2 = Measure(
            id: UUID(),
            index: 2,
            meterOverride: nil,
            beatGridPreset: .swung,
            barlineAfter: .final,
            chordEvents: [
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .c, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .whole,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: "C7"
                )
            ],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let system = ChartSystem(
            id: UUID(),
            index: 0,
            spacingMode: .relaxed,
            lineBreakRule: .automatic,
            measures: [measure1, measure2]
        )

        return Chart(
            id: UUID(),
            title: "Turnaround Study",
            composerCredit: "Irving Berlin",
            styleNote: "MED. SWING",
            chartType: .teachingChart,
            documentKey: .bFlatMajor,
            documentFont: .serif,
            defaultTranspositionView: .concert,
            defaultMeter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            systems: [system],
            sectionLabels: [
                SectionLabel(
                    id: UUID(),
                    text: "A",
                    type: .rehearsalMark,
                    anchorMeasureID: measure1.id,
                    anchorSystemID: system.id,
                    rawInput: "A"
                )
            ],
            cueTexts: [],
            roadmapObjects: [],
            stylePreset: .rehearsalDraft,
            createdAt: .now,
            updatedAt: .now
        )
    }
}

extension Chart {
    static func draft(
        title: String,
        key: DocumentKey = .cMajor,
        layoutStyle: ChartLayoutStyle = .leadSheet
    ) -> Chart {
        Chart(
            id: UUID(),
            title: title,
            chartType: .chordChart,
            layoutStyle: layoutStyle,
            documentKey: key,
            documentFont: .classic,
            defaultTranspositionView: .concert,
            defaultMeter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            hasCompletedInitialSetup: false,
            systems: [],
            sectionLabels: [],
            cueTexts: [],
            roadmapObjects: [],
            stylePreset: layoutStyle.defaultStylePreset,
            engravingPreset: layoutStyle.defaultEngravingPreset,
            createdAt: .now,
            updatedAt: .now
        )
    }

    static func blank(
        title: String,
        key: DocumentKey = .cMajor,
        measureCount: Int = 4,
        layoutStyle: ChartLayoutStyle = .leadSheet
    ) -> Chart {
        let normalizedMeasureCount = max(1, measureCount)
        let measureDefaults = layoutStyle.profile.measureDefaults
        let measures = (1...normalizedMeasureCount).map { index in
            Measure(
                id: UUID(),
                index: index,
                meterOverride: nil,
                beatGridPreset: measureDefaults.beatGridPreset,
                barlineAfter: index == normalizedMeasureCount ? .double : .single,
                chordEvents: [],
                cueTextIDs: [],
                roadmapObjectIDs: []
            )
        }

        let system = ChartSystem(
            id: UUID(),
            index: 0,
            spacingMode: measureDefaults.systemSpacingMode,
            lineBreakRule: .automatic,
            measures: measures
        )

        return Chart(
            id: UUID(),
            title: title,
            chartType: .chordChart,
            layoutStyle: layoutStyle,
            documentKey: key,
            documentFont: .classic,
            defaultTranspositionView: .concert,
            defaultMeter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            hasCompletedInitialSetup: true,
            systems: [system],
            sectionLabels: [],
            cueTexts: [],
            roadmapObjects: [],
            stylePreset: layoutStyle.defaultStylePreset,
            engravingPreset: layoutStyle.defaultEngravingPreset,
            createdAt: .now,
            updatedAt: .now
        )
    }
}

extension DocumentKey {
    static let cMajor = DocumentKey(tonic: .c, accidental: .natural, mode: .major)
    static let fMajor = DocumentKey(tonic: .f, accidental: .natural, mode: .major)
    static let bFlatMajor = DocumentKey(tonic: .b, accidental: .flat, mode: .major)
    static let eFlatMajor = DocumentKey(tonic: .e, accidental: .flat, mode: .major)
    static let gMajor = DocumentKey(tonic: .g, accidental: .natural, mode: .major)

    static let commonCreationKeys: [DocumentKey] = [
        .cMajor,
        .fMajor,
        .bFlatMajor,
        .eFlatMajor,
        .gMajor
    ]
}
