#if canImport(PencilKit) && canImport(UIKit)
import Foundation
import PencilKit
import SwiftUI
import UIKit

struct RecognitionStudyCapturePrompt: Equatable, Identifiable, Sendable {
    let id: String
    /// Strict canonical notation persisted in study artifacts. This must stay
    /// in the same ASCII-accidental language consumed by `ChordNotation`.
    let chordText: String
    /// Human-facing notation may use typographic accidental glyphs without
    /// weakening or changing the persisted canonical label.
    let displayChordText: String
    let chartStyle: RecognitionStudyPresentedChartStyle
    let pace: RecognitionStudyPresentedPaceInstruction
    let size: RecognitionStudyPresentedSizeInstruction
    let construction: RecognitionStudyPresentedConstructionInstruction

    init(
        id: String,
        chordText: String,
        displayChordText: String? = nil,
        chartStyle: RecognitionStudyPresentedChartStyle,
        pace: RecognitionStudyPresentedPaceInstruction,
        size: RecognitionStudyPresentedSizeInstruction,
        construction: RecognitionStudyPresentedConstructionInstruction
    ) {
        self.id = id
        self.chordText = chordText
        self.displayChordText = displayChordText ?? chordText
        self.chartStyle = chartStyle
        self.pace = pace
        self.size = size
        self.construction = construction
    }

    var instructionText: String {
        let paceText: String
        switch pace {
        case .natural:
            paceText = "at your natural speed"
        case .fast:
            paceText = "quickly, as if you were charting live"
        case .careful:
            paceText = "carefully"
        }

        let sizeText: String
        switch size {
        case .small:
            sizeText = "small"
        case .normal:
            sizeText = "at your normal size"
        case .large:
            sizeText = "large"
        }

        let constructionText: String
        switch construction {
        case .rootFirst:
            constructionText = "Start with the root."
        case .modifierFirst:
            constructionText = "Start with the modifier."
        case .mixedOrRetraced:
            constructionText = "Use your natural stroke order; retracing is okay."
        }

        return "Write it \(paceText), \(sizeText). \(constructionText)"
    }

    static let engineeringDryRun: [Self] = [
        Self(
            id: "c-natural-normal-root",
            chordText: "C",
            chartStyle: .simpleChordSheet,
            pace: .natural,
            size: .normal,
            construction: .rootFirst
        ),
        Self(
            id: "b-natural-normal-root",
            chordText: "B",
            chartStyle: .rhythmSectionSheet,
            pace: .natural,
            size: .normal,
            construction: .rootFirst
        ),
        Self(
            id: "g-fast-normal-root",
            chordText: "G7",
            chartStyle: .simpleChordSheet,
            pace: .fast,
            size: .normal,
            construction: .rootFirst
        ),
        Self(
            id: "bb-natural-small-root",
            chordText: "Bb",
            displayChordText: "B♭",
            chartStyle: .rhythmSectionSheet,
            pace: .natural,
            size: .small,
            construction: .rootFirst
        ),
        Self(
            id: "b-major-seven-careful-large-mixed",
            chordText: "B△7",
            chartStyle: .simpleChordSheet,
            pace: .careful,
            size: .large,
            construction: .mixedOrRetraced
        ),
        Self(
            id: "c-minor-seven-fast-normal-modifier",
            chordText: "C-7",
            chartStyle: .rhythmSectionSheet,
            pace: .fast,
            size: .normal,
            construction: .modifierFirst
        ),
        Self(
            id: "d-half-diminished-natural-normal-mixed",
            chordText: "Dø7",
            chartStyle: .simpleChordSheet,
            pace: .natural,
            size: .normal,
            construction: .mixedOrRetraced
        ),
        Self(
            id: "g-altered-natural-normal-root",
            chordText: "G7(b9)",
            chartStyle: .rhythmSectionSheet,
            pace: .natural,
            size: .normal,
            construction: .rootFirst
        ),
        Self(
            id: "c-over-e-fast-small-root",
            chordText: "C/E",
            chartStyle: .simpleChordSheet,
            pace: .fast,
            size: .small,
            construction: .rootFirst
        ),
        Self(
            id: "db-major-nine-careful-large-modifier",
            chordText: "Db△9",
            displayChordText: "D♭△9",
            chartStyle: .rhythmSectionSheet,
            pace: .careful,
            size: .large,
            construction: .modifierFirst
        )
    ]
}

