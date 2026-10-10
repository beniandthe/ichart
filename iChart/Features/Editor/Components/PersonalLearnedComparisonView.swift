#if DEBUG
import SwiftUI

@MainActor
final class PersonalLearnedComparisonModel: ObservableObject {
    @Published var report: PersonalInkLearnedRunReport?
    @Published var pair: PersonalInkOwnershipComparisonReport?
    @Published var error: String?
    @Published var busy = false
    private let queue = DispatchQueue(label: "com.ichart.personal-ml-comparison", qos: .userInitiated)
    private let profileStore: PersonalInkProfileStore
    private let reportDirectory: URL
    private let encoderFactory: () throws -> PersonalInkVisualEncoding

    init(profileStore: PersonalInkProfileStore = .shared,
         reportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
             .appendingPathComponent("PersonalHandwriting/learned-comparisons-v1"),
         encoderFactory: @escaping () throws -> PersonalInkVisualEncoding = {
             guard let directory = PersonalInkVisualEncoder.bundledDirectory() else {
                 throw PersonalInkLearnedComparison.Failure.invalidEncoder
             }
             return try PersonalInkVisualEncoder(directory: directory)
         }) {
        self.profileStore = profileStore
        self.reportDirectory = reportDirectory
        self.encoderFactory = encoderFactory
    }

