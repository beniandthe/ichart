import Foundation
import CryptoKit

/// A session identifies local intake into a teaching flow. In particular,
/// chart review may reuse ink acquired earlier: this context does not verify
/// original acquisition, independent handwriting, writer identity or consent.
struct PersonalInkCaptureContext: Codable, Equatable {
    enum Origin: String, Codable {
        case setup, practice, chartReview, savedEvaluation, selectedSavedSymbol
    }

    var sessionID: UUID
    var captureID: UUID
    var capturedAt: Date
    var origin: Origin
    var chartStyle: String?

    init(sessionID: UUID, captureID: UUID = UUID(), capturedAt: Date = Date(),
         origin: Origin, chartStyle: String? = nil) {
        self.sessionID = sessionID
        self.captureID = captureID
        self.capturedAt = capturedAt
        self.origin = origin
        self.chartStyle = chartStyle
    }

    /// The local evaluation journal uses ChartLayoutStyle raw values. Unknown
    /// or other chart styles remain nil instead of acquiring a guessed label.
    static func chartStyleToken(for rawValue: String) -> String? {
        switch rawValue {
        case "simpleChordSheet": return "simple-chord-sheet"
        case "rhythmSectionSheet": return "rhythm-section-sheet"
        default: return nil
        }
    }
}

/// Additive local evidence for one newly appended lesson. V1 binds the passed
/// input separately from the stored normalized preview. V2 explicitly binds
/// both digests to the exact stored recognition input. Neither version can
/// establish freshness of translated, scaled, reordered or otherwise reused ink.
struct PersonalInkLearningProvenance: Codable, Equatable {
    enum StoredInputRole: String, Codable {
        case recognitionInput
    }

