#if canImport(UIKit)
import CoreGraphics
import Foundation

struct ChordInkRecognitionSessionRequest {
    var requestID: UUID
    var scheduledAt: Date
    var requestedDelay: TimeInterval
    var strokes: [InkStroke]
    var drawingData: Data
    var target: (measureID: UUID, fraction: Double)
    var visualOrder: Double? = nil
    var laneLocation: ChordInkDraftLaneLocation? = nil
    var layoutPageSize: CGSize? = nil
    var options: ChordInkRecognitionOptions
    var ocrImageProvider: () -> CGImage?
}

struct ChordInkRecognitionProposalPayload {
    var requestID: UUID
    var result: ChordInkRecognitionResult
    var drawingData: Data
    var target: (measureID: UUID, fraction: Double)
    var visualOrder: Double? = nil
    var laneLocation: ChordInkDraftLaneLocation? = nil
    var layoutPageSize: CGSize? = nil
    var timing: ChordInkRecognitionTiming
}

final class ChordInkRecognitionSession {
    private let queue: DispatchQueue
    private let recognizer: ChordInkRecognizing
    private let ocrCandidateProvider: ChordOCRCandidateProviding?

    init(
        queue: DispatchQueue,
        recognizer: ChordInkRecognizing,
        ocrCandidateProvider: ChordOCRCandidateProviding?
    ) {
        self.queue = queue
        self.recognizer = recognizer
        self.ocrCandidateProvider = ocrCandidateProvider
    }

    func start(
        request: ChordInkRecognitionSessionRequest,
        completion: @escaping (ChordInkRecognitionProposalPayload) -> Void
    ) {
        let recognizer = recognizer
        let ocrCandidateProvider = ocrCandidateProvider
        queue.async {
            let recognitionStartedAt = Date()
            var result = recognizer.recognize(
                strokes: request.strokes,
                options: request.options
            )
            let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
            if Self.shouldRequestOCR(
                options: request.options,
                result: result,
                primaryDecision: primaryDecision
            ),
               let ocrCandidateProvider,
               let ocrImage = request.ocrImageProvider() {
                let ocrStartedAt = Date()
                let ocrCandidates = ocrCandidateProvider.recognizeCandidates(in: ocrImage)
                result = Self.result(
                    result,
                    byApplyingOCRCandidates: ocrCandidates,
                    options: request.options
                )
                result.metrics.ocrMilliseconds = Date().timeIntervalSince(ocrStartedAt) * 1_000
            }

            let recognitionFinishedAt = Date()
            let payload = ChordInkRecognitionProposalPayload(
                requestID: request.requestID,
                result: result,
                drawingData: request.drawingData,
                target: request.target,
                visualOrder: request.visualOrder,
                laneLocation: request.laneLocation,
                layoutPageSize: request.layoutPageSize,
                timing: ChordInkRecognitionTiming(
                    scheduledAt: request.scheduledAt,
                    requestedDelay: request.requestedDelay,
                    recognitionStartedAt: recognitionStartedAt,
                    recognitionFinishedAt: recognitionFinishedAt,
                    strokeCount: request.strokes.count,
                    ocrCandidateCount: result.ocrCandidates?.count ?? 0
                )
            )

            DispatchQueue.main.async {
                completion(payload)
            }
        }
    }

    func startBatch(
        requests: [ChordInkRecognitionSessionRequest],
        completion: @escaping ([ChordInkRecognitionProposalPayload]) -> Void
    ) {
        guard !requests.isEmpty else {
            DispatchQueue.main.async {
                completion([])
            }
            return
        }

        let recognizer = recognizer
        let ocrCandidateProvider = ocrCandidateProvider
        queue.async {
            let payloads = requests.map { request in
                let recognitionStartedAt = Date()
                var result = recognizer.recognize(
                    strokes: request.strokes,
                    options: request.options
                )
                let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
                if Self.shouldRequestOCR(
                    options: request.options,
                    result: result,
                    primaryDecision: primaryDecision
                ),
                   let ocrCandidateProvider,
                   let ocrImage = request.ocrImageProvider() {
                    let ocrStartedAt = Date()
                    let ocrCandidates = ocrCandidateProvider.recognizeCandidates(in: ocrImage)
                    result = Self.result(
                        result,
                        byApplyingOCRCandidates: ocrCandidates,
                        options: request.options
                    )
                    result.metrics.ocrMilliseconds = Date().timeIntervalSince(ocrStartedAt) * 1_000
                }

                let recognitionFinishedAt = Date()
                return ChordInkRecognitionProposalPayload(
                    requestID: request.requestID,
                    result: result,
                    drawingData: request.drawingData,
                    target: request.target,
                    visualOrder: request.visualOrder,
                    laneLocation: request.laneLocation,
                    layoutPageSize: request.layoutPageSize,
                    timing: ChordInkRecognitionTiming(
                        scheduledAt: request.scheduledAt,
                        requestedDelay: request.requestedDelay,
                        recognitionStartedAt: recognitionStartedAt,
                        recognitionFinishedAt: recognitionFinishedAt,
                        strokeCount: request.strokes.count,
                        ocrCandidateCount: result.ocrCandidates?.count ?? 0
                    )
                )
            }

            DispatchQueue.main.async {
                completion(payloads)
            }
        }
    }