enum RecognitionStudyLocalResult: Equatable, Sendable {
    case accepted(displayText: String, detail: String)
    case review(candidate: String?, detail: String)
    case noRead(detail: String)

    var title: String {
        switch self {
        case .accepted:
            return "Accepted"
        case .review:
            return "Needs review"
        case .noRead:
            return "No read"
        }
    }

    var displayText: String? {
        switch self {
        case let .accepted(displayText, _):
            return displayText
        case let .review(candidate, _):
            return candidate
        case .noRead:
            return nil
        }
    }

    var detail: String {
        switch self {
        case let .accepted(_, detail),
             let .review(_, detail),
             let .noRead(detail):
            return detail
        }
    }
}

struct RecognitionStudyPassSummary: Equatable, Sendable {
    let totalCount: Int
    let eligibleComparisonCount: Int
    let exactCanonicalCandidateCount: Int
    let differentOrInvalidCandidateCount: Int
    let noCandidateCount: Int
    let writerMatchedPromptCount: Int
    let executionErrorCount: Int
    let humanAmbiguousCount: Int
    let technicalFailureCount: Int

    init(outcomes: [RecognitionStudySemanticOutcomeArtifact]) {
        totalCount = outcomes.count
        let comparableOutcomes = outcomes.filter {
            $0.promptOutcome.writerConfirmationState == .asPrompted
        }
        eligibleComparisonCount = comparableOutcomes.count
        exactCanonicalCandidateCount = comparableOutcomes.reduce(into: 0) { count, outcome in
            if outcome.baseRecognizerOutcome.canonicalCandidate?.rawValue
                == outcome.promptOutcome.intendedChord.rawValue {
                count += 1
            }
        }
        differentOrInvalidCandidateCount = comparableOutcomes.reduce(into: 0) { count, outcome in
            guard outcome.baseRecognizerOutcome.candidate != nil else {
                return
            }
            if outcome.baseRecognizerOutcome.canonicalCandidate?.rawValue
                != outcome.promptOutcome.intendedChord.rawValue {
                count += 1
            }
        }
        noCandidateCount = comparableOutcomes.reduce(into: 0) { count, outcome in
            if outcome.baseRecognizerOutcome.candidate == nil {
                count += 1
            }
        }
        writerMatchedPromptCount = outcomes.reduce(into: 0) { count, outcome in
            if outcome.promptOutcome.writerConfirmationState == .asPrompted {
                count += 1
            }
        }
        executionErrorCount = outcomes.reduce(into: 0) { count, outcome in
            if outcome.promptOutcome.writerConfirmationState == .executionError {
                count += 1
            }
        }
        humanAmbiguousCount = outcomes.reduce(into: 0) { count, outcome in
            if outcome.promptOutcome.writerConfirmationState == .humanAmbiguous {
                count += 1
            }
        }
        technicalFailureCount = outcomes.reduce(into: 0) { count, outcome in
            if outcome.promptOutcome.writerConfirmationState == .technicalFailure {
                count += 1
            }
        }
    }
}

struct RecognitionStudyReviewPreview: Equatable {
    let strokes: [InkStroke]
    let sourceCanvasSize: CGSize
}

/// A study-only seam for a candidate recognizer. Implementations must stay
/// local to the isolated target; the default implementation intentionally does
/// not call the production recognizer or any service. The prompted chord is
/// intentionally absent from this API so a candidate cannot receive the answer
/// it is being evaluated against.
protocol RecognitionStudyLocalResultProviding: Sendable {
    var recognizerID: String { get }
    var recognizerVersion: String { get }

    func result(
        for packet: ChordInkCanonicalTrajectoryPacket
    ) async -> RecognitionStudyLocalResult
}

extension RecognitionStudyLocalResultProviding {
    var recognizerID: String { "study-local-provider" }
    var recognizerVersion: String { "study-local-provider-v1" }
}

