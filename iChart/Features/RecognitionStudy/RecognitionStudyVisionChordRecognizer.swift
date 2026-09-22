import CoreGraphics
import Foundation
import ImageIO
import Vision

/// The Vision baseline does not own chord syntax. Its caller must provide the
/// study's single strict, typed grammar boundary. Returning nil means the raw
/// OCR candidate is outside that grammar; implementations must not use fuzzy
/// repair or writer-specific correction memory here.
protocol RecognitionStudyChordCandidateNormalizing: Sendable {
    func normalizedChord(from rawText: String) -> String?
}

/// The production study adapter accepts only the canonical language represented
/// by the shared typed AST. In particular, this does not repair OCR aliases such
/// as `maj`, Unicode accidental lookalikes, or root-letter substitutions.
struct RecognitionStudyCanonicalChordNormalizer:
    RecognitionStudyChordCandidateNormalizing
{
    func normalizedChord(from rawText: String) -> String? {
        guard let notation = try? ChordNotation.parseCanonical(rawText) else {
            return nil
        }
        return notation.canonicalDisplay
    }
}

/// A bounded, study-only baseline that asks Vision to read deterministic
/// rasterizations of lossless ink. It deliberately has no dependency on the
/// production recognizer, correction memory, retained fixtures, or user
/// identity.
///
/// This is an evaluation candidate, not an accuracy claim. A chord is accepted
/// only when two correlated but distinct raster variants agree and each pass
/// has conservative confidence and separation from its nearest competitor.
struct RecognitionStudyVisionChordRecognizer: Sendable {
    private static let hardMaximumCanvasDimension = 2_048
    private static let hardMaximumCanvasPixelCount = 2_097_152
    private static let hardMaximumRasterPasses = 4
    private static let hardMaximumStrokeCount = 512
    private static let hardMaximumPointCount = 65_536
    private static let hardMaximumVisionObservations = 8
    private static let hardMaximumCandidatesPerObservation = 10
    private static let hardMaximumCombinedCandidates = 64

    struct Configuration: Equatable, Sendable {
        var canvasWidth = 512
        var canvasHeight = 256
        var padding = 24.0
        var strokeWidths = [7.0, 10.0]
        var maximumStrokeCount = 128
        var maximumPointCount = 16_384
        var maximumVisionObservations = 4
        var maximumCandidatesPerObservation = 3
        var maximumCombinedCandidates = 12
        var minimumConsensusPasses = 2
        var minimumAcceptedConfidence: Float = 0.78
        var minimumAcceptedMargin: Float = 0.12

        static let `default` = Configuration()
    }

    struct Candidate: Equatable {
        /// The exact string returned by Vision (or the concatenation of exact
        /// component strings when Vision split one chord into text regions).
        let rawText: String
        /// Vision's untouched confidence for each text component.
        let rawComponentConfidences: [Float]
        /// The minimum raw component confidence. This conservative aggregate is
        /// used for ordering and thresholds; it is not a calibrated probability.
        let rawConfidenceFloor: Float
        /// Present only when the raw text satisfies the strict chord grammar.
        let normalizedChord: String?
        let passIndex: Int
        let rank: Int

        init(
            rawText: String,
            rawComponentConfidences: [Float],
            normalizedChord: String?,
            passIndex: Int,
            rank: Int
        ) {
            self.rawText = rawText
            self.rawComponentConfidences = rawComponentConfidences
            rawConfidenceFloor = rawComponentConfidences.min() ?? 0
            self.normalizedChord = normalizedChord
            self.passIndex = passIndex
            self.rank = rank
        }

        init(
            rawText: String,
            rawConfidence: Float,
            normalizedChord: String?,
            passIndex: Int,
            rank: Int
        ) {
            self.init(
                rawText: rawText,
                rawComponentConfidences: [rawConfidence],
                normalizedChord: normalizedChord,
                passIndex: passIndex,
                rank: rank
            )
        }
    }

    enum ReviewReason: Equatable {
        case insufficientConsensus
        case rasterPassDisagreement
        case confidenceBelowThreshold
        case candidateMarginBelowThreshold
        case topCandidateOutsideGrammar
    }

    enum NoReadReason: Equatable {
        case noInk
        case noVisionText
        case noGrammarCandidate
    }

    enum Decision: Equatable {
        case accepted(chord: String, confidenceFloor: Float)
        case review(ReviewReason)
        case noRead(NoReadReason)
    }

    struct Result: Equatable {
        let decision: Decision
        /// All bounded top candidates, including grammar-invalid candidates,
        /// so an evaluator can inspect what Vision actually returned.
        let candidates: [Candidate]
    }

