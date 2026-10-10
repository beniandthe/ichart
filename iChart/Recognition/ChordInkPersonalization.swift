import Foundation

/// Local, example-based adaptation. Distances are NOT calibrated probabilities.
/// This layer can nominate a review choice; it never changes the base model's
/// match, score, or trust evidence, and never learns from its own predictions.
enum PersonalInkExampleKind: String, Codable { case glyph, chord }
enum PersonalInkExampleSource: String, Codable {
    case setup, confirmedReview, explicitCorrection, practice

    static func reviewedChoice(acceptedText: String, presentedText: String?) -> Self? {
        guard let accepted = ChordRecognitionCompendium.match(
            acceptedText.trimmingCharacters(in: .whitespacesAndNewlines)
        )?.displayText else { return nil }
        let presented = presentedText.flatMap {
            ChordRecognitionCompendium.match($0.trimmingCharacters(in: .whitespacesAndNewlines))?.displayText
        }
        // The displayed default may already be personalized. Accepting it is
        // not independent correction evidence, even if the native read differs.
        return accepted == presented ? .confirmedReview : .explicitCorrection
    }
}

struct PersonalInkExample: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: PersonalInkExampleKind
    var label: String
    var strokes: [InkStroke]
    var source: PersonalInkExampleSource
    // Independently user-labeled symbol copied from a saved chord. Optional so
    // older profiles/reports decode unchanged and older apps can ignore it.
    var verifiedSymbolOrigin: PersonalInkVerifiedSymbolOrigin? = nil
    // Only new, explicitly contextualized intake records this metadata. A
    // missing value in older profiles remains unknown without a migration.
    var learningProvenance: PersonalInkLearningProvenance? = nil
    // New lessons keep the actual recognition input, not the thinned preview.
    // Nil means a legacy lesson whose discarded points cannot be recovered.
    var recognitionStrokes: [InkStroke]? = nil

    var recognitionInput: [InkStroke] { recognitionStrokes ?? strokes }
    var hasValidRecognitionInput: Bool { recognitionShape != nil }

    var recognitionShape: PersonalInkShape? {
        guard let shape = PersonalInkShape(strokes: recognitionInput) else { return nil }
        if let recognitionStrokes {
            guard Self.canStoreRecognitionInput(recognitionStrokes),
                  shape.normalizedStrokes == strokes else { return nil }
        }
        // A V2 receipt still requires full input when that optional field was
        // removed or decoded as null; it must never downgrade to a thumbnail.
        if let learningProvenance {
            do { try learningProvenance.validate(example: self) }
            catch { return nil }
        }
        return shape
    }

    static func canStoreRecognitionInput(_ strokes: [InkStroke]) -> Bool {
        // Do not silently discard empty strokes, malformed bounds, or invalid
        // timing while retaining a different input for a learned reader.
        // Storage keeps the existing personal-lesson limits. Model encoders
        // enforce their own separately versioned budgets; they cannot justify
        // truncating or narrowing the lesson which the user explicitly saved.
        let pointCount = strokes.reduce(0) { $0 + $1.points.count }
        guard !strokes.isEmpty, strokes.count <= 64, (2...32_768).contains(pointCount) else { return false }
        return strokes.allSatisfy { stroke in
            let bounds = stroke.bounds
            return !stroke.points.isEmpty
                && [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY].allSatisfy(\.isFinite)
                && bounds.minX <= bounds.maxX && bounds.minY <= bounds.maxY
                && (stroke.creationTimeOffset?.isFinite ?? true)
                && stroke.points.allSatisfy {
                    $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1e8 && abs($0.y) < 1e8
                        && ($0.timeOffset?.isFinite ?? true)
                }
        }
    }
}

struct PersonalInkVerifiedSymbolOrigin: Codable, Equatable {
    let chordExampleID: UUID
    let chordLabel: String
    let originalStrokeIndexes: [Int]
}

struct PersonalInkProfile: Codable, Equatable {
    var version = 1
    var revision = UUID()
    var generation = UUID()
    var isEnabled = false
    var learnsFromReviews = true
    var examples: [PersonalInkExample] = []

    static let maximumExamples = 192
    static let maximumExamplesPerLabel = 6
    static let glyphLabels: Set<String> = Set(["A", "B", "C", "D", "E", "F", "G", "b", "#", "-", "m", "7", "6", "9", "2", "4", "5", "1", "3", "/", "+", "o", "ø", "△", "(", ")"])