struct RecognitionStudyCaptureOnlyResultProvider:
    RecognitionStudyLocalResultProviding
{
    func result(
        for packet: ChordInkCanonicalTrajectoryPacket
    ) async -> RecognitionStudyLocalResult {
        .review(
            candidate: nil,
            detail: "Saved locally. No candidate recognizer is connected to this build."
        )
    }
}

struct RecognitionStudySessionReferenceStore {
    private static let currentSessionKey =
        "recognition-study.current-engineering-session-v1"

    let defaults: UserDefaults
    let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = Self.currentSessionKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> UUID? {
        guard let rawValue = defaults.string(forKey: key),
              let identifier = UUID(uuidString: rawValue),
              identifier.uuidString.lowercased() == rawValue else {
            return nil
        }
        return identifier
    }

    func save(_ identifier: UUID) {
        defaults.set(identifier.uuidString.lowercased(), forKey: key)
    }
}

@MainActor
final class RecognitionStudyCaptureViewModel: ObservableObject {
    enum Phase: Equatable {
        case preparing
        case ready
        case submitting
        case reviewing
        case recordingOutcome
        case completed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .preparing
    @Published private(set) var promptIndex = 0
    @Published private(set) var result: RecognitionStudyLocalResult?
    @Published private(set) var completedSummary: RecognitionStudyPassSummary?
    @Published private(set) var reviewPreview: RecognitionStudyReviewPreview?
    @Published private(set) var requiresInterruptedCaptureExclusion = false

    let prompts: [RecognitionStudyCapturePrompt]

    private let resultProvider: any RecognitionStudyLocalResultProviding
    private let rootDirectoryProvider: @Sendable () throws -> URL
    private let sessionReferenceStore: RecognitionStudySessionReferenceStore
    private var store: RecognitionStudyLocalCaptureStore?
    private var outcomeStore: RecognitionStudyLocalOutcomeStore?
    private var localSessionID: UUID?
    private var pendingCapture: RecognitionStudyStoredCapture?
    private var pendingBaseRecognizerOutcome:
        RecognitionStudyBaseRecognizerOutcome?
    private var hasStarted = false

    init(
        prompts: [RecognitionStudyCapturePrompt] =
            RecognitionStudyCapturePrompt.engineeringDryRun,
        resultProvider: any RecognitionStudyLocalResultProviding =
            RecognitionStudyCaptureOnlyResultProvider(),
        sessionReferenceStore: RecognitionStudySessionReferenceStore = .init(),
        rootDirectoryProvider: @escaping @Sendable () throws -> URL = {
            try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("RecognitionStudy", isDirectory: true)
        }
    ) {
        precondition(!prompts.isEmpty)
        self.prompts = prompts
        self.resultProvider = resultProvider
        self.sessionReferenceStore = sessionReferenceStore
        self.rootDirectoryProvider = rootDirectoryProvider
    }

    var currentPrompt: RecognitionStudyCapturePrompt? {
        prompts.indices.contains(promptIndex) ? prompts[promptIndex] : nil
    }

    var progressText: String {
        if phase == .completed {
            return "Complete · \(prompts.count) of \(prompts.count)"
        }
        return "Chord \(min(promptIndex + 1, prompts.count)) of \(prompts.count)"
    }

    var isReadyToSubmit: Bool {
        phase == .ready && currentPrompt != nil
    }

    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        phase = .preparing