    enum RecognitionError: Error, Equatable {
        case invalidConfiguration
        case strokeLimitExceeded(actual: Int, maximum: Int)
        case pointLimitExceeded(actual: Int, maximum: Int)
        case nonFinitePoint(strokeIndex: Int, pointIndex: Int)
        case unrenderableBounds
        case rasterizationFailed
    }

    struct RasterizedInk {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let grayscalePixels: Data
        let image: CGImage
    }

    private struct Beam {
        var text: String
        var confidences: [Float]

        var confidenceFloor: Float {
            confidences.min() ?? 0
        }
    }

    let configuration: Configuration
    private let normalizer: any RecognitionStudyChordCandidateNormalizing

    init(
        configuration: Configuration = .default,
        normalizer: any RecognitionStudyChordCandidateNormalizing =
            RecognitionStudyCanonicalChordNormalizer()
    ) {
        self.configuration = configuration
        self.normalizer = normalizer
    }

    func recognize(
        packet: ChordInkCanonicalTrajectoryPacket
    ) throws -> Result {
        try recognize(strokes: packet.preparedStrokes())
    }

    func recognize(strokes: [InkStroke]) throws -> Result {
        try Self.validate(configuration)
        let pointCount = try Self.validatedPointCount(
            strokes,
            configuration: configuration
        )
        guard pointCount > 0 else {
            return Result(decision: .noRead(.noInk), candidates: [])
        }

        var evidenceByPass: [[Candidate]] = []
        evidenceByPass.reserveCapacity(configuration.strokeWidths.count)

        for (passIndex, strokeWidth) in configuration.strokeWidths.enumerated() {
            let raster = try Self.rasterize(
                strokes: strokes,
                strokeWidth: strokeWidth,
                configuration: configuration
            )
            evidenceByPass.append(
                try visionCandidates(
                    image: raster.image,
                    passIndex: passIndex
                )
            )
        }

        return Self.decide(
            evidenceByPass: evidenceByPass,
            configuration: configuration
        )
    }

    /// Pure decision function used by deterministic tests. It never calls
    /// Vision and never promotes a lower-ranked grammar-valid candidate past a
    /// higher-ranked grammar-invalid candidate.
    static func decide(
        evidenceByPass: [[Candidate]],
        configuration: Configuration = .default
    ) -> Result {
        let allCandidates = evidenceByPass
            .flatMap { $0 }
            .filter(Self.hasUsableConfidence)
            .sorted(by: Self.candidateComesFirst)

        guard !allCandidates.isEmpty else {
            return Result(decision: .noRead(.noVisionText), candidates: [])
        }
        guard allCandidates.contains(where: { $0.normalizedChord != nil }) else {
            return Result(
                decision: .noRead(.noGrammarCandidate),
                candidates: allCandidates
            )
        }

        let orderedPasses = evidenceByPass.map { pass in
            pass
                .filter(Self.hasUsableConfidence)
                .sorted(by: Self.rankComesFirst)
        }

        if orderedPasses.contains(where: { pass in
            guard let first = pass.first else { return false }
            return first.normalizedChord == nil
        }) {
            return Result(
                decision: .review(.topCandidateOutsideGrammar),
                candidates: allCandidates
            )
        }

        let topCandidates = orderedPasses.compactMap(\.first)
        guard topCandidates.count >= configuration.minimumConsensusPasses,
              topCandidates.count == orderedPasses.count else {
            return Result(
                decision: .review(.insufficientConsensus),
                candidates: allCandidates
            )
        }

        guard let agreedChord = topCandidates.first?.normalizedChord,
              topCandidates.allSatisfy({ $0.normalizedChord == agreedChord }) else {
            return Result(
                decision: .review(.rasterPassDisagreement),
                candidates: allCandidates
            )
        }

        let confidenceFloor = topCandidates
            .map(\.rawConfidenceFloor)
            .min() ?? 0
        guard confidenceFloor >= configuration.minimumAcceptedConfidence else {
            return Result(
                decision: .review(.confidenceBelowThreshold),
                candidates: allCandidates
            )
        }

        let margins = zip(orderedPasses, topCandidates).map { pass, top in
            let strongestCompetitor = pass
                .dropFirst()
                .filter { $0.normalizedChord != agreedChord }
                .map(\.rawConfidenceFloor)
                .max() ?? 0
            return top.rawConfidenceFloor - strongestCompetitor
        }
        guard margins.allSatisfy({ $0 >= configuration.minimumAcceptedMargin }) else {
            return Result(
                decision: .review(.candidateMarginBelowThreshold),
                candidates: allCandidates
            )
        }

        return Result(
            decision: .accepted(
                chord: agreedChord,
                confidenceFloor: confidenceFloor
            ),
            candidates: allCandidates
        )
    }