    @discardableResult
    mutating func learn(strokes: [InkStroke], label: String, kind: PersonalInkExampleKind,
                        source: PersonalInkExampleSource,
                        captureContext: PersonalInkCaptureContext? = nil) throws -> Bool {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical: String
        switch kind {
        case .glyph:
            guard Self.glyphLabels.contains(label) else { throw PersonalInkError.invalidLabel }
            canonical = label
        case .chord:
            guard let match = ChordRecognitionCompendium.match(label) else { throw PersonalInkError.invalidLabel }
            canonical = match.displayText
        }
        guard PersonalInkExample.canStoreRecognitionInput(strokes),
              let shape = PersonalInkShape(strokes: strokes) else { throw PersonalInkError.invalidInk }
        let boundedStrokes = shape.normalizedStrokes
        // Identity uses every point, never the thumbnail. A legacy thumbnail
        // must not delete/deduplicate different dense ink with the same preview.
        let matchingIDs = Set(examples.filter {
            $0.kind == kind && Self.sameLesson($0, as: shape)
        }.map(\.id))
        // Build all potentially failing metadata before any correction or cap
        // mutation. Deduplication/source upgrades preserve the original context
        // (including legacy nil); they are not a new acquisition of this ink.
        let learningProvenance: PersonalInkLearningProvenance?
        if let captureContext, !examples.contains(where: {
            $0.label == canonical && matchingIDs.contains($0.id)
        }) {
            learningProvenance = try PersonalInkLearningProvenance.make(context: captureContext,
                originalInput: strokes, storedInput: strokes, storedInputRole: .recognitionInput)
        } else {
            learningProvenance = nil
        }
        let originalCount = examples.count
        if source == .explicitCorrection {
            // An explicit correction can repair a previously confirmed label
            // for this trajectory, not rewrite other merely similar examples.
            examples.removeAll {
                $0.label != canonical && matchingIDs.contains($0.id)
            }
        }
        // Repeatedly confirming the same saved ink must not swamp the profile.
        if let index = examples.firstIndex(where: {
            $0.label == canonical && matchingIDs.contains($0.id)
        }) {
            let upgradesSource = source == .explicitCorrection && examples[index].source != .explicitCorrection
            if upgradesSource { examples[index].source = .explicitCorrection }
            let changed = upgradesSource || examples.count != originalCount
            if changed { revision = UUID() }
            return changed
        }
        while examples.filter({ $0.kind == kind && $0.label == canonical }).count >= Self.maximumExamplesPerLabel {
            if let index = examples.firstIndex(where: { $0.kind == kind && $0.label == canonical }) {
                examples.remove(at: index)
            }
        }
        examples.append(PersonalInkExample(kind: kind, label: canonical, strokes: boundedStrokes, source: source,
            learningProvenance: learningProvenance, recognitionStrokes: strokes))
        if examples.count > Self.maximumExamples { examples.removeFirst(examples.count - Self.maximumExamples) }
        revision = UUID()
        return true
    }

    /// Exact lesson presence under the same normalization/deduplication rule
    /// used by learning. This is persistence evidence, never a shape-match or
    /// proof that the explicit label is correct.
    func containsExactLesson(strokes: [InkStroke], label: String, kind: PersonalInkExampleKind) -> Bool {
        guard let shape = PersonalInkShape(strokes: strokes) else { return false }
        return examples.contains {
            $0.kind == kind && $0.label == label
                && Self.sameLesson($0, as: shape)
        }
    }

    private static func sameLesson(_ example: PersonalInkExample, as shape: PersonalInkShape) -> Bool {
        guard let reference = example.recognitionShape else { return false }
        return sameNormalizedTrajectory(reference.normalizedRecognitionStrokes, shape.normalizedRecognitionStrokes)
    }

    static func sameNormalizedTrajectory(_ lhs: [InkStroke], _ rhs: [InkStroke]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        // Normalized coordinates occupy a 48-by-32 grid. This subpixel tolerance
        // absorbs floating-point roundoff from page translation/scaling only;
        // it is not the much looser shape distance used for recognition. Keep
        // every stored point and stroke boundary in the identity comparison.
        let roundoffTolerance = 1e-8
        return zip(lhs, rhs).allSatisfy { left, right in
            left.points.count == right.points.count && zip(left.points, right.points).allSatisfy { a, b in
                abs(a.x - b.x) <= roundoffTolerance && abs(a.y - b.y) <= roundoffTolerance
            }
        }
    }

