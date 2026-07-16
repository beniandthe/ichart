import Foundation

enum ChartCloudBackupIntent: String, Codable, Hashable {
    case included
    case legacyLocal
    case excluded
}

struct ChartCloudBackupStatus: Codable, Hashable {
    static let schemaVersion = 1

    var intent: ChartCloudBackupIntent
    var ownerID: UUID?
    var firstBackedUpAt: Date?
    var lastBackedUpAt: Date?
    var schemaVersion: Int

    init(
        intent: ChartCloudBackupIntent,
        ownerID: UUID? = nil,
        firstBackedUpAt: Date? = nil,
        lastBackedUpAt: Date? = nil,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.intent = intent
        self.ownerID = ownerID
        self.firstBackedUpAt = firstBackedUpAt
        self.lastBackedUpAt = lastBackedUpAt
        self.schemaVersion = schemaVersion
    }

    static var included: ChartCloudBackupStatus {
        ChartCloudBackupStatus(intent: .included)
    }

    static var legacyLocal: ChartCloudBackupStatus {
        ChartCloudBackupStatus(intent: .legacyLocal)
    }

    var hasRemoteBackupRecord: Bool {
        ownerID != nil || firstBackedUpAt != nil || lastBackedUpAt != nil
    }

    func shouldBackUp(for ownerID: UUID) -> Bool {
        guard intent == .included else {
            return false
        }

        guard let existingOwnerID = self.ownerID else {
            return true
        }

        return existingOwnerID == ownerID
    }

    mutating func includeForBackup() {
        intent = .included
        schemaVersion = Self.schemaVersion
    }

    mutating func markBackedUp(ownerID: UUID, at date: Date) {
        intent = .included
        self.ownerID = ownerID
        firstBackedUpAt = firstBackedUpAt ?? date
        lastBackedUpAt = date
        schemaVersion = Self.schemaVersion
    }
}