    static func rasterize(
        packet: ChordInkCanonicalTrajectoryPacket,
        strokeWidth: Double,
        configuration: Configuration = .default
    ) throws -> RasterizedInk {
        try rasterize(
            strokes: packet.preparedStrokes(),
            strokeWidth: strokeWidth,
            configuration: configuration
        )
    }

    static func rasterize(
        strokes: [InkStroke],
        strokeWidth: Double,
        configuration: Configuration = .default
    ) throws -> RasterizedInk {
        try validate(configuration)
        let pointCount = try validatedPointCount(
            strokes,
            configuration: configuration
        )
        guard pointCount > 0,
              strokeWidth.isFinite,
              strokeWidth > 0 else {
            throw RecognitionError.unrenderableBounds
        }

        let points = strokes.flatMap(\.points)
        guard let firstPoint = points.first else {
            throw RecognitionError.unrenderableBounds
        }
        var minX = firstPoint.x
        var minY = firstPoint.y
        var maxX = firstPoint.x
        var maxY = firstPoint.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        let sourceWidth = maxX - minX
        let sourceHeight = maxY - minY
        guard sourceWidth.isFinite,
              sourceHeight.isFinite,
              sourceWidth >= 0,
              sourceHeight >= 0 else {
            throw RecognitionError.unrenderableBounds
        }

        let width = configuration.canvasWidth
        let height = configuration.canvasHeight
        let padding = configuration.padding
        let availableWidth = Double(width) - (padding * 2)
        let availableHeight = Double(height) - (padding * 2)
        guard availableWidth > 0, availableHeight > 0 else {
            throw RecognitionError.invalidConfiguration
        }

        let effectiveWidth = max(sourceWidth, 1)
        let effectiveHeight = max(sourceHeight, 1)
        let scale = min(
            availableWidth / effectiveWidth,
            availableHeight / effectiveHeight
        )
        guard scale.isFinite, scale > 0 else {
            throw RecognitionError.unrenderableBounds
        }

        let renderedWidth = sourceWidth * scale
        let renderedHeight = sourceHeight * scale
        let xOffset = (Double(width) - renderedWidth) / 2
        let yOffset = (Double(height) - renderedHeight) / 2
        let bytesPerRow = width
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw RecognitionError.rasterizationFailed
        }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setFillColor(gray: 0, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(CGFloat(strokeWidth))
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .none

        func projected(_ point: InkPoint) -> CGPoint {
            CGPoint(
                x: xOffset + ((point.x - minX) * scale),
                y: yOffset + ((point.y - minY) * scale)
            )
        }

        for stroke in strokes where !stroke.points.isEmpty {
            let projectedPoints = stroke.points.map(projected)
            guard let first = projectedPoints.first else { continue }

            if projectedPoints.count == 1 {
                let radius = CGFloat(strokeWidth / 2)
                context.fillEllipse(
                    in: CGRect(
                        x: first.x - radius,
                        y: first.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
                continue
            }

            context.beginPath()
            context.move(to: first)
            for point in projectedPoints.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }

        guard let image = context.makeImage(),
              let rawBytes = context.data else {
            throw RecognitionError.rasterizationFailed
        }
        let pixels = Data(
            bytes: rawBytes,
            count: bytesPerRow * height
        )
        return RasterizedInk(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            grayscalePixels: pixels,
            image: image
        )
    }

    private func visionCandidates(
        image: CGImage,
        passIndex: Int
    ) throws -> [Candidate] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(
            cgImage: image,
            orientation: .up,
            options: [:]
        )
        try handler.perform([request])

        let observations = (request.results ?? []).sorted { lhs, rhs in
            if abs(lhs.boundingBox.minX - rhs.boundingBox.minX) > 0.001 {
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            return lhs.boundingBox.maxY > rhs.boundingBox.maxY
        }
        guard !observations.isEmpty,
              observations.count <= configuration.maximumVisionObservations else {
            return []
        }

        var beams = [Beam(text: "", confidences: [])]
        for observation in observations {
            let componentCandidates = observation.topCandidates(
                configuration.maximumCandidatesPerObservation
            )
            guard !componentCandidates.isEmpty else { return [] }

            var expanded: [Beam] = []
            expanded.reserveCapacity(
                min(
                    configuration.maximumCombinedCandidates,
                    beams.count * componentCandidates.count
                )
            )
            for beam in beams {
                for component in componentCandidates {
                    guard component.confidence.isFinite,
                          component.confidence >= 0,
                          component.confidence <= 1,
                          !component.string.isEmpty else {
                        continue
                    }
                    expanded.append(
                        Beam(
                            text: beam.text + component.string,
                            confidences: beam.confidences + [component.confidence]
                        )
                    )
                }
            }
            beams = Array(
                expanded
                    .sorted(by: Self.beamComesFirst)
                    .prefix(configuration.maximumCombinedCandidates)
            )
        }

        var seen = Set<String>()
        let uniqueBeams = beams.filter { beam in
            seen.insert(beam.text).inserted
        }
        return uniqueBeams.enumerated().map { rank, beam in
            Candidate(
                rawText: beam.text,
                rawComponentConfidences: beam.confidences,
                normalizedChord: normalizer.normalizedChord(from: beam.text),
                passIndex: passIndex,
                rank: rank
            )
        }
    }

    private static func validate(_ configuration: Configuration) throws {
        let (canvasPixelCount, canvasPixelCountOverflow) =
            configuration.canvasWidth.multipliedReportingOverflow(
                by: configuration.canvasHeight
            )
        guard !canvasPixelCountOverflow,
              configuration.canvasWidth > 0,
              configuration.canvasHeight > 0,
              configuration.canvasWidth <= hardMaximumCanvasDimension,
              configuration.canvasHeight <= hardMaximumCanvasDimension,
              canvasPixelCount <= hardMaximumCanvasPixelCount,
              configuration.padding.isFinite,
              configuration.padding >= 0,
              configuration.padding * 2 < Double(configuration.canvasWidth),
              configuration.padding * 2 < Double(configuration.canvasHeight),
              configuration.strokeWidths.count >= configuration.minimumConsensusPasses,
              configuration.strokeWidths.count <= hardMaximumRasterPasses,
              configuration.strokeWidths.allSatisfy({ $0.isFinite && $0 > 0 }),
              configuration.maximumStrokeCount > 0,
              configuration.maximumStrokeCount <= hardMaximumStrokeCount,
              configuration.maximumPointCount > 0,
              configuration.maximumPointCount <= hardMaximumPointCount,
              configuration.maximumVisionObservations > 0,
              configuration.maximumVisionObservations <= hardMaximumVisionObservations,
              configuration.maximumCandidatesPerObservation > 0,
              configuration.maximumCandidatesPerObservation
                <= hardMaximumCandidatesPerObservation,
              configuration.maximumCombinedCandidates > 0,
              configuration.maximumCombinedCandidates
                <= hardMaximumCombinedCandidates,
              configuration.minimumConsensusPasses > 0,
              configuration.minimumAcceptedConfidence.isFinite,
              (0...1).contains(configuration.minimumAcceptedConfidence),
              configuration.minimumAcceptedMargin.isFinite,
              (0...1).contains(configuration.minimumAcceptedMargin) else {
            throw RecognitionError.invalidConfiguration
        }
    }

    private static func validatedPointCount(
        _ strokes: [InkStroke],
        configuration: Configuration
    ) throws -> Int {
        guard strokes.count <= configuration.maximumStrokeCount else {
            throw RecognitionError.strokeLimitExceeded(
                actual: strokes.count,
                maximum: configuration.maximumStrokeCount
            )
        }

        var pointCount = 0
        for (strokeIndex, stroke) in strokes.enumerated() {
            for (pointIndex, point) in stroke.points.enumerated() {
                guard point.x.isFinite, point.y.isFinite else {
                    throw RecognitionError.nonFinitePoint(
                        strokeIndex: strokeIndex,
                        pointIndex: pointIndex
                    )
                }
                let (nextCount, overflow) = pointCount.addingReportingOverflow(1)
                guard !overflow,
                      nextCount <= configuration.maximumPointCount else {
                    throw RecognitionError.pointLimitExceeded(
                        actual: overflow ? Int.max : nextCount,
                        maximum: configuration.maximumPointCount
                    )
                }
                pointCount = nextCount
            }
        }
        return pointCount
    }

    private static func hasUsableConfidence(_ candidate: Candidate) -> Bool {
        candidate.rawConfidenceFloor.isFinite
            && (0...1).contains(candidate.rawConfidenceFloor)
            && !candidate.rawComponentConfidences.isEmpty
            && candidate.rawComponentConfidences.allSatisfy {
                $0.isFinite && (0...1).contains($0)
            }
    }

    private static func rankComesFirst(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        if lhs.rawConfidenceFloor != rhs.rawConfidenceFloor {
            return lhs.rawConfidenceFloor > rhs.rawConfidenceFloor
        }
        return lhs.rawText < rhs.rawText
    }

    private static func candidateComesFirst(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.passIndex != rhs.passIndex { return lhs.passIndex < rhs.passIndex }
        return rankComesFirst(lhs, rhs)
    }

    private static func beamComesFirst(_ lhs: Beam, _ rhs: Beam) -> Bool {
        if lhs.confidenceFloor != rhs.confidenceFloor {
            return lhs.confidenceFloor > rhs.confidenceFloor
        }
        return lhs.text < rhs.text
    }
}