    /// User-selected example only. Preserve all other labels and opt-in state;
    /// frozen evaluation profiles are independent values and remain unchanged.
    @discardableResult
    mutating func removeExample(id: UUID) -> Bool {
        guard let index = examples.firstIndex(where: { $0.id == id }) else { return false }
        examples.remove(at: index)
        revision = UUID()
        return true
    }
}

enum PersonalInkError: LocalizedError {
    case invalidInk, invalidLabel, incompatibleProfile, profileSizeLimit
    var errorDescription: String? {
        switch self {
        case .invalidInk: return "Write one clear symbol or chord before saving."
        case .invalidLabel: return "Enter a supported chord, or choose one of the setup symbols."
        case .incompatibleProfile: return "This handwriting profile could not be loaded. Your charts are unchanged. Reset the profile to start again."
        case .profileSizeLimit: return "These handwriting examples exceed the local profile storage limit. Nothing was saved. Remove unused examples or teach fewer at once."
        }
    }
}

struct ChordInkPersonalSuggestion: Codable, Hashable {
    enum Source: String, Codable { case wholeChord, symbols }
    var text: String
    var source: Source
    var distance: Double
    // Geometric evidence, not probabilities. Correction provenance explains a
    // selectable alternative; it does not identify a different fresh target.
    var runnerUpDistance: Double? = nil
    var supportingExampleCount = 1
    var correctionSupportCount = 0
}

/// A bounded spatial descriptor: uniform scaling, translation and stroke-order
/// invariant; preserves aspect ratio and every visible stroke. No label is used
/// to extract features. The distance transform is prepared once per example.
struct PersonalInkShape {
    static let width = 48
    static let height = 32
    var occupied: [Int]
    var distances: [Float]
    var aspect: Double
    var normalizedStrokes: [InkStroke]
    var normalizedRecognitionStrokes: [InkStroke]

    init?(strokes: [InkStroke]) {
        guard !strokes.isEmpty, strokes.count <= 64,
              strokes.reduce(0, { $0 + $1.points.count }) <= 32_768 else { return nil }
        let points = strokes.flatMap(\.points)
        guard points.count >= 2, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1e8 && abs($0.y) < 1e8 }) else { return nil }
        let bounds = InkBounds.enclosing(points)
        let extent = max(bounds.width, bounds.height)
        guard extent >= 0.5 else { return nil }
        aspect = max(bounds.width, extent * 0.025) / max(bounds.height, extent * 0.025)
        let scale = min(Double(Self.width - 6) / max(bounds.width, extent * 0.025),
                        Double(Self.height - 6) / max(bounds.height, extent * 0.025))
        let offsetX = (Double(Self.width - 1) - bounds.width * scale) / 2
        let offsetY = (Double(Self.height - 1) - bounds.height * scale) / 2
        var pixels = Set<Int>()
        var normalized: [InkStroke] = []
        var fullNormalized: [InkStroke] = []
        for stroke in strokes where !stroke.points.isEmpty {
            let mapped = stroke.points.map { InkPoint(x: ($0.x - bounds.minX) * scale + offsetX,
                                                      y: ($0.y - bounds.minY) * scale + offsetY) }
            fullNormalized.append(InkStroke(points: mapped))
            // Bounded preview only. It must never replace recognition input.
            let step = max(1, Int(ceil(Double(mapped.count) / 128)))
            var retained = stride(from: 0, to: mapped.count, by: step).map { mapped[$0] }
            if retained.last != mapped.last, let last = mapped.last { retained.append(last) }
            normalized.append(InkStroke(points: retained))
            for index in mapped.indices {
                let start = index == 0 ? mapped[index] : mapped[index - 1]
                let end = mapped[index]
                let steps = max(1, Int(ceil(hypot(end.x - start.x, end.y - start.y) * 2)))
                for sample in 0...steps {
                    let t = Double(sample) / Double(steps)
                    let x = min(Self.width - 1, max(0, Int((start.x + (end.x - start.x) * t).rounded())))
                    let y = min(Self.height - 1, max(0, Int((start.y + (end.y - start.y) * t).rounded())))
                    pixels.insert(y * Self.width + x)
                }
            }
        }
        guard pixels.count >= 2 else { return nil }
        normalizedStrokes = normalized
        normalizedRecognitionStrokes = fullNormalized
        occupied = pixels.sorted()
        var field = [Float](repeating: 100, count: Self.width * Self.height)
        for index in pixels { field[index] = 0 }
        for y in 0..<Self.height {
            for x in 0..<Self.width {
                let i = y * Self.width + x
                if x > 0 { field[i] = min(field[i], field[i - 1] + 1) }
                if y > 0 { field[i] = min(field[i], field[i - Self.width] + 1) }
                if x > 0 && y > 0 { field[i] = min(field[i], field[i - Self.width - 1] + 1.4142) }
                if x + 1 < Self.width && y > 0 { field[i] = min(field[i], field[i - Self.width + 1] + 1.4142) }
            }
        }
        for y in (0..<Self.height).reversed() {
            for x in (0..<Self.width).reversed() {
                let i = y * Self.width + x
                if x + 1 < Self.width { field[i] = min(field[i], field[i + 1] + 1) }
                if y + 1 < Self.height { field[i] = min(field[i], field[i + Self.width] + 1) }
                if x + 1 < Self.width && y + 1 < Self.height { field[i] = min(field[i], field[i + Self.width + 1] + 1.4142) }
                if x > 0 && y + 1 < Self.height { field[i] = min(field[i], field[i + Self.width - 1] + 1.4142) }
            }
        }
        distances = field
    }

    func distance(to other: Self) -> Double {
        let forward = occupied.reduce(0.0) { $0 + Double(other.distances[$1]) } / Double(occupied.count)
        let reverse = other.occupied.reduce(0.0) { $0 + Double(distances[$1]) } / Double(other.occupied.count)
        return (forward + reverse) / 64 + min(abs(log(aspect / other.aspect)), 3) * 0.055
    }
}

