import CoreGraphics
import Foundation

struct ChordDraftPreviewDeviceDiagnosticBounds: Codable, Equatable {
    var minX: Double
    var minY: Double
    var width: Double
    var height: Double

    init(_ bounds: InkBounds) {
        self.init(
            minX: bounds.minX,
            minY: bounds.minY,
            width: bounds.width,
            height: bounds.height
        )
    }

    init(_ rect: CGRect) {
        self.init(
            minX: Double(rect.minX),
            minY: Double(rect.minY),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }
}

struct ChordDraftPreviewDeviceDiagnosticTarget: Codable, Equatable {
    var targetIndex: Int
    var measureID: UUID?
    var fraction: Double?
    var visualOrder: Double?
    var laneSystemIndex: Int?
    var laneFraction: Double?
    var strokeCount: Int
    var bounds: ChordDraftPreviewDeviceDiagnosticBounds?
    var strokeBounds: [ChordDraftPreviewDeviceDiagnosticBounds]?
    var inkStrokes: [InkStroke]? = nil
}

struct ChordDraftPreviewDeviceDiagnosticGlyphCandidate: Codable, Equatable {
    var text: String
    var confidence: Double
    var source: String
}

struct ChordDraftPreviewDeviceDiagnosticPayload: Codable, Equatable {
    var targetIndex: Int
    var measureID: UUID?
    var fraction: Double?
    var visualOrder: Double?
    var laneSystemIndex: Int?
    var laneFraction: Double?
    var strokeCount: Int
    var rawCandidates: [String]
    var supportedCandidates: [String]
    var matchText: String?
    var acceptedText: String?
    var action: String
    var reason: String
    var confidence: Double
    var closeRace: Bool
    var confidenceGap: Double?
    var topScores: [ChordInkCandidateScore]
    var glyphCandidateColumns: [[ChordDraftPreviewDeviceDiagnosticGlyphCandidate]]?
    var inkStrokes: [InkStroke]? = nil
}

struct ChordDraftPreviewDeviceDiagnosticReplacement: Codable, Equatable {
    var draftIndex: Int
    var anchorMeasureID: UUID
    var anchorFractionBucket: Int
    var previousDraftID: UUID?
    var newDraftID: UUID?
    var targetFraction: Double?
    var laneSystemIndex: Int?
    var laneFraction: Double?
    var previousPreviewText: String?
    var newPreviewText: String?
    var previousRenderable: Bool?
    var newRenderable: Bool?
    var bestCandidateText: String?
    var candidateTexts: [String]
    var strokeCount: Int
    var confidence: Double
}

struct LeadSheetChordInkRecognitionBatchTargetingDiagnostics: Codable, Equatable {
    static let version = "ink-grammar-guard-v7-2026-08-27"

    var version: String = Self.version
    var selectedRoute: String
    var draftBarlineClusterCount: Int
    var laneSequentialClusterCount: Int = 0
    var measureLaneClusterCount: Int
    var fallbackClusterCount: Int
    var selectedClusterCount: Int
}

struct ChordDraftPreviewDeviceDiagnosticEvent: Codable, Equatable {
    var timestamp: Date
    var stage: String
    var flow: String?
    var layoutStyle: String?
    var requestID: UUID?
    var sourceStrokeCount: Int?
    var recognitionStrokeCount: Int?
    var visibleStrokeCount: Int?
    var ignoredInvisibleStrokeCount: Int?
    var barlineCount: Int?
    var rawBatchTargetCount: Int?
    var boundedBatchTargetCount: Int?
    var skippedBatchTargetCount: Int?
    var targetingDiagnosticsVersion: String?
    var targetingRoute: String?
    var draftBarlineClusterCount: Int?
    var laneSequentialClusterCount: Int?
    var measureLaneClusterCount: Int?
    var fallbackClusterCount: Int?
    var selectedClusterCount: Int?
    var payloadCount: Int?
    var candidatePayloadCount: Int?
    var draftCount: Int?
    var unresolvedDraftCount: Int?
    var targets: [ChordDraftPreviewDeviceDiagnosticTarget]
    var payloads: [ChordDraftPreviewDeviceDiagnosticPayload]
    var replacements: [ChordDraftPreviewDeviceDiagnosticReplacement]