    enum Failure: LocalizedError, Equatable {
        case unsupportedVersion, invalidDate, unsupportedChartStyle, invalidDigest
        case originalInputMismatch, storedInputMismatch

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "This lesson's local intake metadata uses an unsupported version."
            case .invalidDate: return "This lesson's local intake metadata contains an invalid date. Nothing was saved."
            case .unsupportedChartStyle: return "This lesson's local intake metadata contains an unsupported chart style. Nothing was saved."
            case .invalidDigest: return "This lesson's local intake metadata contains an invalid input digest."
            case .originalInputMismatch: return "This lesson's local intake metadata does not match its original recognition input."
            case .storedInputMismatch: return "This lesson's local intake metadata does not match its stored ink."
            }
        }
    }

    static let legacyVersion = 1
    static let currentVersion = 2
    private static let supportedChartStyles: Set<String> = ["simple-chord-sheet", "rhythm-section-sheet"]

    var version = PersonalInkLearningProvenance.legacyVersion
    var context: PersonalInkCaptureContext
    var taughtAt: Date
    var originalInputSHA256: String
    var storedInputSHA256: String
    var storedInputRole: StoredInputRole? = nil

    static func make(context: PersonalInkCaptureContext, taughtAt: Date = Date(),
                     originalInput: [InkStroke], storedInput: [InkStroke],
                     storedInputRole: StoredInputRole? = nil) throws -> Self {
        try validate(context: context, taughtAt: taughtAt)
        return try Self(version: storedInputRole == .recognitionInput ? currentVersion : legacyVersion,
            context: context, taughtAt: taughtAt,
            originalInputSHA256: inputSHA256(strokes: originalInput),
            storedInputSHA256: inputSHA256(strokes: storedInput), storedInputRole: storedInputRole)
    }

    /// Validates metadata and binds it to the actual stored lesson strokes.
    /// The original input is no longer available here; its digest's syntax is
    /// checked, but acquisition history or chronology is never inferred.
    func validate(storedInput: [InkStroke]) throws {
        guard (version == Self.legacyVersion && storedInputRole == nil)
            || (version == Self.currentVersion && storedInputRole == .recognitionInput) else {
            throw Failure.unsupportedVersion
        }
        try Self.validate(context: context, taughtAt: taughtAt)
        guard Self.validDigest(originalInputSHA256), Self.validDigest(storedInputSHA256) else {
            throw Failure.invalidDigest
        }
        guard try Self.inputSHA256(strokes: storedInput) == storedInputSHA256 else {
            throw Failure.storedInputMismatch
        }
    }

    /// Validates the versioned role against the lesson that will actually be
    /// consumed by recognition. V1 binds the legacy stored preview. V2 binds
    /// both digests to the exact raw recognition input; it does not reinterpret
    /// historical V1 metadata as proof that discarded points ever existed.
    func validate(example: PersonalInkExample) throws {
        if let recognitionStrokes = example.recognitionStrokes {
            guard version == Self.currentVersion, storedInputRole == .recognitionInput else {
                throw Failure.unsupportedVersion
            }
            guard PersonalInkShape(strokes: recognitionStrokes)?.normalizedStrokes == example.strokes else {
                throw Failure.storedInputMismatch
            }
            try validate(storedInput: recognitionStrokes)
            guard try Self.inputSHA256(strokes: recognitionStrokes) == originalInputSHA256 else {
                throw Failure.originalInputMismatch
            }
        } else {
            guard version == Self.legacyVersion, storedInputRole == nil else {
                throw Failure.unsupportedVersion
            }
            try validate(storedInput: example.strokes)
        }
    }

    /// Canonical packet bytes preserve exact geometry, stored bounds, stroke
    /// order and timing availability without another normalization pass.
    static func inputSHA256(strokes: [InkStroke]) throws -> String {
        let data = try ChordInkCanonicalTrajectoryPacket(strokes: strokes).canonicalData()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validate(context: PersonalInkCaptureContext, taughtAt: Date) throws {
        guard context.capturedAt.timeIntervalSinceReferenceDate.isFinite,
              taughtAt.timeIntervalSinceReferenceDate.isFinite else { throw Failure.invalidDate }
        if let style = context.chartStyle, !supportedChartStyles.contains(style) {
            throw Failure.unsupportedChartStyle
        }
    }

    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// A mechanical account of the frozen profile's observed intake sessions.
/// Completeness and disjointness never verify writer identity, consent,
/// original acquisition, chronological ordering or recognition accuracy.
struct PersonalInkProfileLineageSummary: Codable, Equatable {
    let querySessionID: UUID
    let trackedExampleIDs: [UUID]
    let untrackedExampleIDs: [UUID]
    let mismatchedExampleIDs: [UUID]
    let observedSupportSessionIDs: [UUID]
    let overlapExampleIDs: [UUID]
    let isMetadataComplete: Bool
    let areObservedSupportSessionsDisjoint: Bool
    let assuranceNote: String

    init(profile: PersonalInkProfile, querySessionID: UUID) {
        self.querySessionID = querySessionID
        var tracked: [UUID] = []
        var untracked: [UUID] = []
        var mismatched: [UUID] = []
        var sessions = Set<UUID>()
        var overlap: [UUID] = []
        for example in profile.examples {
            guard let provenance = example.learningProvenance else {
                untracked.append(example.id)
                continue
            }
            do {
                try provenance.validate(example: example)
                tracked.append(example.id)
                sessions.insert(provenance.context.sessionID)
                if provenance.context.sessionID == querySessionID { overlap.append(example.id) }
            } catch {
                mismatched.append(example.id)
            }
        }
        trackedExampleIDs = tracked
        untrackedExampleIDs = untracked
        mismatchedExampleIDs = mismatched
        observedSupportSessionIDs = sessions.sorted { $0.uuidString < $1.uuidString }
        overlapExampleIDs = overlap
        let complete = untracked.isEmpty && mismatched.isEmpty
        isMetadataComplete = complete
        // An empty profile is vacuously complete and disjoint, with zero
        // observed supports. These flags confer no accuracy or transfer claim.
        areObservedSupportSessionsDisjoint = complete && overlap.isEmpty
        assuranceNote = "Observed local intake sessions only; writer identity, consent, original acquisition and chronology are not verified. Exact input hashes do not establish freshness of transformed-equivalent ink."
    }
}
