import Foundation
import CoreGraphics

func normalizedPersistentInkDrawingData(_ drawingData: Data?) -> Data? {
    guard let drawingData,
          !drawingData.isEmpty else {
        return nil
    }

    #if canImport(UIKit)
    return LeadSheetPersistentInkColorPolicy.normalizedDrawingData(drawingData)
    #else
    return drawingData
    #endif
}

struct PersistentInkCoordinateSpace: Codable, Hashable {
    var width: Double
    var height: Double
    var measureAnchors: [PersistentInkMeasureAnchor]?
    var chordAnchors: [PersistentInkChordAnchor]?

    init(
        width: Double,
        height: Double,
        measureAnchors: [PersistentInkMeasureAnchor]? = nil,
        chordAnchors: [PersistentInkChordAnchor]? = nil
    ) {
        self.width = width
        self.height = height
        self.measureAnchors = measureAnchors?.isEmpty == true ? nil : measureAnchors
        self.chordAnchors = chordAnchors?.isEmpty == true ? nil : chordAnchors
    }

    init?(
        size: CGSize,
        measureAnchors: [PersistentInkMeasureAnchor]? = nil,
        chordAnchors: [PersistentInkChordAnchor]? = nil
    ) {
        guard size.width > 0,
              size.height > 0,
              size.width.isFinite,
              size.height.isFinite else {
            return nil
        }

        self.width = Double(size.width)
        self.height = Double(size.height)
        self.measureAnchors = measureAnchors?.isEmpty == true ? nil : measureAnchors
        self.chordAnchors = chordAnchors?.isEmpty == true ? nil : chordAnchors
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}

struct PersistentInkFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init?(rect: CGRect) {
        guard rect.minX.isFinite,
              rect.minY.isFinite,
              rect.width > 0,
              rect.height > 0,
              rect.width.isFinite,
              rect.height.isFinite else {
            return nil
        }