    init(
        timestamp: Date = .now,
        stage: String,
        flow: String? = nil,
        layoutStyle: String? = nil,
        requestID: UUID? = nil,
        sourceStrokeCount: Int? = nil,
        recognitionStrokeCount: Int? = nil,
        visibleStrokeCount: Int? = nil,
        ignoredInvisibleStrokeCount: Int? = nil,
        barlineCount: Int? = nil,
        rawBatchTargetCount: Int? = nil,
        boundedBatchTargetCount: Int? = nil,
        skippedBatchTargetCount: Int? = nil,
        targetingDiagnostics: LeadSheetChordInkRecognitionBatchTargetingDiagnostics? = nil,
        payloadCount: Int? = nil,
        candidatePayloadCount: Int? = nil,
        draftCount: Int? = nil,
        unresolvedDraftCount: Int? = nil,
        targets: [ChordDraftPreviewDeviceDiagnosticTarget] = [],
        payloads: [ChordDraftPreviewDeviceDiagnosticPayload] = [],
        replacements: [ChordDraftPreviewDeviceDiagnosticReplacement] = []
    ) {
        self.timestamp = timestamp
        self.stage = stage
        self.flow = flow
        self.layoutStyle = layoutStyle
        self.requestID = requestID
        self.sourceStrokeCount = sourceStrokeCount
        self.recognitionStrokeCount = recognitionStrokeCount
        self.visibleStrokeCount = visibleStrokeCount
        self.ignoredInvisibleStrokeCount = ignoredInvisibleStrokeCount
        self.barlineCount = barlineCount
        self.rawBatchTargetCount = rawBatchTargetCount
        self.boundedBatchTargetCount = boundedBatchTargetCount
        self.skippedBatchTargetCount = skippedBatchTargetCount
        self.targetingDiagnosticsVersion = targetingDiagnostics?.version
        self.targetingRoute = targetingDiagnostics?.selectedRoute
        self.draftBarlineClusterCount = targetingDiagnostics?.draftBarlineClusterCount
        self.laneSequentialClusterCount = targetingDiagnostics?.laneSequentialClusterCount
        self.measureLaneClusterCount = targetingDiagnostics?.measureLaneClusterCount
        self.fallbackClusterCount = targetingDiagnostics?.fallbackClusterCount
        self.selectedClusterCount = targetingDiagnostics?.selectedClusterCount
        self.payloadCount = payloadCount
        self.candidatePayloadCount = candidatePayloadCount
        self.draftCount = draftCount
        self.unresolvedDraftCount = unresolvedDraftCount
        self.targets = targets
        self.payloads = payloads
        self.replacements = replacements
    }
}

struct ChordDraftPreviewDeviceDiagnosticRecorder {
    let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func append(_ event: ChordDraftPreviewDeviceDiagnosticEvent) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try Self.encoder.encode(event) + Data([0x0A])
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func reset() throws {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    func loadEvents() throws -> [ChordDraftPreviewDeviceDiagnosticEvent] {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return try text
            .split(whereSeparator: \.isNewline)
            .map { line in
                try Self.decoder.decode(
                    ChordDraftPreviewDeviceDiagnosticEvent.self,
                    from: Data(line.utf8)
                )
            }
    }
}

extension ChordDraftPreviewDeviceDiagnosticRecorder {
    static func live(fileManager: FileManager = .default) -> ChordDraftPreviewDeviceDiagnosticRecorder {
        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let baseDirectory = applicationSupportURL.appendingPathComponent("iChart", isDirectory: true)
        return ChordDraftPreviewDeviceDiagnosticRecorder(
            url: baseDirectory.appendingPathComponent("chord-draft-preview-debug.jsonl"),
            fileManager: fileManager
        )
    }
}

private extension ChordDraftPreviewDeviceDiagnosticRecorder {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

#if canImport(UIKit)
enum ChordDraftPreviewDeviceDiagnostics {
    static func reset() {
        #if DEBUG
        do {
            let recorder = ChordDraftPreviewDeviceDiagnosticRecorder.live()
            try recorder.reset()
            try recorder.append(ChordDraftPreviewDeviceDiagnosticEvent(stage: "reset"))
        } catch {
            print("iChart chord draft preview diagnostic error: \(error)")
        }
        #endif
    }

