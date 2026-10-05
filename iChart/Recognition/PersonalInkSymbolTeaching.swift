import Foundation

/// Segmentation is a proposal, never a source of symbol labels. Each selected
/// piece needs an explicit label chosen by the user before it can teach.
struct PersonalInkSymbolTeachingReview: Identifiable {
    struct Piece: Identifiable, Equatable {
        let id: Int
        let originalStrokeIndexes: [Int]
        let strokes: [InkStroke]
    }
    struct Receipt: Equatable {
        let selectedSymbolCount: Int
        let changedSymbolCount: Int
        let previousExampleCount: Int
        let savedExampleCount: Int
    }
    enum Failure: LocalizedError {
        case unavailable, disabled, changedSource, noLabels, invalidSelection, conflictingSelections, capacity
        var errorDescription: String? {
            switch self {
            case .unavailable: return "This example cannot be safely separated. Use Choose Examples to teach its symbols."
            case .disabled: return "Personal learning is off. No symbols were saved."
            case .changedSource: return "This saved example or profile changed. Reopen Teach Symbols before saving."
            case .noLabels: return "Choose a label for at least one piece containing a single symbol."
            case .invalidSelection: return "One of these symbol selections is no longer valid. Nothing was saved."
            case .conflictingSelections: return "Identical symbol shapes have different selected labels. Check those labels before teaching. Nothing was saved."
            case .capacity: return "These selections do not fit the profile limits. Teach fewer examples of the same symbol, or remove unused examples. Nothing was saved."
            }
        }
    }

    let id = UUID()
    let source: PersonalInkExample
    let profileGeneration: UUID
    let pieces: [Piece]

    init(exampleID: UUID, profile: PersonalInkProfile) throws {
        guard profile.isEnabled else { throw Failure.disabled }
        guard let example = profile.examples.first(where: { $0.id == exampleID }), example.kind == .chord,
              example.hasValidRecognitionInput else { throw Failure.unavailable }
        let recognitionInput = example.recognitionInput
        let clusters = StrokeClusterer(wrapperPolicy: .preserveOriginalInk)
            .indexedClusters(recognitionInput.map { InkStroke(points: $0.points) })
        var proposedGroups: [[Int]] = []
        let coversSource = !clusters.isEmpty && clusters.count <= 16
            && clusters.flatMap(\.originalIndexes).sorted() == Array(recognitionInput.indices)
        if coversSource {
            for cluster in clusters {
                let original = cluster.originalIndexes.map { recognitionInput[$0] }
                // A failed proposal is not a reason to deny manual selection.
                // Keep the source available without inventing a partition.
                guard original.map(\.points) == cluster.cluster.strokes.map(\.points) else {
                    proposedGroups = []
                    break
                }
                proposedGroups.append(cluster.originalIndexes.sorted())
            }
        }
        source = example
        profileGeneration = profile.generation
        pieces = try Self.makePieces(proposedGroups, source: example)
    }

    private init(source: PersonalInkExample, profileGeneration: UUID, pieces: [Piece]) {
        self.source = source
        self.profileGeneration = profileGeneration
        self.pieces = pieces
    }

    /// Explicit ownership in stored-example coordinates. A partial partition
    /// keeps its complement unassigned; it never trims a stroke or fabricates
    /// a new acquisition. Ownership/labels are user input, not accuracy proof.
    func selectingOriginalGroups(_ groups: [[Int]]) throws -> Self {
        .init(source: source, profileGeneration: profileGeneration,
              pieces: try Self.makePieces(groups, source: source))
    }

    var unassignedStrokeIndexes: [Int] {
        let assigned = Set(pieces.flatMap(\.originalStrokeIndexes))
        return source.recognitionInput.indices.filter { !assigned.contains($0) }
    }

    private static func makePieces(_ groups: [[Int]], source: PersonalInkExample) throws -> [Piece] {
        let indexes = groups.flatMap { $0 }
        guard groups.count <= 16, groups.allSatisfy({ !$0.isEmpty }),
              indexes.allSatisfy({ source.recognitionInput.indices.contains($0) }),
              Set(indexes).count == indexes.count else { throw Failure.invalidSelection }
        return groups.enumerated().map { index, group in
            let ordered = group.sorted()
            return .init(id: index, originalStrokeIndexes: ordered,
                         strokes: ordered.map { source.recognitionInput[$0] })
        }
    }

    /// Atomic value edit: a late invalid selection cannot partially teach.
    /// Whole-chord labels are deliberately never parsed into inferred lessons.
    func teach(labels: [String?], profile: inout PersonalInkProfile) throws -> Receipt {
        guard profile.isEnabled else { throw Failure.disabled }
        guard profile.generation == profileGeneration,
              profile.examples.first(where: { $0.id == source.id }) == source else { throw Failure.changedSource }
        guard labels.count == pieces.count,
              labels.compactMap({ $0 }).allSatisfy(PersonalInkProfile.glyphLabels.contains) else { throw Failure.invalidSelection }
        let selected = zip(pieces, labels).compactMap { piece, label in label.map { (piece, $0) } }
        guard !selected.isEmpty else { throw Failure.noLabels }
        let normalizedSelections = try selected.map { piece, label -> ([InkStroke], String) in
            guard let shape = PersonalInkShape(strokes: piece.strokes) else { throw Failure.invalidSelection }
            return (shape.normalizedRecognitionStrokes, label)
        }
        for left in normalizedSelections.indices {
            for right in normalizedSelections.indices where right > left {
                guard normalizedSelections[left].1 == normalizedSelections[right].1
                    || !PersonalInkProfile.sameNormalizedTrajectory(
                        normalizedSelections[left].0, normalizedSelections[right].0) else {
                    throw Failure.conflictingSelections
                }
            }
        }
        let captureContext: PersonalInkCaptureContext?
        if let provenance = source.learningProvenance {
            // A selected saved piece belongs to the parent's recorded intake,
            // not a newly invented handwriting acquisition/session. Reject
            // changed metadata before the atomic value edit begins.
            do { try provenance.validate(example: source) }
            catch { throw Failure.changedSource }
            captureContext = .init(sessionID: provenance.context.sessionID,
                captureID: provenance.context.captureID, capturedAt: provenance.context.capturedAt,
                origin: .selectedSavedSymbol, chartStyle: provenance.context.chartStyle)
        } else {
            captureContext = nil
        }
        var updated = profile
        var changed = 0
        for (piece, label) in selected {
            let oldIDs = Set(updated.examples.map(\.id))
            if try updated.learn(strokes: piece.strokes, label: label, kind: .glyph, source: .explicitCorrection,
                                 captureContext: captureContext) {
                changed += 1
                // A duplicate standalone lesson retains its existing origin.
                if let index = updated.examples.firstIndex(where: { !oldIDs.contains($0.id) }) {
                    updated.examples[index].verifiedSymbolOrigin = .init(chordExampleID: source.id,
                        chordLabel: source.label, originalStrokeIndexes: piece.originalStrokeIndexes)
                }
            }
        }
        // A later correction/cap must not silently discard an earlier selected
        // lesson. Publish a receipt only if the source and every confirmed
        // trajectory/label remain represented after the entire value edit.
        guard updated.examples.contains(source), selected.allSatisfy({ piece, label in
            updated.containsExactLesson(strokes: piece.strokes, label: label, kind: .glyph)
        }) else { throw Failure.capacity }
        let receipt = Receipt(selectedSymbolCount: selected.count, changedSymbolCount: changed,
                              previousExampleCount: profile.examples.count, savedExampleCount: updated.examples.count)
        profile = updated
        return receipt
    }
}