        do {
            let rootDirectory = try rootDirectoryProvider()
            let store = try await RecognitionStudyLocalCaptureStore.open(
                rootDirectory: rootDirectory
            )
            let outcomeStore = try await RecognitionStudyLocalOutcomeStore.open(
                rootDirectory: rootDirectory
            )
            if let savedSessionID = sessionReferenceStore.load(),
               try await store.sessionManifest(
                   localSessionID: savedSessionID
               ) != nil {
                let captures = try await store.committedCaptures(
                    localSessionID: savedSessionID
                )
                let ordinals = captures.map {
                    Int($0.envelope.captureOrdinal)
                }
                guard captures.count <= prompts.count,
                      ordinals == Array(0..<captures.count) else {
                    throw RecognitionStudyLocalCaptureStoreError
                        .corruptArtifact("noncontiguous engineering pass")
                }
                let outcomes = try await outcomeStore.outcomes(
                    localSessionID: savedSessionID
                )
                let outcomesByAuthorizationID = Dictionary(
                    uniqueKeysWithValues: outcomes.map {
                        ($0.authorizationID.rawValue, $0)
                    }
                )
                let captureAuthorizationIDs = Set(captures.map {
                    $0.envelope.authorizationBinding.authorizationID.rawValue
                })
                guard outcomesByAuthorizationID.count == outcomes.count,
                      outcomes.count <= captures.count,
                      Set(outcomesByAuthorizationID.keys).isSubset(
                        of: captureAuthorizationIDs
                      ) else {
                    throw RecognitionStudyLocalCaptureStoreError
                        .corruptArtifact("invalid engineering outcomes")
                }
                var unresolvedCaptures = [RecognitionStudyStoredCapture]()
                for (index, capture) in captures.enumerated() {
                    let authorizationID = capture.envelope
                        .authorizationBinding.authorizationID.rawValue
                    guard let outcome = outcomesByAuthorizationID[
                        authorizationID
                    ] else {
                        unresolvedCaptures.append(capture)
                        continue
                    }
                    try outcome.validateBindings(
                        packet: capture.packet,
                        envelope: capture.envelope
                    )
                    guard outcome.localCaptureID
                            == capture.envelope.localCaptureID,
                          outcome.promptOutcome.promptID.rawValue
                            == prompts[index].id,
                          outcome.promptOutcome.intendedChord.rawValue
                            == prompts[index].chordText else {
                        throw RecognitionStudyLocalCaptureStoreError
                            .corruptArtifact("engineering outcome mismatch")
                    }
                }
                guard unresolvedCaptures.count <= 1,
                      unresolvedCaptures.first == captures.last
                            || unresolvedCaptures.isEmpty else {
                    throw RecognitionStudyLocalCaptureStoreError
                        .corruptArtifact("noncontiguous engineering outcomes")
                }
                self.store = store
                self.outcomeStore = outcomeStore
                localSessionID = savedSessionID
                if let pendingCapture = unresolvedCaptures.first {
                    promptIndex = Int(
                        pendingCapture.envelope.captureOrdinal
                    )
                    self.pendingCapture = pendingCapture
                    pendingBaseRecognizerOutcome = try RecognitionStudyBaseRecognizerOutcome(
                        recognizerID: resultProvider.recognizerID,
                        recognizerVersion: resultProvider.recognizerVersion,
                        disposition: .notRun,
                        candidate: nil
                    )
                    reviewPreview = RecognitionStudyReviewPreview(
                        strokes: pendingCapture.packet.preparedStrokes(),
                        sourceCanvasSize: CGSize(
                            width: pendingCapture.envelope.presentedSurface
                                .canvasWidth.value,
                            height: pendingCapture.envelope.presentedSurface
                                .canvasHeight.value
                        )
                    )
                    requiresInterruptedCaptureExclusion = true
                    result = .review(
                        candidate: nil,
                        detail: "This capture was interrupted before its exact recognizer result was stored. The saved ink is restored below, but the sample must be excluded and rewritten in a new pass."
                    )
                    phase = .reviewing
                } else {
                    promptIndex = captures.count
                    if captures.count == prompts.count {
                        completedSummary = RecognitionStudyPassSummary(
                            outcomes: outcomes
                        )
                        phase = .completed
                    } else {
                        phase = .ready
                    }
                }
                return
            }

            let sessionID = UUID()
            let context = try Self.clientAppContext()
            let manifest = try RecognitionStudySessionManifest(
                localSessionID: sessionID,
                clientCreatedAtUnixMilliseconds: Self.unixMilliseconds(),
                clientAppContext: context
            )
            _ = try await store.createSession(manifest)
            sessionReferenceStore.save(sessionID)
            self.store = store
            self.outcomeStore = outcomeStore
            localSessionID = sessionID
            phase = .ready
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    @discardableResult
    func submit(
        drawing: PKDrawing,
        canvasSize: CGSize,
        clientObservedOrientation: RecognitionStudyObservedOrientation
    ) async -> Bool {
        guard phase == .ready,
              let prompt = currentPrompt,
              let store,
              let localSessionID else {
            return false
        }

        let preparedStrokes = PencilKitInkAdapter.inkStrokes(from: drawing)
        guard preparedStrokes.contains(where: { !$0.points.isEmpty }) else {
            result = .noRead(detail: "Write one chord before submitting.")
            return false
        }

        phase = .submitting
        result = nil
        reviewPreview = nil
        requiresInterruptedCaptureExclusion = false
        do {
            let packet = try ChordInkCanonicalTrajectoryPacket(
                strokes: preparedStrokes
            )
            let surface = try RecognitionStudyPresentedSurface(
                presentedChartStyle: prompt.chartStyle,
                clientObservedOrientation: clientObservedOrientation,
                canvasWidth: Double(canvasSize.width),
                canvasHeight: Double(canvasSize.height),
                presentedPaceInstruction: prompt.pace,
                presentedSizeInstruction: prompt.size,
                presentedConstructionInstruction: prompt.construction
            )
            let storedCapture = try await store.storeCapture(
                localSessionID: localSessionID,
                authorizationID: UUID(),
                localCaptureID: UUID(),
                captureOrdinal: UInt32(promptIndex),
                clientCapturedAtUnixMilliseconds: Self.unixMilliseconds(),
                presentedSurface: surface,
                packet: packet
            )
            let localResult = await resultProvider.result(
                for: packet
            )
            pendingCapture = storedCapture
            pendingBaseRecognizerOutcome = try baseOutcome(for: localResult)
            result = localResult

            phase = .reviewing
            return true
        } catch {
            phase = .failed(Self.message(for: error))
            return false
        }
    }

    func retryPreparation() async {
        guard case .failed = phase else {
            return
        }
        hasStarted = false
        store = nil
        outcomeStore = nil
        localSessionID = nil
        pendingCapture = nil
        pendingBaseRecognizerOutcome = nil
        result = nil
        completedSummary = nil
        reviewPreview = nil
        requiresInterruptedCaptureExclusion = false
        await start()
    }

    @discardableResult
    func recordOutcomeAndAdvance(
        _ writerConfirmationState: RecognitionStudyWriterConfirmationState
    ) async -> Bool {
        guard phase == .reviewing,
              let prompt = currentPrompt,
              let pendingCapture,
              let pendingBaseRecognizerOutcome,
              let outcomeStore else {
            return false
        }
        guard requiresInterruptedCaptureExclusion
                ? writerConfirmationState == .technicalFailure
                : writerConfirmationState != .technicalFailure else {
            return false
        }

        phase = .recordingOutcome
        do {
            _ = try await outcomeStore.storeOutcome(
                packet: pendingCapture.packet,
                envelope: pendingCapture.envelope,
                promptID: prompt.id,
                intendedChord: prompt.chordText,
                writerConfirmationState: writerConfirmationState,
                baseRecognizerOutcome: pendingBaseRecognizerOutcome,
                clientRecordedAtUnixMilliseconds: Self.unixMilliseconds()
            )
            self.pendingCapture = nil
            self.pendingBaseRecognizerOutcome = nil
            result = nil
            reviewPreview = nil
            requiresInterruptedCaptureExclusion = false
            promptIndex += 1
            if promptIndex == prompts.count, let localSessionID {
                completedSummary = RecognitionStudyPassSummary(
                    outcomes: try await outcomeStore.outcomes(
                        localSessionID: localSessionID
                    )
                )
                phase = .completed
            } else {
                phase = .ready
            }
            return true
        } catch {
            phase = .failed(Self.message(for: error))
            return false
        }
    }

    @discardableResult
    func beginNewPass() async -> Bool {
        guard phase == .completed, let store else {
            return false
        }

        phase = .preparing
        result = nil
        pendingCapture = nil
        pendingBaseRecognizerOutcome = nil
        completedSummary = nil
        reviewPreview = nil
        requiresInterruptedCaptureExclusion = false
        do {
            let sessionID = UUID()
            let manifest = try RecognitionStudySessionManifest(
                localSessionID: sessionID,
                clientCreatedAtUnixMilliseconds: Self.unixMilliseconds(),
                clientAppContext: try Self.clientAppContext()
            )
            _ = try await store.createSession(manifest)
            sessionReferenceStore.save(sessionID)
            localSessionID = sessionID
            promptIndex = 0
            phase = .ready
            return true
        } catch {
            phase = .failed(Self.message(for: error))
            return false
        }
    }

    private static func clientAppContext() throws -> RecognitionStudyClientAppContext {
        let dictionary = Bundle.main.infoDictionary ?? [:]
        let appVersion = dictionary["CFBundleShortVersionString"] as? String
            ?? "0"
        let buildNumber = dictionary["CFBundleVersion"] as? String
            ?? "0"
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersion
        return try RecognitionStudyClientAppContext(
            appVersion: appVersion,
            buildNumber: buildNumber,
            operatingSystemMajorVersion: UInt16(
                clamping: operatingSystem.majorVersion
            ),
            operatingSystemMinorVersion: UInt16(
                clamping: operatingSystem.minorVersion
            )
        )
    }

    private static func unixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }

    private static func message(for error: Error) -> String {
        if error as? RecognitionStudyLocalCaptureStoreError
                == .protectedDataUnavailable
            || error as? RecognitionStudyLocalOutcomeStoreError
                == .protectedDataUnavailable {
            return "Unlock this iPad, then try again."
        }
        return "The local study store could not save this step. Try again before continuing."
    }

    private func baseOutcome(
        for result: RecognitionStudyLocalResult
    ) throws -> RecognitionStudyBaseRecognizerOutcome {
        let disposition: RecognitionStudyBaseDisposition
        let candidate: String?
        switch result {
        case let .accepted(displayText, _):
            disposition = .accepted
            candidate = displayText
        case let .review(displayText, _):
            disposition = .review
            candidate = displayText
        case .noRead:
            disposition = .noRead
            candidate = nil
        }
        return try RecognitionStudyBaseRecognizerOutcome(
            recognizerID: resultProvider.recognizerID,
            recognizerVersion: resultProvider.recognizerVersion,
            disposition: disposition,
            candidate: candidate
        )
    }

    static func observedOrientation(
        viewportSize: CGSize
    ) -> RecognitionStudyObservedOrientation {
        viewportSize.width > viewportSize.height ? .landscape : .portrait
    }
}

struct RecognitionStudyCaptureView: View {
    @StateObject private var model: RecognitionStudyCaptureViewModel
    @State private var drawing = PKDrawing()
    @State private var canvasCommand: RecognitionStudyCanvasCommand?
    @State private var canUndo = false
    @State private var canvasSize = CGSize(width: 1, height: 1)
    @State private var viewportSize = CGSize(width: 1, height: 1)