        x = Double(rect.minX)
        y = Double(rect.minY)
        width = Double(rect.width)
        height = Double(rect.height)
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct PersistentInkPoint: Codable, Hashable {
    var x: Double
    var y: Double

    init?(point: CGPoint) {
        guard point.x.isFinite,
              point.y.isFinite else {
            return nil
        }

        x = Double(point.x)
        y = Double(point.y)
    }

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct PersistentInkMeasureAnchor: Codable, Hashable {
    var measureID: UUID
    var frame: PersistentInkFrame

    init?(measureID: UUID, frame: CGRect) {
        guard let persistentFrame = PersistentInkFrame(rect: frame) else {
            return nil
        }

        self.measureID = measureID
        self.frame = persistentFrame
    }
}

struct PersistentInkChordAnchor: Codable, Hashable {
    var measureID: UUID
    var chordID: UUID
    var frame: PersistentInkFrame
    var registrationPoint: PersistentInkPoint?

    init?(
        measureID: UUID,
        chordID: UUID,
        frame: CGRect,
        registrationPoint: CGPoint? = nil
    ) {
        guard let persistentFrame = PersistentInkFrame(rect: frame) else {
            return nil
        }

        self.measureID = measureID
        self.chordID = chordID
        self.frame = persistentFrame
        self.registrationPoint = registrationPoint.flatMap(PersistentInkPoint.init(point:))
    }
}

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
    var hasExplicitClefSelection: Bool = false
    var hasCompletedInitialSetup: Bool = true
    var systems: [ChartSystem]
    var keyChanges: [KeyChange]
    var keyChangeSystemBreakMeasureIDs: Set<UUID>
    var timeSignatureChanges: [TimeSignatureChange]
    var sectionLabels: [SectionLabel]
    var cueTexts: [CueText]
    var roadmapObjects: [RoadmapObject]
    var freehandSymbols: [FreehandSymbol]
    var stylePreset: StylePreset
    var engravingPreset: EngravingPreset
    var pageHandwrittenNotationData: Data?
    var pageHandwrittenNotationCoordinateSpace: PersistentInkCoordinateSpace?
    var pageHandwrittenHeaderData: Data?
    var pageHandwrittenHeaderCoordinateSpace: PersistentInkCoordinateSpace?
    var pageHandwrittenChordData: Data?
    var pageHandwrittenChordCoordinateSpace: PersistentInkCoordinateSpace?
    var cloudBackupStatus: ChartCloudBackupStatus
    var createdAt: Date
    var updatedAt: Date

    var measures: [Measure] {
        systems.flatMap(\.measures)
    }

    var renderedClef: ChartClef {
        if layoutStyle == .rhythmSectionSheet && !hasExplicitClefSelection {
            return .bass
        }

        return defaultClef
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
        notationFont: NotationFontPreset = .finaleBroadway,
        typography: ChartTypographySettings? = nil,
        defaultTranspositionView: TranspositionView,
        chordTranspositionSemitones: Int = 0,
        defaultMeter: Meter,
        staffStyle: StaffStyle = .fiveLine,
        defaultClef: ChartClef = .treble,
        hasExplicitClefSelection: Bool = false,
        hasCompletedInitialSetup: Bool = true,
        systems: [ChartSystem],
        keyChanges: [KeyChange] = [],
        keyChangeSystemBreakMeasureIDs: Set<UUID> = [],
        timeSignatureChanges: [TimeSignatureChange] = [],
        sectionLabels: [SectionLabel],
        cueTexts: [CueText],
        roadmapObjects: [RoadmapObject],
        freehandSymbols: [FreehandSymbol] = [],
        stylePreset: StylePreset,
        engravingPreset: EngravingPreset = .balanced,
        pageHandwrittenNotationData: Data? = nil,
        pageHandwrittenNotationCoordinateSpace: PersistentInkCoordinateSpace? = nil,
        pageHandwrittenHeaderData: Data? = nil,
        pageHandwrittenHeaderCoordinateSpace: PersistentInkCoordinateSpace? = nil,
        pageHandwrittenChordData: Data? = nil,
        pageHandwrittenChordCoordinateSpace: PersistentInkCoordinateSpace? = nil,
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
        self.hasExplicitClefSelection = hasExplicitClefSelection
        self.hasCompletedInitialSetup = hasCompletedInitialSetup
        self.systems = Self.systemsApplyingChordTransposition(
            to: systems,
            by: chordTranspositionSemitones
        )
        self.keyChanges = keyChanges
        self.keyChangeSystemBreakMeasureIDs = keyChangeSystemBreakMeasureIDs
        self.timeSignatureChanges = timeSignatureChanges
        self.sectionLabels = sectionLabels
        self.cueTexts = cueTexts
        self.roadmapObjects = roadmapObjects
        self.freehandSymbols = []
        self.stylePreset = stylePreset
        self.engravingPreset = engravingPreset
        self.pageHandwrittenNotationData = normalizedPersistentInkDrawingData(pageHandwrittenNotationData)
        self.pageHandwrittenNotationCoordinateSpace = Self.coordinateSpace(
            pageHandwrittenNotationCoordinateSpace,
            for: self.pageHandwrittenNotationData
        )
        self.pageHandwrittenHeaderData = normalizedPersistentInkDrawingData(pageHandwrittenHeaderData)
        self.pageHandwrittenHeaderCoordinateSpace = Self.coordinateSpace(
            pageHandwrittenHeaderCoordinateSpace,
            for: self.pageHandwrittenHeaderData
        )
        self.pageHandwrittenChordData = normalizedPersistentInkDrawingData(pageHandwrittenChordData)
        self.pageHandwrittenChordCoordinateSpace = Self.coordinateSpace(
            pageHandwrittenChordCoordinateSpace,
            for: self.pageHandwrittenChordData
        )
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
        case hasExplicitClefSelection
        case hasCompletedInitialSetup
        case systems
        case keyChanges
        case keyChangeSystemBreakMeasureIDs
        case timeSignatureChanges
        case sectionLabels
        case cueTexts
        case roadmapObjects
        case freehandSymbols
        case stylePreset
        case engravingPreset
        case pageHandwrittenNotationData
        case pageHandwrittenNotationCoordinateSpace
        case pageHandwrittenHeaderData
        case pageHandwrittenHeaderCoordinateSpace
        case pageHandwrittenChordData
        case pageHandwrittenChordCoordinateSpace
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
        defaultClef = try container.decodeIfPresent(ChartClef.self, forKey: .defaultClef)
            ?? (layoutStyle == .rhythmSectionSheet ? .bass : .treble)
        hasExplicitClefSelection = try container.decodeIfPresent(Bool.self, forKey: .hasExplicitClefSelection) ?? false
        hasCompletedInitialSetup = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedInitialSetup) ?? true
        let decodedSystems = try container.decode([ChartSystem].self, forKey: .systems)
        systems = Self.systemsApplyingChordTransposition(
            to: decodedSystems,
            by: decodedChordTranspositionSemitones
        )
        keyChanges = try container.decodeIfPresent([KeyChange].self, forKey: .keyChanges) ?? []
        keyChangeSystemBreakMeasureIDs = try container.decodeIfPresent(
            Set<UUID>.self,
            forKey: .keyChangeSystemBreakMeasureIDs
        ) ?? []
        timeSignatureChanges = try container.decodeIfPresent([TimeSignatureChange].self, forKey: .timeSignatureChanges) ?? []
        sectionLabels = try container.decode([SectionLabel].self, forKey: .sectionLabels)
        cueTexts = try container.decode([CueText].self, forKey: .cueTexts)
        roadmapObjects = try container.decode([RoadmapObject].self, forKey: .roadmapObjects)
        _ = try container.decodeIfPresent([FreehandSymbol].self, forKey: .freehandSymbols)
        freehandSymbols = []
        stylePreset = try container.decode(StylePreset.self, forKey: .stylePreset)
        engravingPreset = try container.decodeIfPresent(EngravingPreset.self, forKey: .engravingPreset) ?? .balanced
        pageHandwrittenNotationData = normalizedPersistentInkDrawingData(
            try container.decodeIfPresent(Data.self, forKey: .pageHandwrittenNotationData)
        )
        pageHandwrittenNotationCoordinateSpace = Self.coordinateSpace(
            try container.decodeIfPresent(PersistentInkCoordinateSpace.self, forKey: .pageHandwrittenNotationCoordinateSpace),
            for: pageHandwrittenNotationData
        )
        pageHandwrittenHeaderData = normalizedPersistentInkDrawingData(
            try container.decodeIfPresent(Data.self, forKey: .pageHandwrittenHeaderData)
        )
        pageHandwrittenHeaderCoordinateSpace = Self.coordinateSpace(
            try container.decodeIfPresent(PersistentInkCoordinateSpace.self, forKey: .pageHandwrittenHeaderCoordinateSpace),
            for: pageHandwrittenHeaderData
        )
        pageHandwrittenChordData = normalizedPersistentInkDrawingData(
            try container.decodeIfPresent(Data.self, forKey: .pageHandwrittenChordData)
        )
        pageHandwrittenChordCoordinateSpace = Self.coordinateSpace(
            try container.decodeIfPresent(PersistentInkCoordinateSpace.self, forKey: .pageHandwrittenChordCoordinateSpace),
            for: pageHandwrittenChordData
        )
        cloudBackupStatus = try container.decodeIfPresent(ChartCloudBackupStatus.self, forKey: .cloudBackupStatus)
            ?? .legacyLocal
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    private static func coordinateSpace(
        _ coordinateSpace: PersistentInkCoordinateSpace?,
        for drawingData: Data?
    ) -> PersistentInkCoordinateSpace? {
        drawingData == nil ? nil : coordinateSpace
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
    var startsNewPage: Bool
    var measures: [Measure]

    init(
        id: UUID,
        index: Int,
        spacingMode: SpacingMode,
        lineBreakRule: LineBreakRule,
        startsNewPage: Bool = false,
        measures: [Measure]
    ) {
        self.id = id
        self.index = index
        self.spacingMode = spacingMode
        self.lineBreakRule = lineBreakRule
        self.startsNewPage = startsNewPage
        self.measures = measures
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case index
        case spacingMode
        case lineBreakRule
        case startsNewPage
        case measures
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        index = try container.decode(Int.self, forKey: .index)
        spacingMode = try container.decode(SpacingMode.self, forKey: .spacingMode)
        lineBreakRule = try container.decode(LineBreakRule.self, forKey: .lineBreakRule)
        startsNewPage = try container.decodeIfPresent(Bool.self, forKey: .startsNewPage) ?? false
        measures = try container.decode([Measure].self, forKey: .measures)
    }
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

    var pitch: ChordPitch {
        ChordPitch(root: tonic, accidental: accidental)
    }

    var displayText: String {
        "\(tonic.rawValue)\(accidental.rawValue) \(mode.displayText)"
    }

    var titleDisplayText: String {
        let modeText = mode.displayText
        let titleModeText = modeText.prefix(1).uppercased() + String(modeText.dropFirst())
        return "\(tonic.rawValue)\(accidental.rawValue) \(titleModeText)"
    }

    var compactDisplayText: String {
        "\(tonic.rawValue)\(accidental.rawValue) \(mode.shortDisplayText)"
    }

    var keySignature: KeySignature? {
        Self.keySignatureByKey[self]
    }

    var spellingPreference: PitchSpellingPreference {
        keySignature?.spellingPreference ?? PitchSpellingPreference.forAccidental(accidental)
    }

    func transposed(for view: TranspositionView) -> DocumentKey {
        transposed(by: view.semitoneOffsetFromConcert)
    }

    func transposed(by semitones: Int) -> DocumentKey {
        let normalizedSemitones = normalizedSemitone(semitones)
        guard normalizedSemitones != 0 else { return self }

        if let standardKey = Self.standardKey(
            matchingSemitone: normalizedSemitone(pitch.semitone + normalizedSemitones),
            mode: mode,
            preference: spellingPreference
        ) {
            return standardKey
        }

        let transposedPitch = pitch
            .transposed(by: normalizedSemitones)
            .spelled(using: spellingPreference)

        return DocumentKey(
            tonic: transposedPitch.root,
            accidental: transposedPitch.accidental,
            mode: mode
        )
    }

    func semitoneDelta(to key: DocumentKey) -> Int {
        normalizedSemitone(key.pitch.semitone - pitch.semitone)
    }

    func concertKey(for view: TranspositionView) -> DocumentKey {
        guard view.semitoneOffsetFromConcert != 0 else { return self }

        if let exactKey = Self.standardKeys(for: mode).first(where: { $0.transposed(for: view) == self }) {
            return exactKey
        }

        let semitone = normalizedSemitone(pitch.semitone - view.semitoneOffsetFromConcert)
        if let standardKey = Self.standardKey(
            matchingSemitone: semitone,
            mode: mode,
            preference: spellingPreference
        ) {
            return standardKey
        }

        let concertPitch = ChordPitch.from(semitone: semitone, preference: spellingPreference)
        return DocumentKey(
            tonic: concertPitch.root,
            accidental: concertPitch.accidental,
            mode: mode
        )
    }

    private static func standardKey(
        matchingSemitone semitone: Int,
        mode: KeyMode,
        preference: PitchSpellingPreference
    ) -> DocumentKey? {
        let candidates = standardKeys(for: mode)
        guard !candidates.isEmpty else { return nil }

        let matchingKeys = candidates.filter { $0.pitch.semitone == semitone }
        if let preferredKey = matchingKeys.first(where: { $0.spellingPreference == preference }) {
            return preferredKey
        }

        return matchingKeys.min {
            ($0.keySignature?.count ?? 0) < ($1.keySignature?.count ?? 0)
        }
    }

    private static func standardKeys(for mode: KeyMode) -> [DocumentKey] {
        switch mode {
        case .major:
            return standardMajorKeys
        case .minor:
            return standardMinorKeys
        case .modal:
            return []
        }
    }

    private func normalizedSemitone(_ semitone: Int) -> Int {
        let modulo = semitone % 12
        return modulo >= 0 ? modulo : modulo + 12
    }
}

enum KeySignatureAccidentalKind: String, Codable, Hashable {
    case sharps
    case flats
}

struct KeySignature: Codable, Hashable {
    var kind: KeySignatureAccidentalKind
    var count: Int

    var spellingPreference: PitchSpellingPreference {
        kind == .sharps ? .sharps : .flats
    }
}

struct KeyChange: Identifiable, Codable, Hashable {
    var id: UUID
    var measureID: UUID
    var key: DocumentKey

    init(
        id: UUID = UUID(),
        measureID: UUID,
        key: DocumentKey
    ) {
        self.id = id
        self.measureID = measureID
        self.key = key
    }
}

extension DocumentKey: Identifiable {
    var id: String {
        "\(tonic.rawValue)\(accidental.rawValue)-\(mode.rawValue)"
    }

    static let cMajor = DocumentKey(tonic: .c, accidental: .natural, mode: .major)
    static let gMajor = DocumentKey(tonic: .g, accidental: .natural, mode: .major)
    static let dMajor = DocumentKey(tonic: .d, accidental: .natural, mode: .major)
    static let aMajor = DocumentKey(tonic: .a, accidental: .natural, mode: .major)
    static let eMajor = DocumentKey(tonic: .e, accidental: .natural, mode: .major)
    static let bMajor = DocumentKey(tonic: .b, accidental: .natural, mode: .major)
    static let fSharpMajor = DocumentKey(tonic: .f, accidental: .sharp, mode: .major)
    static let cSharpMajor = DocumentKey(tonic: .c, accidental: .sharp, mode: .major)
    static let fMajor = DocumentKey(tonic: .f, accidental: .natural, mode: .major)
    static let bFlatMajor = DocumentKey(tonic: .b, accidental: .flat, mode: .major)
    static let eFlatMajor = DocumentKey(tonic: .e, accidental: .flat, mode: .major)
    static let aFlatMajor = DocumentKey(tonic: .a, accidental: .flat, mode: .major)
    static let dFlatMajor = DocumentKey(tonic: .d, accidental: .flat, mode: .major)
    static let gFlatMajor = DocumentKey(tonic: .g, accidental: .flat, mode: .major)
    static let cFlatMajor = DocumentKey(tonic: .c, accidental: .flat, mode: .major)

    static let aMinor = DocumentKey(tonic: .a, accidental: .natural, mode: .minor)
    static let eMinor = DocumentKey(tonic: .e, accidental: .natural, mode: .minor)
    static let bMinor = DocumentKey(tonic: .b, accidental: .natural, mode: .minor)
    static let fSharpMinor = DocumentKey(tonic: .f, accidental: .sharp, mode: .minor)
    static let cSharpMinor = DocumentKey(tonic: .c, accidental: .sharp, mode: .minor)
    static let gSharpMinor = DocumentKey(tonic: .g, accidental: .sharp, mode: .minor)
    static let dSharpMinor = DocumentKey(tonic: .d, accidental: .sharp, mode: .minor)
    static let aSharpMinor = DocumentKey(tonic: .a, accidental: .sharp, mode: .minor)
    static let dMinor = DocumentKey(tonic: .d, accidental: .natural, mode: .minor)
    static let gMinor = DocumentKey(tonic: .g, accidental: .natural, mode: .minor)
    static let cMinor = DocumentKey(tonic: .c, accidental: .natural, mode: .minor)
    static let fMinor = DocumentKey(tonic: .f, accidental: .natural, mode: .minor)
    static let bFlatMinor = DocumentKey(tonic: .b, accidental: .flat, mode: .minor)
    static let eFlatMinor = DocumentKey(tonic: .e, accidental: .flat, mode: .minor)
    static let aFlatMinor = DocumentKey(tonic: .a, accidental: .flat, mode: .minor)

    static let standardMajorKeys: [DocumentKey] = [
        .cFlatMajor,
        .gFlatMajor,
        .dFlatMajor,
        .aFlatMajor,
        .eFlatMajor,
        .bFlatMajor,
        .fMajor,
        .cMajor,
        .gMajor,
        .dMajor,
        .aMajor,
        .eMajor,
        .bMajor,
        .fSharpMajor,
        .cSharpMajor
    ]

    static let standardMinorKeys: [DocumentKey] = [
        .aFlatMinor,
        .eFlatMinor,
        .bFlatMinor,
        .fMinor,
        .cMinor,
        .gMinor,
        .dMinor,
        .aMinor,
        .eMinor,
        .bMinor,
        .fSharpMinor,
        .cSharpMinor,
        .gSharpMinor,
        .dSharpMinor,
        .aSharpMinor
    ]

    static let allStandardKeys: [DocumentKey] = standardMajorKeys + standardMinorKeys

    static let commonCreationKeys: [DocumentKey] = [
        .cMajor,
        .fMajor,
        .bFlatMajor,
        .eFlatMajor,
        .gMajor
    ]

    private static let keySignatureByKey: [DocumentKey: KeySignature] = [
        .gMajor: KeySignature(kind: .sharps, count: 1),
        .dMajor: KeySignature(kind: .sharps, count: 2),
        .aMajor: KeySignature(kind: .sharps, count: 3),
        .eMajor: KeySignature(kind: .sharps, count: 4),
        .bMajor: KeySignature(kind: .sharps, count: 5),
        .fSharpMajor: KeySignature(kind: .sharps, count: 6),
        .cSharpMajor: KeySignature(kind: .sharps, count: 7),
        .eMinor: KeySignature(kind: .sharps, count: 1),
        .bMinor: KeySignature(kind: .sharps, count: 2),
        .fSharpMinor: KeySignature(kind: .sharps, count: 3),
        .cSharpMinor: KeySignature(kind: .sharps, count: 4),
        .gSharpMinor: KeySignature(kind: .sharps, count: 5),
        .dSharpMinor: KeySignature(kind: .sharps, count: 6),
        .aSharpMinor: KeySignature(kind: .sharps, count: 7),
        .fMajor: KeySignature(kind: .flats, count: 1),
        .bFlatMajor: KeySignature(kind: .flats, count: 2),
        .eFlatMajor: KeySignature(kind: .flats, count: 3),
        .aFlatMajor: KeySignature(kind: .flats, count: 4),
        .dFlatMajor: KeySignature(kind: .flats, count: 5),
        .gFlatMajor: KeySignature(kind: .flats, count: 6),
        .cFlatMajor: KeySignature(kind: .flats, count: 7),
        .dMinor: KeySignature(kind: .flats, count: 1),
        .gMinor: KeySignature(kind: .flats, count: 2),
        .cMinor: KeySignature(kind: .flats, count: 3),
        .fMinor: KeySignature(kind: .flats, count: 4),
        .bFlatMinor: KeySignature(kind: .flats, count: 5),
        .eFlatMinor: KeySignature(kind: .flats, count: 6),
        .aFlatMinor: KeySignature(kind: .flats, count: 7)
    ]
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

    var shortDisplayText: String {
        switch self {
        case .major:
            return "maj"
        case .minor:
            return "min"
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
    var displayedDocumentKey: DocumentKey {
        documentKey.transposed(for: defaultTranspositionView)
    }

    func displayedEffectiveKey(for measure: Measure) -> DocumentKey {
        displayedEffectiveKey(forMeasureID: measure.id)
    }

    func displayedEffectiveKey(forMeasureID measureID: UUID) -> DocumentKey {
        effectiveKey(forMeasureID: measureID).transposed(for: defaultTranspositionView)
    }

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
        displayedChordSymbol(for: chordEvent, in: nil)
    }

    func displayedChordSymbol(for chordEvent: ChordEvent, in measureID: UUID?) -> ChordSymbol {
        let activeKey = measureID.map { displayedEffectiveKey(forMeasureID: $0) } ?? displayedDocumentKey
        let transposedSymbol = chordEvent
            .transposed(for: defaultTranspositionView)
            .symbol
            .transposedForChartDisplay(by: chordTranspositionSemitones)

        guard chordEvent.spellingIntent == .automatic else {
            return transposedSymbol
        }

        guard let keySignature = activeKey.keySignature else {
            return transposedSymbol
        }

        return transposedSymbol.spelledForChartDisplay(using: keySignature.spellingPreference)
    }

    func enharmonicChordSpellingTexts(for chordEvent: ChordEvent, in measureID: UUID?) -> [String] {
        displayedChordSymbol(for: chordEvent, in: measureID).enharmonicDisplayTexts()
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