struct PersonalInkSnapshot {
    struct Example { var label: String; var kind: PersonalInkExampleKind; var source: PersonalInkExampleSource; var shape: PersonalInkShape }
    let profile: PersonalInkProfile
    private let prepared: [Example]

    init(profile: PersonalInkProfile) {
        self.profile = profile
        prepared = profile.examples.compactMap { example in
            example.recognitionShape.map { Example(label: example.label, kind: example.kind, source: example.source, shape: $0) }
        }
    }

    func wasAlreadyLearned(strokes: [InkStroke]) -> Bool {
        guard let shape = PersonalInkShape(strokes: strokes) else { return false }
        return prepared.contains { shape.distance(to: $0.shape) < 0.0001 }
    }

    func applying(to baseline: ChordInkRecognitionResult, strokes: [InkStroke], previewEvenIfDisabled: Bool = false) -> ChordInkRecognitionResult {
        var result = baseline
        result.personalizationRevision = profile.revision
        result.personalSuggestion = suggestion(strokes: strokes, previewEvenIfDisabled: previewEvenIfDisabled)
        return result
    }

    func suggestion(strokes: [InkStroke], previewEvenIfDisabled: Bool = false) -> ChordInkPersonalSuggestion? {
        guard profile.isEnabled || previewEvenIfDisabled, !prepared.isEmpty else { return nil }
        if let match = nearest(strokes: strokes, kind: .chord) {
            return ChordInkPersonalSuggestion(text: match.label, source: .wholeChord, distance: match.distance,
                runnerUpDistance: match.runnerUpDistance, supportingExampleCount: match.supportCount,
                correctionSupportCount: match.correctionCount)
        }
        // Require every cluster to have unambiguous personal evidence. Never
        // discard an unread suffix or manufacture a chord from a prefix.
        let clusters = StrokeClusterer().cluster(strokes.map { InkStroke(points: $0.points) })
        guard !clusters.isEmpty, clusters.count <= 16 else { return nil }
        let matches = clusters.compactMap { nearest(strokes: $0.strokes, kind: .glyph) }
        guard matches.count == clusters.count,
              let match = ChordRecognitionCompendium.match(matches.map(\.label).joined()) else { return nil }
        return ChordInkPersonalSuggestion(text: match.displayText, source: .symbols,
            distance: matches.map(\.distance).max() ?? 0,
            supportingExampleCount: matches.map(\.supportCount).min() ?? 0)
    }