struct Chart: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var composerCredit: String?
    var styleNote: String?
    var headerInputMode: ChartHeaderInputMode
    var chartType: ChartType
    var layoutStyle: ChartLayoutStyle
    var documentKey: DocumentKey
    var documentFont: ChartFontPreset
    var notationFont: NotationFontPreset
    var typography: ChartTypographySettings
    var defaultTranspositionView: TranspositionView
    var chordTranspositionSemitones: Int
    var defaultMeter: Meter
    var staffStyle: StaffStyle = .fiveLine
    var defaultClef: ChartClef = .treble
    var hasCompletedInitialSetup: Bool = true
    var systems: [ChartSystem]
    var timeSignatureChanges: [TimeSignatureChange]
    var sectionLabels: [SectionLabel]
    var cueTexts: [CueText]
    var roadmapObjects: [RoadmapObject]
    var freehandSymbols: [FreehandSymbol]
    var stylePreset: StylePreset
    var engravingPreset: EngravingPreset
    var pageHandwrittenNotationData: Data?
    var pageHandwrittenHeaderData: Data?
    var pageHandwrittenChordData: Data?
    var cloudBackupStatus: ChartCloudBackupStatus
    var createdAt: Date
    var updatedAt: Date

    var measures: [Measure] {
        systems.flatMap(\.measures)
    }

    var renderedClef: ChartClef {
        layoutStyle == .rhythmSectionSheet ? .bass : defaultClef
    }

    init(
        id: UUID,
        title: String,
        composerCredit: String? = nil,
        styleNote: String? = nil,
        headerInputMode: ChartHeaderInputMode = .typed,
        chartType: ChartType,
        layoutStyle: ChartLayoutStyle = .leadSheet,
        documentKey: DocumentKey,
        documentFont: ChartFontPreset,
        notationFont: NotationFontPreset = .petaluma,
        typography: ChartTypographySettings? = nil,
        defaultTranspositionView: TranspositionView,
        chordTranspositionSemitones: Int = 0,
        defaultMeter: Meter,
        staffStyle: StaffStyle = .fiveLine,
        defaultClef: ChartClef = .treble,
        hasCompletedInitialSetup: Bool = true,
        systems: [ChartSystem],
        timeSignatureChanges: [TimeSignatureChange] = [],
        sectionLabels: [SectionLabel],
        cueTexts: [CueText],
        roadmapObjects: [RoadmapObject],
        freehandSymbols: [FreehandSymbol] = [],
        stylePreset: StylePreset,
        engravingPreset: EngravingPreset = .balanced,
        pageHandwrittenNotationData: Data? = nil,
        pageHandwrittenHeaderData: Data? = nil,
        pageHandwrittenChordData: Data? = nil,
        cloudBackupStatus: ChartCloudBackupStatus = .included,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.composerCredit = composerCredit
        self.styleNote = styleNote
        self.headerInputMode = headerInputMode
        self.chartType = chartType
        self.layoutStyle = layoutStyle
        self.documentKey = documentKey
        self.documentFont = documentFont
        self.notationFont = notationFont.releaseSafePreset
        self.typography = typography ?? ChartTypographySettings.default(for: self.notationFont)
        self.defaultTranspositionView = defaultTranspositionView
        self.chordTranspositionSemitones = 0
        self.defaultMeter = defaultMeter
        self.staffStyle = staffStyle
        self.defaultClef = defaultClef
        self.hasCompletedInitialSetup = hasCompletedInitialSetup
        self.systems = Self.systemsApplyingChordTransposition(
            to: systems,
            by: chordTranspositionSemitones
        )
        self.timeSignatureChanges = timeSignatureChanges
        self.sectionLabels = sectionLabels
        self.cueTexts = cueTexts
        self.roadmapObjects = roadmapObjects
        self.freehandSymbols = []
        self.stylePreset = stylePreset
        self.engravingPreset = engravingPreset
        self.pageHandwrittenNotationData = pageHandwrittenNotationData
        self.pageHandwrittenHeaderData = pageHandwrittenHeaderData
        self.pageHandwrittenChordData = pageHandwrittenChordData
        self.cloudBackupStatus = cloudBackupStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case composerCredit
        case styleNote
        case headerInputMode
        case chartType
        case layoutStyle
        case documentKey
        case documentFont
        case notationFont
        case typography
        case defaultTranspositionView
        case chordTranspositionSemitones
        case defaultMeter
        case staffStyle
        case defaultClef
        case hasCompletedInitialSetup
        case systems
        case timeSignatureChanges
        case sectionLabels
        case cueTexts
        case roadmapObjects
        case freehandSymbols
        case stylePreset
        case engravingPreset
        case pageHandwrittenNotationData
        case pageHandwrittenHeaderData
        case pageHandwrittenChordData
        case cloudBackupStatus
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        composerCredit = try container.decodeIfPresent(String.self, forKey: .composerCredit)
        styleNote = try container.decodeIfPresent(String.self, forKey: .styleNote)
        headerInputMode = try container.decodeIfPresent(ChartHeaderInputMode.self, forKey: .headerInputMode) ?? .typed
        chartType = try container.decode(ChartType.self, forKey: .chartType)
        layoutStyle = try container.decodeIfPresent(ChartLayoutStyle.self, forKey: .layoutStyle) ?? .leadSheet
        documentKey = try container.decode(DocumentKey.self, forKey: .documentKey)
        documentFont = try container.decode(ChartFontPreset.self, forKey: .documentFont)
        notationFont = (try container.decodeIfPresent(NotationFontPreset.self, forKey: .notationFont) ?? .petaluma)
            .releaseSafePreset
        typography = try container.decodeIfPresent(ChartTypographySettings.self, forKey: .typography)
            ?? ChartTypographySettings.default(for: notationFont)
        defaultTranspositionView = try container.decode(TranspositionView.self, forKey: .defaultTranspositionView)
        let decodedChordTranspositionSemitones = Self.normalizedChordTranspositionSemitones(
            try container.decodeIfPresent(Int.self, forKey: .chordTranspositionSemitones) ?? 0
        )
        chordTranspositionSemitones = 0
        defaultMeter = try container.decode(Meter.self, forKey: .defaultMeter)
        staffStyle = try container.decodeIfPresent(StaffStyle.self, forKey: .staffStyle) ?? .fiveLine
        defaultClef = try container.decodeIfPresent(ChartClef.self, forKey: .defaultClef) ?? .treble
        hasCompletedInitialSetup = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedInitialSetup) ?? true
        let decodedSystems = try container.decode([ChartSystem].self, forKey: .systems)
        systems = Self.systemsApplyingChordTransposition(
            to: decodedSystems,
            by: decodedChordTranspositionSemitones
        )
        timeSignatureChanges = try container.decodeIfPresent([TimeSignatureChange].self, forKey: .timeSignatureChanges) ?? []
        sectionLabels = try container.decode([SectionLabel].self, forKey: .sectionLabels)
        cueTexts = try container.decode([CueText].self, forKey: .cueTexts)
        roadmapObjects = try container.decode([RoadmapObject].self, forKey: .roadmapObjects)
        _ = try container.decodeIfPresent([FreehandSymbol].self, forKey: .freehandSymbols)
        freehandSymbols = []
        stylePreset = try container.decode(StylePreset.self, forKey: .stylePreset)
        engravingPreset = try container.decodeIfPresent(EngravingPreset.self, forKey: .engravingPreset) ?? .balanced
        pageHandwrittenNotationData = try container.decodeIfPresent(Data.self, forKey: .pageHandwrittenNotationData)
        pageHandwrittenHeaderData = try container.decodeIfPresent(Data.self, forKey: .pageHandwrittenHeaderData)
        pageHandwrittenChordData = try container.decodeIfPresent(Data.self, forKey: .pageHandwrittenChordData)
        cloudBackupStatus = try container.decodeIfPresent(ChartCloudBackupStatus.self, forKey: .cloudBackupStatus)
            ?? .legacyLocal
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

