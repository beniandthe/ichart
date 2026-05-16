import Foundation

#if canImport(CoreGraphics)
import CoreGraphics

protocol ChordOCRCandidateProviding {
    func recognizeCandidates(in image: CGImage) -> [ChordOCRCandidate]
}

enum ChordOCRCandidateProviderFactory {
    static func liveProvider() -> ChordOCRCandidateProviding? {
        #if canImport(Vision)
        return VisionChordOCRCandidateProvider()
        #else
        return nil
        #endif
    }
}
#else
protocol ChordOCRCandidateProviding {}

enum ChordOCRCandidateProviderFactory {
    static func liveProvider() -> ChordOCRCandidateProviding? {
        nil
    }
}
#endif

#if canImport(Vision) && canImport(CoreGraphics)
import Vision

final class VisionChordOCRCandidateProvider: ChordOCRCandidateProviding {
    var maximumCandidatesPerObservation: Int
    var minimumConfidence: Double

    init(
        maximumCandidatesPerObservation: Int = 3,
        minimumConfidence: Double = 0.12
    ) {
        self.maximumCandidatesPerObservation = maximumCandidatesPerObservation
        self.minimumConfidence = minimumConfidence
    }

    func recognizeCandidates(in image: CGImage) -> [ChordOCRCandidate] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.05

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let candidates = (request.results ?? [])
            .flatMap { observation in
                observation.topCandidates(maximumCandidatesPerObservation)
            }
            .filter { candidate in
                Double(candidate.confidence) >= minimumConfidence
            }
            .map { candidate in
                ChordOCRCandidate.normalized(
                    rawText: candidate.string,
                    confidence: Double(candidate.confidence),
                    source: .appleVision
                )
            }

        return uniqueCandidates(candidates)
    }

    private func uniqueCandidates(_ candidates: [ChordOCRCandidate]) -> [ChordOCRCandidate] {
        var bestByKey: [String: ChordOCRCandidate] = [:]
        for candidate in candidates {
            let key = candidate.displayText ?? candidate.rawText
            if let current = bestByKey[key],
               current.confidence >= candidate.confidence {
                continue
            }

            bestByKey[key] = candidate
        }

        return bestByKey.values.sorted { lhs, rhs in
            if lhs.isSupported != rhs.isSupported {
                return lhs.isSupported && !rhs.isSupported
            }

            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return (lhs.displayText ?? lhs.rawText) < (rhs.displayText ?? rhs.rawText)
        }
    }
}
#endif