    static func recordTargeting(
        flow: ChordInkRecognitionFlow,
        sourceStrokeCount: Int,
        recognitionStrokeCount: Int,
        visibleStrokeCount: Int,
        ignoredInvisibleStrokeCount: Int,
        barlineCount: Int,
        rawBatchTargets: [LeadSheetChordInkRecognitionBatchTarget],
        boundedBatchTargets: [LeadSheetChordInkRecognitionBatchTarget],
        targetingDiagnostics: LeadSheetChordInkRecognitionBatchTargetingDiagnostics? = nil,
        layoutStyle: ChartLayoutStyle? = nil
    ) {
        #if DEBUG
        append(
            ChordDraftPreviewDeviceDiagnosticEvent(
                stage: "targeting",
                flow: flow.telemetryValue,
                layoutStyle: layoutStyle?.rawValue,
                sourceStrokeCount: sourceStrokeCount,
                recognitionStrokeCount: recognitionStrokeCount,
                visibleStrokeCount: visibleStrokeCount,
                ignoredInvisibleStrokeCount: ignoredInvisibleStrokeCount,
                barlineCount: barlineCount,
                rawBatchTargetCount: rawBatchTargets.count,
                boundedBatchTargetCount: boundedBatchTargets.count,
                skippedBatchTargetCount: rawBatchTargets.count - boundedBatchTargets.count,
                targetingDiagnostics: targetingDiagnostics,
                targets: boundedBatchTargets.enumerated().map { index, target in
                    diagnosticTarget(index: index, target: target)
                }
            )
        )
        #endif
    }

    static func recordSingleTarget(
        flow: ChordInkRecognitionFlow,
        request: ChordInkRecognitionSessionRequest,
        layoutStyle: ChartLayoutStyle? = nil
    ) {
        #if DEBUG
        append(
            ChordDraftPreviewDeviceDiagnosticEvent(
                stage: "single_target",
                flow: flow.telemetryValue,
                layoutStyle: layoutStyle?.rawValue,
                requestID: request.requestID,
                recognitionStrokeCount: request.strokes.count,
                targets: [
                    ChordDraftPreviewDeviceDiagnosticTarget(
                        targetIndex: 0,
                        measureID: request.target.measureID,
                        fraction: request.target.fraction,
                        visualOrder: request.visualOrder,
                        laneSystemIndex: request.laneLocation?.systemIndex,
                        laneFraction: request.laneLocation?.fraction,
                        strokeCount: request.strokes.count,
                        bounds: bounds(for: request.strokes),
                        strokeBounds: strokeBounds(for: request.strokes),
                        inkStrokes: request.strokes
                    )
                ]
            )
        )
        #endif
    }

    static func recordNoTarget(
        flow: ChordInkRecognitionFlow,
        stage: String,
        recognitionStrokeCount: Int,
        rawBatchTargetCount: Int,
        boundedBatchTargetCount: Int,
        layoutStyle: ChartLayoutStyle? = nil
    ) {
        #if DEBUG
        append(
            ChordDraftPreviewDeviceDiagnosticEvent(
                stage: stage,
                flow: flow.telemetryValue,
                layoutStyle: layoutStyle?.rawValue,
                recognitionStrokeCount: recognitionStrokeCount,
                rawBatchTargetCount: rawBatchTargetCount,
                boundedBatchTargetCount: boundedBatchTargetCount
            )
        )
        #endif
    }