extension Chart {
    var shouldBackUpToCloud: Bool {
        cloudBackupStatus.intent == .included
    }

    var hasCloudBackupRecord: Bool {
        cloudBackupStatus.hasRemoteBackupRecord
    }

    mutating func includeInCloudBackup() {
        cloudBackupStatus.includeForBackup()
    }

    mutating func markBackedUpToCloud(ownerID: UUID, at date: Date) {
        cloudBackupStatus.markBackedUp(ownerID: ownerID, at: date)
    }

    func shouldBackUpToCloud(for ownerID: UUID) -> Bool {
        cloudBackupStatus.shouldBackUp(for: ownerID)
    }
}

enum ChartHeaderInputMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case typed
    case handwritten

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .typed:
            return "Typed"
        case .handwritten:
            return "Handwritten"
        }
    }
}

struct ChartSystem: Identifiable, Codable, Hashable {
    var id: UUID
    var index: Int
    var spacingMode: SpacingMode
    var lineBreakRule: LineBreakRule
    var measures: [Measure]
}

enum ChartType: String, Codable, CaseIterable, Hashable {
    case chordChart
    case roadmapChart
    case teachingChart
}

enum ChartLayoutStyle: String, Codable, CaseIterable, Hashable, Identifiable {
    case simpleChordSheet
    case rhythmSectionSheet
    case leadSheet

    static let v1NewChartOptions: [ChartLayoutStyle] = [
        .simpleChordSheet,
        .rhythmSectionSheet
    ]

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .simpleChordSheet:
            return "Simple Chord Sheet"
        case .rhythmSectionSheet:
            return "Rhythm Section Sheet"
        case .leadSheet:
            return "Lead Sheet"
        }
    }

    var detailText: String {
        switch self {
        case .simpleChordSheet:
            return "Dense chord-first grid for fast harmonic roadmaps."
        case .rhythmSectionSheet:
            return "Chord chart with extra room for hits, slashes, and groove cues."
        case .leadSheet:
            return "Staff-based page for melody, chords, and standard notation."
        }
    }

    var systemImageName: String {
        switch self {
        case .simpleChordSheet:
            return "square.grid.2x2"
        case .rhythmSectionSheet:
            return "music.note.list"
        case .leadSheet:
            return "music.quarternote.3"
        }
    }

    var defaultStylePreset: StylePreset {
        profile.defaultStylePreset
    }

    var defaultEngravingPreset: EngravingPreset {
        profile.defaultEngravingPreset
    }
}

struct DocumentKey: Codable, Hashable {
    var tonic: ChordRoot
    var accidental: Accidental
    var mode: KeyMode

    var displayText: String {
        "\(tonic.rawValue)\(accidental.rawValue) \(mode.displayText)"
    }

    func transposed(for view: TranspositionView) -> DocumentKey {
        guard view.semitoneOffsetFromConcert != 0 else { return self }

        let pitch = ChordPitch(root: tonic, accidental: accidental)
        let preference = PitchSpellingPreference.forAccidental(accidental)
        let transposedPitch = pitch.transposed(by: view.semitoneOffsetFromConcert).spelled(using: preference)

        return DocumentKey(
            tonic: transposedPitch.root,
            accidental: transposedPitch.accidental,
            mode: mode
        )
    }
}

enum KeyMode: String, Codable, CaseIterable, Hashable {
    case major
    case minor
    case modal

    var displayText: String {
        switch self {
        case .major:
            return "major"
        case .minor:
            return "minor"
        case .modal:
            return "modal"
        }
    }
}