    func compare(_ run: PersonalInkEvaluationRun) {
        guard !busy else { return }
        report = nil; pair = nil; error = nil
        let current = profileStore.snapshot().profile
        guard current.isEnabled else { error = PersonalInkLearnedComparison.Failure.disabled.localizedDescription; return }
        busy = true
        let factory = encoderFactory
        queue.async {
            let result = Result { try PersonalInkLearnedRunReport.compare(run, encoder: factory()) }
            DispatchQueue.main.async {
                self.busy = false
                guard self.profileStore.snapshot().profile == current else {
                    self.error = PersonalInkLearnedComparison.Failure.staleProfile.localizedDescription
                    return
                }
                switch result {
                case .success(let report):
                    do { try report.save(in: self.reportDirectory); self.report = report }
                    catch { self.error = "Comparison could not be saved: \(error.localizedDescription)" }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }

    func compareAlternatives(_ run: PersonalInkEvaluationRun) {
        guard !busy else { return }
        report = nil; pair = nil; error = nil
        let current = profileStore.snapshot().profile
        guard current.isEnabled else { error = PersonalInkLearnedComparison.Failure.disabled.localizedDescription; return }
        busy = true
        let factory = encoderFactory
        queue.async {
            let result = Result {
                try PersonalInkLearnedRunReport.compare(run, encoder: factory(), grouping: .losslessSourceV2,
                    includesCompleteTokenHypotheses: true)
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let report):
                    do {
                        let published = try self.profileStore.withUnchangedProfile(expected: current) {
                            try report.save(in: self.reportDirectory)
                            self.report = report
                            return true
                        }
                        if published != true { self.error = PersonalInkLearnedComparison.Failure.staleProfile.localizedDescription }
                    } catch { self.error = "Comparison could not be saved: \(error.localizedDescription)" }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }

    /// The actual comparison surface uses one fitted model for both grouping
    /// routes and publishes nothing until the complete pair is durably saved.
    /// Keep `compare(_:)` above unchanged as the historical single-report API.
    func comparePair(_ run: PersonalInkEvaluationRun) {
        guard !busy else { return }
        report = nil; pair = nil; error = nil
        let current = profileStore.snapshot().profile
        guard current.isEnabled else {
            error = PersonalInkLearnedComparison.Failure.disabled.localizedDescription
            return
        }
        busy = true
        let factory = encoderFactory
        queue.async {
            let result = Result { try PersonalInkOwnershipComparisonReport.compare(run, encoder: factory()) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let pair):
                    do {
                        let published = try self.profileStore.withUnchangedProfile(expected: current) {
                            let directory = self.reportDirectory
                                .appendingPathComponent("selective-ownership-pairs-v1", isDirectory: true)
                            try pair.save(in: directory)
                            self.report = pair.legacy
                            self.pair = pair
                            return true
                        }
                        guard published == true else {
                            self.error = PersonalInkLearnedComparison.Failure.staleProfile.localizedDescription
                            return
                        }
                    } catch {
                        self.error = "Comparison pair could not be saved: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

/// Display of already validated frozen metadata, not an acquisition or quality
/// assessment. Keeping this separate makes the actual UI wording inspectable.
struct PersonalInkFrozenLineagePresentation {
    enum Status: Equatable { case legacyUnknown, emptySupport, incomplete, overlapping, disjoint }
    let status: Status
    let summary: String
    let statusText: String
    let warnings: [String]
    let details: String
    let assurance: String

    init(lineage: PersonalInkProfileLineageSummary?) {
        guard let lineage else {
            status = .legacyUnknown
            summary = "Saved support intake: unknown (older test)."
            statusText = "No frozen intake summary was saved."
            warnings = ["Older evidence has not been backfilled from later lessons."]
            details = "Query and support intake identifiers were not recorded in this comparison."
            assurance = "Local intake metadata does not verify writer identity, original acquisition or fresh handwriting."
            return
        }
        let tracked = lineage.trackedExampleIDs.count
        let untracked = lineage.untrackedExampleIDs.count
        let mismatched = lineage.mismatchedExampleIDs.count
        let overlapping = lineage.overlapExampleIDs.count
        summary = "Saved support intake: \(tracked) tracked · \(untracked) untracked · \(mismatched) mismatched · \(overlapping) overlapping"
        var notes: [String] = []
        if !lineage.isMetadataComplete {
            notes.append("Missing or mismatched metadata: support/query intake separation is not established.")
        }
        if overlapping > 0 { notes.append("Some support lessons share the query intake session.") }
        if tracked + untracked + mismatched == 0 {
            status = .emptySupport
            statusText = "No support examples were saved. Empty support is not transfer evidence."
        } else if overlapping > 0 {
            status = .overlapping
            statusText = "Observed support and query intake sessions overlap."
        } else if !lineage.isMetadataComplete || !lineage.areObservedSupportSessionsDisjoint {
            status = .incomplete
            statusText = "Observed support/query intake separation is unknown."
        } else {
            status = .disjoint
            statusText = "Observed support intake sessions are separate from this query session."
        }
        warnings = notes
        func identifiers(_ values: [UUID]) -> String {
            values.isEmpty ? "none" : values.map(\.uuidString).joined(separator: ", ")
        }
        details = "Query intake: \(lineage.querySessionID.uuidString)\nObserved support intakes: \(identifiers(lineage.observedSupportSessionIDs))\nTracked lessons: \(identifiers(lineage.trackedExampleIDs))\nUntracked lessons: \(identifiers(lineage.untrackedExampleIDs))\nMismatched lessons: \(identifiers(lineage.mismatchedExampleIDs))\nOverlapping lessons: \(identifiers(lineage.overlapExampleIDs))"
        assurance = lineage.assuranceNote
    }
}

@MainActor
struct PersonalLearnedComparisonView: View {
    let run: PersonalInkEvaluationRun
    @StateObject private var model: PersonalLearnedComparisonModel

    init(run: PersonalInkEvaluationRun) {
        self.run = run
        _model = StateObject(wrappedValue: PersonalLearnedComparisonModel())
    }

    init(run: PersonalInkEvaluationRun, model: PersonalLearnedComparisonModel) {
        self.run = run
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Learned model comparison").font(.title2.bold())
                Text("Experimental · read-only · nothing is rendered or taught")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Uses the profile saved before this chart test (\(run.profile.examples.count) examples). Later corrections are not used. Saved ink is a replay, not a new handwriting test.")
                Text("The model learns personal weights from your labeled examples. Its scores are not confidence percentages. Musical symbols need their own labeled examples; whole-chord corrections do not silently label their parts.")
                    .font(.callout).foregroundStyle(.secondary)
                if let error = model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("learned.error") }
                if !run.records.contains(where: { $0.recognitionStrokes != nil }) {
                    Text("This older test did not save the original recognition coordinates. A new chart capture is needed; thumbnail ink cannot replace them.")
                        .foregroundStyle(.orange)
                }
                if model.busy {
                    ProgressView("Fitting saved examples and comparing model hypotheses…")
                } else {
                    Menu {
                        Button("Current paired comparison") { model.comparePair(run) }
                        Button("Complete-symbol ML alternatives") { model.compareAlternatives(run) }
                    } label: {
                        Label("Compare this saved test", systemImage: "chart.bar.doc.horizontal")
                    }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("learned.compare")
                        .disabled(!run.records.contains(where: { $0.recognitionStrokes != nil }))
                }
                if let pair = model.pair {
                    legacyReportView(pair.legacy)
                    selectiveOwnershipView(pair.selective, pairID: pair.id)
                } else if let report = model.report {
                    // Historical callers still publish and render one legacy
                    // report through the unchanged `compare(_:)` API.
                    legacyReportView(report)
                }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Learned ML")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func legacyReportView(_ report: PersonalInkLearnedRunReport) -> some View {
        Label("Comparison saved locally", systemImage: "checkmark.circle").font(.callout)
        Text("Saved lessons: \(report.glyphLessonCount) symbols · \(report.wholeChordLessonCount) whole chords")
            .font(.headline)
        frozenLineageView(report.profileLineage)
        Group {
            if report.completeTokenHypothesisVersion == PersonalInkMLChordHypothesisComparison.version {
                Text("This separate lossless-grouping comparison keeps top-1 results below. Requested complete-symbol alternatives are unscored hypotheses; unsupported rows may have none. None replaces an app reading.")
            } else if report.groupingVersion == PersonalInkLearnedComparison.Grouping.losslessSourceV2.rawValue {
                Text("The learned-model readings below use the same saved ink and lossless grouping route. Personal methods are shown separately; none replaces the recorded app result.")
            } else {
                Text("The legacy learned-model readings below share the same saved ink and legacy grouping route. Personal methods are shown separately; none replaces the recorded app result.")
            }
        }.font(.caption).foregroundStyle(.secondary)
        if let scorecard = report.scorecard { scorecardView(scorecard) }
        ForEach(report.rows) { row in
            if let record = run.records.first(where: { $0.id == row.id }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Measure \(record.measureIndex) · intended \(record.intended ?? "unlabeled")").font(.headline)
                    Text("Recorded app: \(record.personalized ?? "No read")")
                    if let prediction = row.prediction {
                        let presentationLabels = prediction.chordDomainPresentationLabels
                        Text("Shared ML: \(prediction.genericChord ?? "No complete read")")
                        Text("ML + examples (original): \(prediction.personalChord ?? "No complete read")")
                            .fontWeight(.semibold)
                        if let anchored = prediction.anchored {
                            Text("ML + examples (new): \(anchored.chord ?? "No complete read")").fontWeight(.semibold)
                            Text("The new method tries to preserve untaught character shapes. It can also lose useful corrections; it is not automatically preferred.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Show proposed-group readings and whole-chord candidates") {
                            ForEach(prediction.glyphs.indices, id: \.self) { index in
                                Text("Proposed group \(index + 1): \(presentationLabels.generic[index] ?? "Unresolved") → \(presentationLabels.personal[index] ?? "Unresolved")")
                                if let anchored = presentationLabels.anchored,
                                   anchored.indices.contains(index) {
                                    Text("New personal method: \(anchored[index] ?? "Unresolved")")
                                }
                            }
                            if !prediction.glyphs.isEmpty {
                                Text("A proposed group is not a verified symbol boundary.")
                                    .foregroundStyle(.secondary)
                            }
                            if !prediction.wholeChordRanks.isEmpty {
                                Text("Closest taught chords: \(prediction.wholeChordRanks.map(\.label).joined(separator: ", "))")
                                Text("Closed-set candidates only: even unrelated ink can rank first. These are not accepted reads.")
                                    .foregroundStyle(.secondary)
                            }
                        }.font(.callout)
                    }
                    if let exclusion = row.exclusion { Text(exclusion).font(.caption).foregroundStyle(.orange) }
                    if let hypotheses = row.completeTokenHypotheses {
                        DisclosureGroup("Complete-symbol alternatives · not scored") {
                            Text(hypotheses.assuranceNote).font(.caption).foregroundStyle(.orange)
                            hypothesisView(hypotheses.generic, title: "Shared ML")
                            hypothesisView(hypotheses.personal, title: "ML + examples")
                            if let anchored = hypotheses.anchored {
                                hypothesisView(anchored, title: "Anchored ML + examples")
                            }
                        }
                        .accessibilityIdentifier("learned.complete-token-hypotheses")
                    }
                }.padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        Text("Source: UJI Pen Characters v2, Prat et al., CC BY 4.0. The shared training data contains characters, not complete chords.")
            .font(.caption).foregroundStyle(.secondary)
        Text("Model \(report.encoderIdentity)\nProfile \(report.profileRevision.uuidString)")
            .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
    }

    private func frozenLineageView(_ lineage: PersonalInkProfileLineageSummary?) -> some View {
        let presentation = PersonalInkFrozenLineagePresentation(lineage: lineage)
        return VStack(alignment: .leading, spacing: 6) {
            Text(presentation.summary).font(.callout.weight(.semibold))
                .accessibilityIdentifier("learned.lineage.summary")
            Text(presentation.statusText).font(.caption)
                .accessibilityIdentifier("learned.lineage.status")
            ForEach(presentation.warnings, id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
            DisclosureGroup("Inspect frozen intake metadata") {
                Text(presentation.details).font(.caption2.monospaced()).textSelection(.enabled)
                    .accessibilityIdentifier("learned.lineage.details")
            }.font(.caption)
            Text(presentation.assurance).font(.caption2).foregroundStyle(.secondary)
        }.accessibilityIdentifier("learned.lineage")
    }

    private func hypothesisView(_ result: PersonalInkMLChordComposer.Result, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold))
            if result.candidates.isEmpty { Text("No grammar-valid complete alternative found in this search.") }
            ForEach(Array(result.candidates.enumerated()), id: \.offset) { _, candidate in
                Text("\(candidate.text) — tokens: \(candidate.tokens.joined(separator: " · "))")
            }
            Text("Examined \(result.examinedSequenceCount) of \(result.totalSequenceCount) retained-rank sequences. \(result.searchComplete ? "Search complete within those ranks." : "Search incomplete; unexplored readings remain unknown.")\(result.omittedCandidates ? " More valid alternatives were omitted by the display cap." : "")")
                .font(.caption).foregroundStyle(.secondary)
            Text("No confidence percentage or ownership approval is implied.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func selectiveOwnershipView(_ report: PersonalInkLearnedRunReport, pairID: UUID) -> some View {
        let unresolved = report.scorecard?.ownershipUnresolvedCount
            ?? report.rows.filter { $0.prediction?.ownership != nil }.count
        VStack(alignment: .leading, spacing: 12) {
            Text("Selective ownership comparison").font(.title3.bold())
            Text("All nontrivial ownership proposals are uncalibrated here, so this route leaves them unresolved before any query group or whole chord is encoded.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Eligible attempts — resolved ownership: 0 · unresolved: \(unresolved)")
                .font(.headline)
            Text("Zero committed wrong reads with zero resolved reads is not recognition improvement. Structural coverage only means every source stroke index appears once; it does not make a proposed group a verified symbol.")
                .font(.caption).foregroundStyle(.orange)
            if let scorecard = report.scorecard {
                scorecardView(scorecard, title: "Selective ownership results",
                              identifier: "learned.ownership.scorecard")
            }
            ForEach(report.rows) { row in
                if let record = run.records.first(where: { $0.id == row.id }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Measure \(record.measureIndex) · intended \(record.intended ?? "unlabeled")")
                            .font(.headline)
                        if let ownership = row.prediction?.ownership {
                            Label("Ownership unresolved", systemImage: "questionmark.diamond")
                                .fontWeight(.semibold)
                                .accessibilityIdentifier("learned.ownership.unresolved")
                            Text("Reason: this geometry-only proposal is not calibrated ownership evidence.")
                            Text("Source strokes: \(ownership.sourceStrokeCount) · structural coverage: \(ownership.hasCompleteCoverage ? "complete" : "incomplete")")
                                .font(.callout)
                            if let exact = record.recognitionStrokes {
                                Text("Proposed groups—unverified")
                                    .font(.callout.weight(.semibold))
                                PersonalOwnershipProposalInkPreview(
                                    strokes: exact,
                                    groups: ownership.proposedGroups
                                )
                                .frame(height: 104)
                                .accessibilityIdentifier("learned.ownership.preview")
                                Text("Original recognition ink, display-only; colors follow the proposed source-index groups.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(proposalDescription(ownership.proposedGroups))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .accessibilityIdentifier("learned.ownership.proposals")
                            Text("Assessment \(ownership.version)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if let exclusion = row.exclusion {
                            Text(exclusion).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Text("Pair \(pairID.uuidString)\nGrouping \(report.groupingVersion ?? "not recorded")")
                .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .accessibilityIdentifier("learned.ownership")
    }

    private func proposalDescription(_ groups: [[Int]]) -> String {
        guard !groups.isEmpty else { return "Proposed groups: none" }
        return "Source indexes (zero-based): " + groups.enumerated().map { offset, indexes in
            "Group \(offset + 1) [\(indexes.map(String.init).joined(separator: ", "))]"
        }.joined(separator: " · ")
    }

    private func scorecardView(_ card: PersonalInkLearnedScorecard,
                               title: String = "Complete-chord results",
                               identifier: String = "learned.scorecard") -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text("Written: \(card.expectedChordCount.map(String.init) ?? "not recorded") · captured: \(card.capturedCount) · missing: \(card.missingCount)")
                .font(.callout)
            if let unresolved = card.ownershipUnresolvedCount {
                Text("Ownership unresolved: \(unresolved) · resolved: 0. Eligible unresolved attempts remain no-reads, not unsupported inputs.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if card.wholeChartDenominator == nil {
                Text("Limited comparison: \(card.eligibleCount) eligible captured targets. A whole-chart score is unavailable because the count, original input, grouping, labels, or fresh-ink checks are incomplete.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if card.unsupportedInputCount > 0 {
                Text("\(card.unsupportedInputCount) unsupported inputs are counted as failed ML reads.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if card.eligibleCount == 0 && card.wholeChartDenominator == nil {
                Text("No eligible fresh attempts to score. The saved predictions below remain available for inspection.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(card.eligibleCount == 0 && card.wholeChartDenominator == nil ? [] : card.scores) { score in
                VStack(alignment: .leading, spacing: 4) {
                    let denominator = card.wholeChartDenominator ?? card.eligibleCount
                    let absent = card.wholeChartDenominator == nil ? 0 : card.missingCount
                    Text("\(score.method.title): \(score.correct)/\(denominator) exact")
                        .fontWeight(.semibold)
                    Text("Wrong reads: \(score.wrongReads) · no reads: \(score.noReads + absent)")
                        .font(.caption)
                    if let reference = score.method.reference,
                       let gains = score.improvements, let harms = score.regressions {
                        Text("Compared with \(reference.title): \(gains) improvements · \(harms) regressions")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let wrong = score.trustedWrongReads, wrong > 0 {
                        Text("Wrong suggestions marked trusted: \(wrong)")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Exact includes the root, quality, extensions and slash bass. Missing chords remain in the written count. These are suggestions, not chords committed after review.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier(identifier)
    }
}

/// Display-only review of exact saved recognition input. Geometry is fit into
/// the preview without rewriting source points, times, bounds, or stroke order.
private struct PersonalOwnershipProposalInkPreview: View {
    let strokes: [InkStroke]
    let groups: [[Int]]

    var body: some View {
        Canvas { context, size in
            guard let transform = fitTransform(in: size) else { return }
            var groupByStroke: [Int: Int] = [:]
            for (group, indexes) in groups.enumerated() {
                for index in indexes where strokes.indices.contains(index) && groupByStroke[index] == nil {
                    groupByStroke[index] = group
                }
            }
            for (strokeIndex, stroke) in strokes.enumerated() where !stroke.points.isEmpty {
                let color = groupByStroke[strokeIndex].map(groupColor) ?? Color.secondary
                if stroke.points.count == 1, let point = stroke.points.first,
                   let location = transform.location(for: point) {
                    context.fill(
                        Path(ellipseIn: CGRect(x: location.x - 2, y: location.y - 2, width: 4, height: 4)),
                        with: .color(color)
                    )
                    continue
                }
                var path = Path()
                var isFirst = true
                for point in stroke.points {
                    guard let location = transform.location(for: point) else { continue }
                    if isFirst { path.move(to: location); isFirst = false }
                    else { path.addLine(to: location) }
                }
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
        .accessibilityLabel("Original recognition ink colored by unverified proposed groups")
    }

    private func groupColor(_ index: Int) -> Color {
        let hue = (Double(index) * 0.618_033_988_75).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.72, brightness: 0.82)
    }

    private func fitTransform(in size: CGSize) -> FitTransform? {
        let points = strokes.flatMap(\.points)
        guard !points.isEmpty, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        let width = maxX - minX, height = maxY - minY
        guard width.isFinite, height.isFinite else { return nil }
        let padding: CGFloat = 8
        let availableWidth = max(size.width - padding * 2, 1)
        let availableHeight = max(size.height - padding * 2, 1)
        let scale = min(availableWidth / CGFloat(max(width, 1)),
                        availableHeight / CGFloat(max(height, 1)))
        guard scale.isFinite, scale > 0 else { return nil }
        let drawnWidth = CGFloat(width) * scale
        let drawnHeight = CGFloat(height) * scale
        return FitTransform(
            minX: minX,
            minY: minY,
            scale: scale,
            offsetX: (size.width - drawnWidth) / 2,
            offsetY: (size.height - drawnHeight) / 2
        )
    }

    private struct FitTransform {
        let minX: Double
        let minY: Double
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        func location(for point: InkPoint) -> CGPoint? {
            guard point.x.isFinite, point.y.isFinite else { return nil }
            let x = offsetX + CGFloat(point.x - minX) * scale
            let y = offsetY + CGFloat(point.y - minY) * scale
            guard x.isFinite, y.isFinite else { return nil }
            return CGPoint(x: x, y: y)
        }
    }
}
#endif
