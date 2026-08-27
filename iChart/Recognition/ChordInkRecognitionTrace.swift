import Foundation

struct ChordInkRecognitionTrace: Codable, Equatable {
    var events: [ChordDraftPreviewDeviceDiagnosticEvent]

    init(events: [ChordDraftPreviewDeviceDiagnosticEvent]) {
        self.events = events
    }

    var passes: [ChordInkRecognitionTracePass] {
        ChordInkRecognitionTracePassBuilder.passes(from: events)
    }

    var stabilityIssues: [ChordInkRecognitionTraceStabilityIssue] {
        previewRegressionIssues()
            + batchSupportedReadRegressionIssues()
            + targetAbsorptionRegressionIssues()
    }

    var observations: [ChordInkRecognitionTraceObservation] {
        closeRacePrimaryCandidateChangeObservations()
    }

    var replayableTargets: [ChordInkRecognitionTraceReplayableTarget] {
        passes.enumerated().flatMap { passIndex, pass in
            let payloadsByTargetIndex = Dictionary(
                pass.payloads.map { ($0.targetIndex, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            return pass.targets.compactMap { target -> ChordInkRecognitionTraceReplayableTarget? in
                let payload = payloadsByTargetIndex[target.targetIndex]
                let strokes: [InkStroke]
                if let payloadStrokes = payload?.inkStrokes, !payloadStrokes.isEmpty {
                    strokes = payloadStrokes
                } else {
                    strokes = target.inkStrokes ?? []
                }
                guard !strokes.isEmpty else {
                    return nil
                }

                return ChordInkRecognitionTraceReplayableTarget(
                    passIndex: passIndex,
                    passKind: pass.kind,
                    targetIndex: target.targetIndex,
                    measureID: target.measureID ?? payload?.measureID,
                    fraction: target.fraction ?? payload?.fraction,
                    visualOrder: target.visualOrder ?? payload?.visualOrder,
                    recognizedDisplayText: payload?.acceptedText ?? payload?.matchText ?? payload?.supportedCandidates.first,
                    action: payload?.action,
                    reason: payload?.reason,
                    supportedCandidates: payload?.supportedCandidates ?? [],
                    topScores: payload?.topScores ?? [],
                    strokes: strokes
                )
            }
        }
    }

    func fixtureDocument(
        passIndex: Int,
        targetIndex: Int,
        expectedDisplayText: String,
        name: String? = nil
    ) throws -> InkFixtureDocument? {
        guard let target = replayableTargets.first(where: {
            $0.passIndex == passIndex && $0.targetIndex == targetIndex
        }) else {
            return nil
        }

        return try target.fixtureDocument(
            expectedDisplayText: expectedDisplayText,
            name: name
        )
    }

    func fixtureJSONString(
        passIndex: Int,
        targetIndex: Int,
        expectedDisplayText: String,
        name: String? = nil
    ) throws -> String? {
        guard let target = replayableTargets.first(where: {
            $0.passIndex == passIndex && $0.targetIndex == targetIndex
        }) else {
            return nil
        }

        return try target.fixtureJSONString(
            expectedDisplayText: expectedDisplayText,
            name: name
        )
    }

    private func previewRegressionIssues() -> [ChordInkRecognitionTraceStabilityIssue] {
        passes.enumerated().flatMap { passIndex, pass in
            pass.replacements.compactMap { replacement in
                guard replacement.previousRenderable == true,
                      replacement.previousPreviewText != nil,
                      replacement.newRenderable != true || replacement.newPreviewText == nil else {
                    return nil
                }

                return ChordInkRecognitionTraceStabilityIssue(
                    kind: .previewDroppedRenderableRead,
                    passIndex: passIndex,
                    targetIndex: replacement.draftIndex,
                    previousText: replacement.previousPreviewText,
                    newText: replacement.newPreviewText,
                    details: "Preview replacement dropped a previously renderable chord read."
                )
            }
        }
    }

    private func batchSupportedReadRegressionIssues() -> [ChordInkRecognitionTraceStabilityIssue] {
        var latestReadableTargetByFingerprint = [ChordInkRecognitionTraceTargetFingerprint: ChordInkRecognitionTracePayloadSnapshot]()
        var issues = [ChordInkRecognitionTraceStabilityIssue]()

        for (passIndex, pass) in passes.enumerated() {
            let payloadsByTargetIndex = Dictionary(
                pass.payloads.map { ($0.targetIndex, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for target in pass.targets {
                guard let fingerprint = ChordInkRecognitionTraceTargetFingerprint(target: target),
                      let payload = payloadsByTargetIndex[target.targetIndex] else {
                    continue
                }

                if pass.kind == .batch,
                   let previousPayload = latestReadableTargetByFingerprint[fingerprint],
                   !previousPayload.supportedCandidates.isEmpty,
                   payload.supportedCandidates.isEmpty {
                    issues.append(
                        ChordInkRecognitionTraceStabilityIssue(
                            kind: .batchTargetLostSupportedRead,
                            passIndex: passIndex,
                            targetIndex: target.targetIndex,
                            previousText: previousPayload.bestSupportedText,
                            newText: payload.rawCandidates.first,
                            details: "Batch recognition lost supported candidates for a previously readable target with the same stroke fingerprint."
                        )
                    )
                }

                if !payload.supportedCandidates.isEmpty {
                    latestReadableTargetByFingerprint[fingerprint] = ChordInkRecognitionTracePayloadSnapshot(payload: payload)
                }
            }
        }

        return issues
    }

    private func targetAbsorptionRegressionIssues() -> [ChordInkRecognitionTraceStabilityIssue] {
        var latestReadableTargetBySlot = [ChordInkRecognitionTraceTargetSequenceSlot: ChordInkRecognitionTraceTargetAbsorptionSnapshot]()
        var issues = [ChordInkRecognitionTraceStabilityIssue]()
        let resetTimestamps = events
            .filter { $0.stage == "reset" }
            .map(\.timestamp)
            .sorted()
        var nextResetIndex = 0

        for (passIndex, pass) in passes.enumerated() {
            while nextResetIndex < resetTimestamps.count,
                  let passTimestamp = pass.startTimestamp,
                  resetTimestamps[nextResetIndex] <= passTimestamp {
                latestReadableTargetBySlot.removeAll()
                nextResetIndex += 1
            }

            let payloadsByTargetIndex = Dictionary(
                pass.payloads.map { ($0.targetIndex, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for target in pass.targets {
                guard let payload = payloadsByTargetIndex[target.targetIndex],
                      let slot = ChordInkRecognitionTraceTargetSequenceSlot(target: target, payload: payload),
                      let snapshot = ChordInkRecognitionTraceTargetAbsorptionSnapshot(target: target, payload: payload) else {
                    continue
                }

                if let previous = latestReadableTargetBySlot[slot],
                   let previousText = previous.bestSupportedText,
                   let newText = snapshot.bestSupportedText,
                   previousText != newText,
                   snapshot.absorbs(previous) {
                    issues.append(
                        ChordInkRecognitionTraceStabilityIssue(
                            kind: .targetAbsorbedPreviouslyReadableRead,
                            passIndex: passIndex,
                            targetIndex: target.targetIndex,
                            previousText: previousText,
                            newText: newText,
                            details: "Target absorbed a previously readable chord stroke fingerprint plus detached right-side ink before changing the read."
                        )
                    )
                }

                if snapshot.bestSupportedText != nil {
                    latestReadableTargetBySlot[slot] = snapshot
                }
            }

            if pass.previewEvent?.draftCount == 0 {
                latestReadableTargetBySlot.removeAll()
            }
        }

        return issues
    }

    private func closeRacePrimaryCandidateChangeObservations() -> [ChordInkRecognitionTraceObservation] {
        var latestPayloadBySlot = [ChordInkRecognitionTraceTargetSlot: ChordInkRecognitionTracePayloadSnapshot]()
        var observations = [ChordInkRecognitionTraceObservation]()
        let resetTimestamps = events
            .filter { $0.stage == "reset" }
            .map(\.timestamp)
            .sorted()
        var nextResetIndex = 0

        for (passIndex, pass) in passes.enumerated() {
            while nextResetIndex < resetTimestamps.count,
                  let passTimestamp = pass.startTimestamp,
                  resetTimestamps[nextResetIndex] <= passTimestamp {
                latestPayloadBySlot.removeAll()
                nextResetIndex += 1
            }

            let payloadsByTargetIndex = Dictionary(
                pass.payloads.map { ($0.targetIndex, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for target in pass.targets {
                guard let payload = payloadsByTargetIndex[target.targetIndex],
                      let slot = ChordInkRecognitionTraceTargetSlot(target: target, payload: payload) else {
                    continue
                }

                let snapshot = ChordInkRecognitionTracePayloadSnapshot(payload: payload)
                if let previousPayload = latestPayloadBySlot[slot],
                   let previousText = previousPayload.bestSupportedText,
                   let newText = snapshot.bestSupportedText,
                   previousText != newText,
                   previousPayload.isCloseRaceConfirmation,
                   snapshot.isCloseRaceConfirmation,
                   previousPayload.hasSupportedCandidateOverlap(with: snapshot) {
                    observations.append(
                        ChordInkRecognitionTraceObservation(
                            kind: .closeRacePrimaryCandidateChanged,
                            passIndex: passIndex,
                            targetIndex: target.targetIndex,
                            previousText: previousText,
                            newText: newText,
                            details: Self.closeRaceCandidateChangeDetails(
                                previousText: previousText,
                                newText: newText,
                                previousPayload: previousPayload,
                                newPayload: snapshot
                            )
                        )
                    )
                }

                if snapshot.bestSupportedText != nil {
                    latestPayloadBySlot[slot] = snapshot
                }
            }

            if pass.previewEvent?.draftCount == 0 {
                latestPayloadBySlot.removeAll()
            }
        }

        return observations
    }

    private static func closeRaceCandidateChangeDetails(
        previousText: String,
        newText: String,
        previousPayload: ChordInkRecognitionTracePayloadSnapshot,
        newPayload: ChordInkRecognitionTracePayloadSnapshot
    ) -> String {
        let previousRoot = rootDescriptor(for: previousText) ?? "unknown"
        let newRoot = rootDescriptor(for: newText) ?? "unknown"
        return "Close-race confirmation primary candidate changed from \(previousText) to \(newText) for the same target slot; root descriptor \(previousRoot) -> \(newRoot), previous gap \(previousPayload.confidenceGapText), new gap \(newPayload.confidenceGapText)."
    }

    private static func rootDescriptor(for text: String) -> String? {
        guard let symbol = ChordRecognitionCompendium.match(text)?.symbol,
              symbol.kind == .rooted else {
            return nil
        }

        return "\(symbol.root.rawValue)\(symbol.accidental.rawValue)"
    }
}

struct ChordInkRecognitionTracePass: Codable, Equatable {
    var kind: ChordInkRecognitionTracePassKind
    var targetEvent: ChordDraftPreviewDeviceDiagnosticEvent?
    var payloadEvent: ChordDraftPreviewDeviceDiagnosticEvent?
    var previewEvent: ChordDraftPreviewDeviceDiagnosticEvent?

    var targets: [ChordDraftPreviewDeviceDiagnosticTarget] {
        targetEvent?.targets ?? []
    }

    var payloads: [ChordDraftPreviewDeviceDiagnosticPayload] {
        payloadEvent?.payloads ?? []
    }

    var replacements: [ChordDraftPreviewDeviceDiagnosticReplacement] {
        previewEvent?.replacements ?? []
    }

    fileprivate var startTimestamp: Date? {
        targetEvent?.timestamp ?? payloadEvent?.timestamp ?? previewEvent?.timestamp
    }
}

enum ChordInkRecognitionTracePassKind: String, Codable, Equatable {
    case singleTarget
    case batch
}

struct ChordInkRecognitionTraceStabilityIssue: Codable, Equatable {
    var kind: ChordInkRecognitionTraceStabilityIssueKind
    var passIndex: Int
    var targetIndex: Int
    var previousText: String?
    var newText: String?
    var details: String
}

enum ChordInkRecognitionTraceStabilityIssueKind: String, Codable, Equatable {
    case previewDroppedRenderableRead
    case batchTargetLostSupportedRead
    case targetAbsorbedPreviouslyReadableRead
}

struct ChordInkRecognitionTraceObservation: Codable, Equatable {
    var kind: ChordInkRecognitionTraceObservationKind
    var passIndex: Int
    var targetIndex: Int
    var previousText: String?
    var newText: String?
    var details: String
}

enum ChordInkRecognitionTraceObservationKind: String, Codable, Equatable {
    case closeRacePrimaryCandidateChanged
}

struct ChordInkRecognitionTraceReplayableTarget: Codable, Equatable {
    var passIndex: Int
    var passKind: ChordInkRecognitionTracePassKind
    var targetIndex: Int
    var measureID: UUID?
    var fraction: Double?
    var visualOrder: Double?
    var recognizedDisplayText: String?
    var action: String?
    var reason: String?
    var supportedCandidates: [String]
    var topScores: [ChordInkCandidateScore]
    var strokes: [InkStroke]

    func fixtureDocument(
        expectedDisplayText: String,
        name: String? = nil
    ) throws -> InkFixtureDocument {
        try ChordInkFixtureExporter.fixtureDocument(
            name: name,
            expectedDisplayText: expectedDisplayText,
            strokes: strokes
        )
    }

    func fixtureJSONString(
        expectedDisplayText: String,
        name: String? = nil
    ) throws -> String {
        try ChordInkFixtureExporter.fixtureJSONString(
            name: name,
            expectedDisplayText: expectedDisplayText,
            strokes: strokes
        )
    }
}

struct ChordInkRecognitionTraceTargetFingerprint: Codable, Hashable {
    var strokeCount: Int
    var quantizedBounds: [QuantizedTraceBounds]

    init?(target: ChordDraftPreviewDeviceDiagnosticTarget) {
        let sourceBounds = target.strokeBounds?.isEmpty == false
            ? target.strokeBounds ?? []
            : target.bounds.map { [$0] } ?? []
        guard !sourceBounds.isEmpty else {
            return nil
        }

        strokeCount = target.strokeCount
        quantizedBounds = sourceBounds.map(QuantizedTraceBounds.init(bounds:))
    }
}

struct QuantizedTraceBounds: Codable, Hashable {
    var minX: Int
    var minY: Int
    var width: Int
    var height: Int

    init(bounds: ChordDraftPreviewDeviceDiagnosticBounds) {
        minX = Self.quantize(bounds.minX)
        minY = Self.quantize(bounds.minY)
        width = Self.quantize(bounds.width)
        height = Self.quantize(bounds.height)
    }

    private static func quantize(_ value: Double) -> Int {
        Int((value * 2).rounded())
    }
}

private struct ChordInkRecognitionTracePayloadSnapshot: Equatable {
    var targetIndex: Int
    var rawCandidates: [String]
    var supportedCandidates: [String]
    var matchText: String?
    var acceptedText: String?
    var action: String
    var closeRace: Bool
    var confidenceGap: Double?
    var topGlyphText: String?

    init(payload: ChordDraftPreviewDeviceDiagnosticPayload) {
        targetIndex = payload.targetIndex
        rawCandidates = payload.rawCandidates
        supportedCandidates = payload.supportedCandidates
        matchText = payload.matchText
        acceptedText = payload.acceptedText
        action = payload.action
        closeRace = payload.closeRace
        confidenceGap = payload.confidenceGap
        topGlyphText = payload.glyphCandidateColumns?.first?.first?.text
    }

    var bestSupportedText: String? {
        acceptedText ?? matchText ?? supportedCandidates.first
    }

    var isCloseRaceConfirmation: Bool {
        action == ChordInkRecognitionAction.confirm.rawValue && closeRace
    }

    var confidenceGapText: String {
        confidenceGap.map { String(format: "%.4f", $0) } ?? "unknown"
    }

    func hasSupportedCandidateOverlap(with other: ChordInkRecognitionTracePayloadSnapshot) -> Bool {
        let supported = Set(supportedCandidates)
        return !supported.isDisjoint(with: other.supportedCandidates)
    }
}

private struct ChordInkRecognitionTraceTargetAbsorptionSnapshot: Equatable {
    private static let minimumDetachedAddedStrokeGap = 24.0

    var targetIndex: Int
    var strokeBounds: [ChordDraftPreviewDeviceDiagnosticBounds]
    var quantizedStrokeBounds: Set<QuantizedTraceBounds>
    var payload: ChordInkRecognitionTracePayloadSnapshot

    init?(
        target: ChordDraftPreviewDeviceDiagnosticTarget,
        payload: ChordDraftPreviewDeviceDiagnosticPayload
    ) {
        let sourceBounds = target.strokeBounds?.isEmpty == false
            ? target.strokeBounds ?? []
            : target.bounds.map { [$0] } ?? []
        guard !sourceBounds.isEmpty else {
            return nil
        }

        targetIndex = target.targetIndex
        strokeBounds = sourceBounds
        quantizedStrokeBounds = Set(sourceBounds.map(QuantizedTraceBounds.init(bounds:)))
        self.payload = ChordInkRecognitionTracePayloadSnapshot(payload: payload)
    }

    var bestSupportedText: String? {
        payload.bestSupportedText
    }

    func absorbs(_ previous: ChordInkRecognitionTraceTargetAbsorptionSnapshot) -> Bool {
        guard strokeBounds.count > previous.strokeBounds.count,
              quantizedStrokeBounds.isSuperset(of: previous.quantizedStrokeBounds),
              let addedStrokeGap = minimumAddedStrokeGap(after: previous) else {
            return false
        }

        return addedStrokeGap >= Self.minimumDetachedAddedStrokeGap
    }

    private func minimumAddedStrokeGap(after previous: ChordInkRecognitionTraceTargetAbsorptionSnapshot) -> Double? {
        let previousBounds = previous.quantizedStrokeBounds
        let addedBounds = strokeBounds.filter { bounds in
            !previousBounds.contains(QuantizedTraceBounds(bounds: bounds))
        }
        guard let previousMaxX = previous.strokeBounds.map(\.maxX).max(),
              let addedMinX = addedBounds.map(\.minX).min() else {
            return nil
        }

        return addedMinX - previousMaxX
    }
}

private struct ChordInkRecognitionTraceTargetSequenceSlot: Codable, Hashable {
    var targetIndex: Int
    var measureID: UUID?
    var laneSystemIndex: Int?

    init?(
        target: ChordDraftPreviewDeviceDiagnosticTarget,
        payload: ChordDraftPreviewDeviceDiagnosticPayload
    ) {
        targetIndex = target.targetIndex
        measureID = target.measureID ?? payload.measureID
        laneSystemIndex = target.laneSystemIndex ?? payload.laneSystemIndex

        guard measureID != nil || laneSystemIndex != nil else {
            return nil
        }
    }
}

private struct ChordInkRecognitionTraceTargetSlot: Codable, Hashable {
    var targetIndex: Int
    var measureID: UUID?
    var laneSystemIndex: Int?
    var laneFractionBucket: Int?

    init?(
        target: ChordDraftPreviewDeviceDiagnosticTarget,
        payload: ChordDraftPreviewDeviceDiagnosticPayload
    ) {
        targetIndex = target.targetIndex
        measureID = target.measureID ?? payload.measureID
        laneSystemIndex = target.laneSystemIndex ?? payload.laneSystemIndex
        laneFractionBucket = Self.bucket(
            target.laneFraction
                ?? payload.laneFraction
                ?? target.fraction
                ?? payload.fraction
                ?? target.visualOrder
                ?? payload.visualOrder
        )

        guard measureID != nil || laneSystemIndex != nil || laneFractionBucket != nil else {
            return nil
        }
    }

    private static func bucket(_ fraction: Double?) -> Int? {
        fraction.map { Int(($0 * 20).rounded()) }
    }
}

private extension ChordDraftPreviewDeviceDiagnosticBounds {
    var maxX: Double {
        minX + width
    }
}

private enum ChordInkRecognitionTracePassBuilder {
    static func passes(from events: [ChordDraftPreviewDeviceDiagnosticEvent]) -> [ChordInkRecognitionTracePass] {
        var passes = [ChordInkRecognitionTracePass]()
        var pendingPass: ChordInkRecognitionTracePass?

        func finishPendingPass() {
            if let pass = pendingPass {
                passes.append(pass)
                pendingPass = nil
            }
        }

        for event in events {
            switch event.stage {
            case "single_target":
                finishPendingPass()
                pendingPass = ChordInkRecognitionTracePass(
                    kind: .singleTarget,
                    targetEvent: event,
                    payloadEvent: nil,
                    previewEvent: nil
                )
            case "targeting" where (event.boundedBatchTargetCount ?? event.targets.count) > 0:
                finishPendingPass()
                pendingPass = ChordInkRecognitionTracePass(
                    kind: .batch,
                    targetEvent: event,
                    payloadEvent: nil,
                    previewEvent: nil
                )
            case "finish_single":
                attachPayloadEvent(event, kind: .singleTarget, pendingPass: &pendingPass, passes: &passes)
            case "finish_batch":
                attachPayloadEvent(event, kind: .batch, pendingPass: &pendingPass, passes: &passes)
            case "preview_replace":
                guard pendingPass != nil else {
                    continue
                }

                pendingPass?.previewEvent = event
                finishPendingPass()
            default:
                continue
            }
        }

        finishPendingPass()
        return passes
    }

    private static func attachPayloadEvent(
        _ event: ChordDraftPreviewDeviceDiagnosticEvent,
        kind: ChordInkRecognitionTracePassKind,
        pendingPass: inout ChordInkRecognitionTracePass?,
        passes: inout [ChordInkRecognitionTracePass]
    ) {
        if let currentPass = pendingPass,
           currentPass.kind != kind {
            passes.append(currentPass)
            pendingPass = nil
        }

        if pendingPass == nil {
            pendingPass = ChordInkRecognitionTracePass(
                kind: kind,
                targetEvent: nil,
                payloadEvent: event,
                previewEvent: nil
            )
        } else {
            pendingPass?.payloadEvent = event
        }
    }
}