enum TranspositionView: String, Codable, CaseIterable, Hashable, Identifiable {
    case concert
    case bb
    case eb
    case f

    var id: String { rawValue }

    static let instrumentOptions: [TranspositionView] = [
        .concert,
        .bb,
        .eb,
        .f
    ]

    var displayText: String {
        switch self {
        case .concert:
            return "Concert"
        case .bb:
            return "Bb Horn"
        case .eb:
            return "Eb Horn"
        case .f:
            return "F Horn"
        }
    }

    var intervalDisplayText: String {
        switch self {
        case .concert:
            return "No transpose"
        case .bb:
            return "+M2"
        case .eb:
            return "+M6"
        case .f:
            return "+P5"
        }
    }

    var semitoneOffsetFromConcert: Int {
        switch self {
        case .concert:
            return 0
        case .bb:
            return 2
        case .eb:
            return 9
        case .f:
            return 7
        }
    }
}

extension Chart {
    static func normalizedChordTranspositionSemitones(_ semitones: Int) -> Int {
        let modulo = semitones % 12
        return modulo >= 0 ? modulo : modulo + 12
    }

    static func systemsApplyingChordTransposition(
        to systems: [ChartSystem],
        by semitones: Int
    ) -> [ChartSystem] {
        let normalizedSemitones = normalizedChordTranspositionSemitones(semitones)
        guard normalizedSemitones != 0 else {
            return systems
        }

        var transposedSystems = systems
        for systemIndex in transposedSystems.indices {
            for measureIndex in transposedSystems[systemIndex].measures.indices {
                for chordIndex in transposedSystems[systemIndex].measures[measureIndex].chordEvents.indices {
                    let transposedSymbol = transposedSystems[systemIndex]
                        .measures[measureIndex]
                        .chordEvents[chordIndex]
                        .symbol
                        .transposedForChartDisplay(by: normalizedSemitones)
                    transposedSystems[systemIndex]
                        .measures[measureIndex]
                        .chordEvents[chordIndex]
                        .symbol = transposedSymbol
                    transposedSystems[systemIndex]
                        .measures[measureIndex]
                        .chordEvents[chordIndex]
                        .rawInput = transposedSymbol.displayText
                }
            }
        }

        return transposedSystems
    }

    var chordTranspositionDisplayText: String {
        Self.intervalDisplayText(forNormalizedSemitones: chordTranspositionSemitones)
    }

    var libraryTranspositionText: String {
        guard chordTranspositionSemitones != 0 else {
            return defaultTranspositionView.displayText
        }

        return "\(defaultTranspositionView.displayText) · \(chordTranspositionDisplayText)"
    }

    static func intervalDisplayText(forNormalizedSemitones semitones: Int) -> String {
        switch normalizedChordTranspositionSemitones(semitones) {
        case 0:
            return "Written"
        case 1:
            return "+m2"
        case 2:
            return "+M2"
        case 3:
            return "+m3"
        case 4:
            return "+M3"
        case 5:
            return "+P4"
        case 6:
            return "+tritone"
        case 7:
            return "+P5"
        case 8:
            return "+m6"
        case 9:
            return "+M6"
        case 10:
            return "+m7"
        default:
            return "+M7"
        }
    }

    mutating func setInstrumentTranspositionView(_ view: TranspositionView) {
        defaultTranspositionView = view
        chordTranspositionSemitones = 0
        updatedAt = .now
    }

    func displayedChordSymbol(for chordEvent: ChordEvent) -> ChordSymbol {
        chordEvent
            .transposed(for: defaultTranspositionView)
            .symbol
            .transposedForChartDisplay(by: chordTranspositionSemitones)
    }
}

enum ChartFontPreset: String, Codable, CaseIterable, Hashable {
    case classic
    case rounded
    case serif
    case mono

    var displayText: String {
        switch self {
        case .classic:
            return "Classic"
        case .rounded:
            return "Rounded"
        case .serif:
            return "Serif"
        case .mono:
            return "Mono"
        }
    }
}

enum StylePreset: String, Codable, CaseIterable, Hashable {
    case cleanStudio
    case gigSheet
    case plainWhite
    case rehearsalDraft
}

enum StaffStyle: String, Codable, Hashable {
    case fiveLine
}

enum SpacingMode: String, Codable, CaseIterable, Hashable {
    case automatic
    case relaxed
    case compact
}

enum LineBreakRule: String, Codable, CaseIterable, Hashable {
    case automatic
    case forced
    case keepWithNext
}