    private static func shouldRequestOCR(
        options: ChordInkRecognitionOptions,
        result: ChordInkRecognitionResult,
        primaryDecision: ChordInkRecognitionDecision
    ) -> Bool {
        switch options.ocrRequestPolicy {
        case .always:
            return true
        case .trustGated:
            return ChordRecognitionTrustArbiter.shouldRequestOCR(
                for: result,
                primaryDecision: primaryDecision
            )
        }
    }

    private static func result(
        _ result: ChordInkRecognitionResult,
        byApplyingOCRCandidates ocrCandidates: [ChordOCRCandidate],
        options: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult {
        var updated = result
        updated.ocrCandidates = ocrCandidates

        for displayText in supportedOCRCandidateTexts(from: ocrCandidates) {
            appendCandidateText(displayText, confidence: ocrCandidateScoreConfidence, to: &updated)
        }

        if options.ocrRequestPolicy == .always,
           let preferredOCRText = preferredOCRCandidateText(
               ocrCandidates: ocrCandidates,
               result: result
           ),
           let hybridMatch = ChordRecognitionCompendium.match(preferredOCRText),
           result.match?.displayText != hybridMatch.displayText {
            updated.match = hybridMatch
            updated.confidence = min(updated.confidence, ocrPreferredConfirmationConfidence)
            appendCandidateText(
                hybridMatch.displayText,
                confidence: ocrPreferredConfirmationConfidence,
                to: &updated,
                prepend: true
            )
        }

        updated.metrics.rawCandidateCount = updated.rawCandidates.count
        return updated
    }

    private static let ocrCandidateScoreConfidence = ChordInkRecognitionPolicy.autoRenderMinimumConfidence - 0.06
    private static let ocrPreferredConfirmationConfidence = ChordInkRecognitionPolicy.autoRenderMinimumConfidence - 0.25

    private static func supportedOCRCandidateTexts(from candidates: [ChordOCRCandidate]) -> [String] {
        uniqueDisplayTexts(candidates.compactMap(\.displayText))
    }

    private static func preferredOCRCandidateText(
        ocrCandidates: [ChordOCRCandidate],
        result: ChordInkRecognitionResult
    ) -> String? {
        if let hybridText = ocrRootHybridCandidateText(
            ocrCandidates: ocrCandidates,
            result: result
        ) {
            return hybridText
        }

        if result.match != nil,
           let directOCRText = supportedOCRCandidateTexts(from: ocrCandidates).first {
            return directOCRText
        }

        return nil
    }

    private static func ocrRootHybridCandidateText(
        ocrCandidates: [ChordOCRCandidate],
        result: ChordInkRecognitionResult
    ) -> String? {
        guard let ocrRoot = ocrRootCandidate(from: ocrCandidates),
              ocrRoot.displayText != result.match?.displayText else {
            return nil
        }

        let primaryTexts = uniqueDisplayTexts(
            [result.match?.displayText].compactMap { $0 }
                + result.candidateScores.compactMap(\.displayText)
                + result.rawCandidates
        )
        for primaryText in primaryTexts {
            guard let primarySymbol = try? ChordSymbolParser.parse(primaryText),
                  primarySymbol.kind == .rooted,
                  primarySymbol.displayText != ocrRoot.displayText else {
                continue
            }

            var hybridSymbol = primarySymbol
            hybridSymbol.root = ocrRoot.symbol.root
            hybridSymbol.accidental = ocrRoot.symbol.accidental
            let hybridText = hybridSymbol.displayText
            guard hybridText != primarySymbol.displayText,
                  ChordRecognitionCompendium.match(hybridText) != nil else {
                continue
            }

            return hybridText
        }

        return nil
    }

    private static func ocrRootCandidate(
        from candidates: [ChordOCRCandidate]
    ) -> (displayText: String, symbol: ChordSymbol)? {
        candidates
            .compactMap { candidate -> (displayText: String, symbol: ChordSymbol, confidence: Double)? in
                guard let displayText = candidate.displayText,
                      let symbol = try? ChordSymbolParser.parse(displayText),
                      symbol.kind == .rooted,
                      symbol.quality.isEmpty,
                      symbol.extensions.isEmpty,
                      symbol.alterations.isEmpty,
                      symbol.slashBass == nil else {
                    return nil
                }

                return (displayText, symbol, candidate.confidence)
            }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }

                return lhs.displayText < rhs.displayText
            }
            .first
            .map { (displayText: $0.displayText, symbol: $0.symbol) }
    }

    private static func appendCandidateText(
        _ displayText: String,
        confidence: Double,
        to result: inout ChordInkRecognitionResult,
        prepend: Bool = false
    ) {
        guard !displayText.isEmpty else {
            return
        }

        if prepend {
            result.rawCandidates.removeAll { $0 == displayText }
            result.rawCandidates.insert(displayText, at: 0)
        } else if !result.rawCandidates.contains(displayText) {
            result.rawCandidates.append(displayText)
        }

        if prepend {
            result.candidateScores.removeAll { $0.displayText == displayText }
        } else if result.candidateScores.contains(where: { $0.displayText == displayText }) {
            return
        }

        let score = ChordInkCandidateScore(
            text: displayText,
            displayText: displayText,
            confidence: confidence
        )
        if prepend {
            result.candidateScores.insert(score, at: 0)
        } else {
            result.candidateScores.append(score)
        }
    }

    private static func uniqueDisplayTexts(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for text in texts {
            guard !seen.contains(text) else {
                continue
            }

            seen.insert(text)
            result.append(text)
        }
        return result
    }
}
#endif