    static func recordPayloads(
        _ payloads: [ChordInkRecognitionProposalPayload],
        flow: ChordInkRecognitionFlow,
        stage: String,
        layoutStyle: ChartLayoutStyle? = nil
    ) {
        #if DEBUG
        append(
            ChordDraftPreviewDeviceDiagnosticEvent(
                stage: stage,
                flow: flow.telemetryValue,
                layoutStyle: layoutStyle?.rawValue,
                requestID: payloads.first?.requestID,
                payloadCount: payloads.count,
                candidatePayloadCount: payloads.filter { !$0.result.rawCandidates.isEmpty }.count,
                payloads: payloads.enumerated().map { index, payload in
                    diagnosticPayload(index: index, payload: payload)
                }
            )
        )
        #endif
    }

    static func recordPreviewReplacement(
        previousState: ChordPreviewState,
        inputs: [ChordInkDraftInput],
        updatedState: ChordPreviewState,
        layoutStyle: ChartLayoutStyle? = nil
    ) {
        #if DEBUG
        let previousDraftsByAnchor = Dictionary(
            previousState.draftChords.map { ($0.anchor, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let replacements = updatedState.draftChords.enumerated().map { index, draft in
            let previousDraft = previousDraftsByAnchor[draft.anchor]
            return ChordDraftPreviewDeviceDiagnosticReplacement(
                draftIndex: index,
                anchorMeasureID: draft.anchor.measureID,
                anchorFractionBucket: draft.anchor.fractionBucket,
                previousDraftID: previousDraft?.id,
                newDraftID: draft.id,
                targetFraction: draft.targetFraction,
                laneSystemIndex: draft.laneLocation?.systemIndex,
                laneFraction: draft.laneLocation?.fraction,
                previousPreviewText: previousDraft?.previewText,
                newPreviewText: draft.previewText,
                previousRenderable: previousDraft?.isRenderable,
                newRenderable: draft.isRenderable,
                bestCandidateText: draft.bestCandidateText,
                candidateTexts: draft.candidateTexts,
                strokeCount: draft.strokeCount,
                confidence: draft.confidence
            )
        }

        append(
            ChordDraftPreviewDeviceDiagnosticEvent(
                stage: "preview_replace",
                layoutStyle: layoutStyle?.rawValue,
                payloadCount: inputs.count,
                draftCount: updatedState.draftChords.count,
                unresolvedDraftCount: updatedState.unresolvedChordCount,
                replacements: replacements
            )
        )
        #endif
    }
}

private extension ChordDraftPreviewDeviceDiagnostics {
    #if DEBUG
    static func append(_ event: ChordDraftPreviewDeviceDiagnosticEvent) {
        do {
            try ChordDraftPreviewDeviceDiagnosticRecorder.live().append(event)
            print(compactSummary(for: event))
        } catch {
            print("iChart chord draft preview diagnostic error: \(error)")
        }
    }

    static func diagnosticTarget(
        index: Int,
        target: LeadSheetChordInkRecognitionBatchTarget
    ) -> ChordDraftPreviewDeviceDiagnosticTarget {
        ChordDraftPreviewDeviceDiagnosticTarget(
            targetIndex: index,
            measureID: target.measureID,
            fraction: target.fraction,
            visualOrder: target.visualOrder,
            laneSystemIndex: target.laneLocation?.systemIndex,
            laneFraction: target.laneLocation?.fraction,
            strokeCount: target.strokes.count,
            bounds: bounds(for: target.strokes),
            strokeBounds: strokeBounds(for: target.strokes),
            inkStrokes: target.strokes
        )
    }

    static func diagnosticPayload(
        index: Int,
        payload: ChordInkRecognitionProposalPayload
    ) -> ChordDraftPreviewDeviceDiagnosticPayload {
        let decision = ChordInkRecognitionPolicy.decision(for: payload.result)
        return ChordDraftPreviewDeviceDiagnosticPayload(
            targetIndex: index,
            measureID: payload.target.measureID,
            fraction: payload.target.fraction,
            visualOrder: payload.visualOrder,
            laneSystemIndex: payload.laneLocation?.systemIndex,
            laneFraction: payload.laneLocation?.fraction,
            strokeCount: payload.timing.strokeCount,
            rawCandidates: Array(payload.result.rawCandidates.prefix(12)),
            supportedCandidates: Array(ChordInkRenderResolutionPolicy.candidateTexts(for: payload.result).prefix(8)),
            matchText: payload.result.match?.displayText,
            acceptedText: decision.acceptedText,
            action: decision.action.rawValue,
            reason: decision.reason,
            confidence: payload.result.confidence,
            closeRace: decision.isCloseRace,
            confidenceGap: decision.confidenceGap,
            topScores: Array(payload.result.candidateScores.prefix(8)),
            glyphCandidateColumns: payload.result.glyphCandidates.map { candidates in
                candidates.prefix(8).map { candidate in
                    ChordDraftPreviewDeviceDiagnosticGlyphCandidate(
                        text: candidate.text,
                        confidence: candidate.confidence,
                        source: candidate.source.rawValue
                    )
                }
            },
            inkStrokes: payload.strokes
        )
    }

    static func bounds(for strokes: [InkStroke]) -> ChordDraftPreviewDeviceDiagnosticBounds? {
        guard !strokes.isEmpty else {
            return nil
        }

        return ChordDraftPreviewDeviceDiagnosticBounds(
            InkBounds.enclosing(strokes.map(\.bounds))
        )
    }

    static func strokeBounds(for strokes: [InkStroke]) -> [ChordDraftPreviewDeviceDiagnosticBounds] {
        strokes.map { stroke in
            ChordDraftPreviewDeviceDiagnosticBounds(stroke.bounds)
        }
    }

    static func compactSummary(for event: ChordDraftPreviewDeviceDiagnosticEvent) -> String {
        switch event.stage {
        case "targeting":
            return "iChart chord draft debug: targeting flow=\(event.flow ?? "none") layout=\(event.layoutStyle ?? "unknown") source=\(event.sourceStrokeCount ?? -1) recognition=\(event.recognitionStrokeCount ?? -1) barlines=\(event.barlineCount ?? -1) targets=\(event.boundedBatchTargetCount ?? -1)\n"
        case "single_target":
            let target = event.targets.first
            return "iChart chord draft debug: single_target layout=\(event.layoutStyle ?? "unknown") strokes=\(target?.strokeCount ?? -1) fraction=\(target?.fraction ?? -1)\n"
        case "finish_single", "finish_batch":
            let best = event.payloads.map { payload in
                payload.acceptedText ?? payload.matchText ?? payload.supportedCandidates.first ?? "?"
            }.joined(separator: "|")
            return "iChart chord draft debug: \(event.stage) layout=\(event.layoutStyle ?? "unknown") payloads=\(event.payloadCount ?? -1) best=\(best)\n"
        case "preview_replace":
            let texts = event.replacements.map { replacement in
                "\(replacement.previousPreviewText ?? "?")->\(replacement.newPreviewText ?? "?")"
            }.joined(separator: "|")
            return "iChart chord draft debug: preview_replace layout=\(event.layoutStyle ?? "unknown") drafts=\(event.draftCount ?? -1) unresolved=\(event.unresolvedDraftCount ?? -1) \(texts)\n"
        default:
            return "iChart chord draft debug: \(event.stage)\n"
        }
    }
    #endif
}
#endif