    private struct Match {
        var label: String
        var distance: Double
        var runnerUpDistance: Double?
        var supportCount: Int
        var correctionCount: Int
    }

    private func nearest(strokes: [InkStroke], kind: PersonalInkExampleKind) -> Match? {
        guard let query = PersonalInkShape(strokes: strokes) else { return nil }
        let maximumDistance = kind == .chord ? 0.065 : 0.075
        let minimumMargin = 0.018
        let distances = prepared.filter { $0.kind == kind }.map { ($0, query.distance(to: $0.shape)) }
        var bestByLabel: [String: Double] = [:]
        for (example, distance) in distances {
            bestByLabel[example.label] = min(bestByLabel[example.label] ?? .infinity, distance)
        }
        let ranked = bestByLabel.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }
        guard let best = ranked.first, best.value <= maximumDistance else { return nil }
        let runnerUp = ranked.dropFirst().first?.value
        if let runnerUp, runnerUp - best.value < minimumMargin { return nil }
        let support = distances.filter { example, distance in
            example.label == best.key && distance <= maximumDistance && distance <= best.value + minimumMargin
        }
        return Match(label: best.key, distance: best.value, runnerUpDistance: runnerUp,
            supportCount: support.count, correctionCount: support.filter { $0.0.source == .explicitCorrection }.count)
    }
}

/// Reads/writes occur only on initialization or an explicit profile operation,
/// never on PencilKit's drawing callback. Recognition takes an immutable snapshot.
final class PersonalInkProfileStore: @unchecked Sendable {
    static let maximumStoredBytes = 8_000_000
    static let shared = PersonalInkProfileStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PersonalHandwriting/profile-v1.json"))
    private let url: URL
    private let lock = NSLock()
    private var current: PersonalInkSnapshot
    private(set) var loadError: String?

    init(url: URL) {
        self.url = url
        var profile = PersonalInkProfile()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= Self.maximumStoredBytes else { throw PersonalInkError.incompatibleProfile }
                profile = try JSONDecoder().decode(PersonalInkProfile.self, from: data)
                guard profile.version == 1, profile.examples.count <= PersonalInkProfile.maximumExamples,
                      profile.examples.allSatisfy({ $0.hasValidRecognitionInput &&
                          ($0.kind == .glyph ? PersonalInkProfile.glyphLabels.contains($0.label) : ChordRecognitionCompendium.match($0.label) != nil) }) else {
                    throw PersonalInkError.incompatibleProfile
                }
            } catch {
                profile = PersonalInkProfile()
                loadError = PersonalInkError.incompatibleProfile.localizedDescription
            }
        }
        current = PersonalInkSnapshot(profile: profile)
    }

    func snapshot() -> PersonalInkSnapshot {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Perform an external save/publication only while this exact enabled
    /// profile is still current. No profile data is changed by this method.
    /// The closure runs under the store lock and MUST NOT reenter this store
    /// (including snapshot/update/reset), directly or through another callback.
    func withUnchangedProfile<T>(expected: PersonalInkProfile,
                                 operation: () throws -> T) throws -> T? {
        lock.lock(); defer { lock.unlock() }
        guard current.profile.isEnabled, current.profile == expected else { return nil }
        return try operation()
    }

    func update(_ edit: (inout PersonalInkProfile) throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        var profile = current.profile
        try edit(&profile)
        guard profile != current.profile else { return }
        profile.revision = UUID()
        let data = try JSONEncoder().encode(profile)
        // Refuse the entire edit before writing or publishing. A file which
        // cannot pass our load limit must never replace the saved profile.
        guard data.count <= Self.maximumStoredBytes else { throw PersonalInkError.profileSizeLimit }
        guard profile.version == 1, profile.examples.count <= PersonalInkProfile.maximumExamples,
              profile.examples.allSatisfy({ $0.hasValidRecognitionInput &&
                  ($0.kind == .glyph ? PersonalInkProfile.glyphLabels.contains($0.label) : ChordRecognitionCompendium.match($0.label) != nil) }) else {
            throw PersonalInkError.incompatibleProfile
        }
        let prepared = PersonalInkSnapshot(profile: profile)
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var excludedFolder = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedFolder.setResourceValues(values)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        current = prepared
        loadError = nil
    }

    func reset() throws { try update { $0 = PersonalInkProfile() } }
}