    init(
        prompts: [RecognitionStudyCapturePrompt] =
            RecognitionStudyCapturePrompt.engineeringDryRun,
        resultProvider: any RecognitionStudyLocalResultProviding =
            RecognitionStudyCaptureOnlyResultProvider()
    ) {
        _model = StateObject(
            wrappedValue: RecognitionStudyCaptureViewModel(
                prompts: prompts,
                resultProvider: resultProvider
            )
        )
    }

    var body: some View {
        GeometryReader { viewport in
            NavigationStack {
                VStack(spacing: 16) {
                    disclosure
                    promptHeader
                    if model.phase == .completed {
                        completionSummary
                        controls
                    } else {
                        canvas
                        controls
                        resultArea
                    }
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Recognition Study")
                .navigationBarTitleDisplayMode(.inline)
            }
            .onAppear {
                viewportSize = viewport.size
            }
            .onChange(of: viewport.size) { _, nextSize in
                viewportSize = nextSize
            }
        }
        .task {
            await model.start()
        }
    }

    private var disclosure: some View {
        Label {
            Text(
                "Engineering study only. Raw Pencil trajectories stay in this app on this iPad; this screen has no upload or production-recognition path."
            )
            .font(.footnote)
        } icon: {
            Image(systemName: "lock.iphone")
        }
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var promptHeader: some View {
        if let prompt = model.currentPrompt {
            VStack(spacing: 5) {
                Text(model.progressText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(prompt.displayChordText)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("Write chord \(prompt.displayChordText)")
                Text(prompt.instructionText)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Label(
                    prompt.chartStyle == .simpleChordSheet
                        ? "Simple chord sheet context"
                        : "Rhythm section sheet context",
                    systemImage: prompt.chartStyle == .simpleChordSheet
                        ? "rectangle.split.3x1"
                        : "music.note.list"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Study pass complete")
                    .font(.title2.bold())
                Text(model.progressText)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                canvasBackdrop
                if let preview = model.reviewPreview {
                    RecognitionStudyTrajectoryPreview(
                        preview: preview
                    )
                } else {
                    RecognitionStudyCanvasView(
                        drawing: $drawing,
                        canUndo: $canUndo,
                        command: canvasCommand,
                        isDrawingEnabled: isCanvasDrawingEnabled
                    )
                }
            }
            .onAppear {
                canvasSize = proxy.size
            }
            .onChange(of: proxy.size) { _, nextSize in
                canvasSize = nextSize
            }
        }
        .frame(minHeight: 300, idealHeight: 380, maxHeight: 440)
        .background(Color(uiColor: .systemBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityLabel("Single chord writing pad")
        .accessibilityHidden(model.phase == .completed)
    }

    @ViewBuilder
    private var canvasBackdrop: some View {
        if model.currentPrompt?.chartStyle == .rhythmSectionSheet {
            VStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, 28)
            .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.035))
                .padding(28)
                .accessibilityHidden(true)
        }
    }

    private var isCanvasDrawingEnabled: Bool {
        switch model.phase {
        case .preparing, .submitting, .reviewing, .recordingOutcome,
             .completed, .failed:
            return false
        case .ready:
            return true
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if model.phase != .completed {
                Button {
                    canvasCommand = RecognitionStudyCanvasCommand(.undo)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(!canUndo || model.phase != .ready)

                Button(role: .destructive) {
                    canvasCommand = RecognitionStudyCanvasCommand(.clear)
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(drawing.strokes.isEmpty || model.phase != .ready)

                Spacer(minLength: 12)
            }

            switch model.phase {
            case .failed:
                Button("Try Again") {
                    Task {
                        await model.retryPreparation()
                    }
                }
                .buttonStyle(.borderedProminent)

            case .completed:
                Button {
                    Task {
                        if await model.beginNewPass() {
                            canvasCommand = RecognitionStudyCanvasCommand(.reset)
                        }
                    }
                } label: {
                    Label("Start new pass", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)

            case .reviewing:
                Text("Confirm the ink below to continue")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)

            case .recordingOutcome:
                ProgressView("Saving outcome…")

            default:
                Button {
                    let snapshot = drawing
                    let submittedSize = canvasSize
                    Task {
                        let didStore = await model.submit(
                            drawing: snapshot,
                            canvasSize: submittedSize,
                            clientObservedOrientation:
                                RecognitionStudyCaptureViewModel
                                    .observedOrientation(
                                        viewportSize: viewportSize
                                    )
                        )
                        _ = didStore
                    }
                } label: {
                    if model.phase == .submitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Save & Continue", systemImage: "arrow.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !model.isReadyToSubmit
                        || drawing.strokes.isEmpty
                        || canvasSize.width <= 0
                        || canvasSize.height <= 0
                )
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var completionSummary: some View {
        if let summary = model.completedSummary {
            VStack(alignment: .leading, spacing: 14) {
                Text("Local engineering result")
                    .font(.headline)
                summaryRow(
                    title: "Exact canonical candidate",
                    value: summary.exactCanonicalCandidateCount,
                    total: summary.eligibleComparisonCount,
                    color: .green
                )
                summaryRow(
                    title: "Different or grammar-invalid candidate",
                    value: summary.differentOrInvalidCandidateCount,
                    total: summary.eligibleComparisonCount,
                    color: .orange
                )
                summaryRow(
                    title: "No candidate",
                    value: summary.noCandidateCount,
                    total: summary.eligibleComparisonCount,
                    color: .secondary
                )
                Divider()
                Text(
                    "Comparable captures: \(summary.eligibleComparisonCount) of \(summary.totalCount). Execution errors excluded: \(summary.executionErrorCount). Ambiguous ink excluded: \(summary.humanAmbiguousCount). Technical failures excluded: \(summary.technicalFailureCount)."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Text(
                    "This is a local engineering comparison, not writer-independent accuracy or a production trust result."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
    }

    private func summaryRow(
        title: String,
        value: Int,
        total: Int,
        color: Color
    ) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text("\(value) / \(total)")
                .font(.body.monospacedDigit().weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var resultArea: some View {
        if case let .failed(message) = model.phase {
            resultCard(
                title: "Not saved",
                candidate: nil,
                detail: message,
                color: .red,
                symbol: "exclamationmark.triangle.fill"
            )
        } else if let result = model.result {
            VStack(spacing: 10) {
                switch result {
                case let .accepted(displayText, detail):
                    resultCard(
                        title: result.title,
                        candidate: displayText,
                        detail: detail,
                        color: .green,
                        symbol: "checkmark.circle.fill"
                    )
                case let .review(candidate, detail):
                    resultCard(
                        title: result.title,
                        candidate: candidate,
                        detail: detail,
                        color: .orange,
                        symbol: "questionmark.circle.fill"
                    )
                case let .noRead(detail):
                    resultCard(
                        title: result.title,
                        candidate: nil,
                        detail: detail,
                        color: .secondary,
                        symbol: "minus.circle.fill"
                    )
                }
                if model.phase == .reviewing {
                    writerConfirmationControls
                }
            }
        } else {
            Color.clear
                .frame(height: 58)
                .accessibilityHidden(true)
        }
    }

    private var writerConfirmationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.requiresInterruptedCaptureExclusion {
                Text("This interrupted capture cannot be compared safely.")
                    .font(.callout.weight(.semibold))
                confirmationButton(
                    "Exclude & Continue",
                    state: .technicalFailure
                )
            } else {
                Text("Does the visible ink match the prompted chord?")
                    .font(.callout.weight(.semibold))
                HStack(spacing: 8) {
                    confirmationButton(
                        "Matches prompt",
                        state: .asPrompted
                    )
                    confirmationButton(
                        "I wrote it differently",
                        state: .executionError
                    )
                    confirmationButton(
                        "Ink is ambiguous",
                        state: .humanAmbiguous
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private struct RecognitionStudyTrajectoryPreview: View {
        let preview: RecognitionStudyReviewPreview

        var body: some View {
            Canvas { context, size in
                let sourceWidth = max(preview.sourceCanvasSize.width, 1)
                let sourceHeight = max(preview.sourceCanvasSize.height, 1)
                let scale = min(
                    size.width / sourceWidth,
                    size.height / sourceHeight
                )
                let offsetX = (size.width - sourceWidth * scale) / 2
                let offsetY = (size.height - sourceHeight * scale) / 2

                for stroke in preview.strokes where !stroke.points.isEmpty {
                    if stroke.points.count == 1, let point = stroke.points.first {
                        let center = CGPoint(
                            x: offsetX + point.x * scale,
                            y: offsetY + point.y * scale
                        )
                        context.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: center.x - 2,
                                    y: center.y - 2,
                                    width: 4,
                                    height: 4
                                )
                            ),
                            with: .color(.primary)
                        )
                        continue
                    }

                    var path = Path()
                    for (index, point) in stroke.points.enumerated() {
                        let location = CGPoint(
                            x: offsetX + point.x * scale,
                            y: offsetY + point.y * scale
                        )
                        if index == 0 {
                            path.move(to: location)
                        } else {
                            path.addLine(to: location)
                        }
                    }
                    context.stroke(
                        path,
                        with: .color(.primary),
                        style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }
            .allowsHitTesting(false)
            .accessibilityLabel("Restored saved chord ink")
        }
    }

    private func confirmationButton(
        _ title: String,
        state: RecognitionStudyWriterConfirmationState
    ) -> some View {
        Button(title) {
            Task {
                if await model.recordOutcomeAndAdvance(state) {
                    canvasCommand = RecognitionStudyCanvasCommand(.reset)
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private func resultCard(
        title: String,
        candidate: String?,
        detail: String,
        color: Color,
        symbol: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    if let candidate {
                        Text(candidate)
                            .font(.headline.monospaced())
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
#endif
