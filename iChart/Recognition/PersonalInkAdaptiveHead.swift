import Foundation

/// Comparison-only learned personal layer, not a second base recognizer.
/// Fits regularized one-vs-rest visual weights to explicitly labeled examples.
/// Scores are uncalibrated regression outputs, never probabilities or trust.
/// No live suggestion/render path calls this until independent validation.
struct PersonalInkAdaptiveHead {
    static let version = "personal-balanced-ridge-v1"
    static let regularization = 0.1

    enum Failure: Error {
        case disabled, invalidProfile, insufficientLabels, invalidFeatures, numericalFailure
    }
    struct Candidate: Equatable {
        var label: String
        var score: Double
    }

    let profileRevision: UUID
    let kind: PersonalInkExampleKind
    let exampleCount: Int
    let labels: [String]
    private let weights: [[Double]]

    init(profile: PersonalInkProfile, kind: PersonalInkExampleKind) throws {
        guard profile.isEnabled else { throw Failure.disabled }
        guard profile.version == 1, profile.examples.count <= PersonalInkProfile.maximumExamples else {
            throw Failure.invalidProfile
        }
        let examples = profile.examples.filter { $0.kind == kind }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard examples.allSatisfy({ example in
            (kind == .glyph ? PersonalInkProfile.glyphLabels.contains(example.label)
                : ChordRecognitionCompendium.match(example.label)?.displayText == example.label)
                && example.hasValidRecognitionInput
        }) else { throw Failure.invalidProfile }
        let features = try examples.map { example -> [Double] in
            guard let value = Self.features(strokes: example.recognitionInput) else { throw Failure.invalidFeatures }
            return value
        }
        let fitted = try PersonalInkBalancedRidge.fit(features: features, labels: examples.map(\.label),
                                                      regularization: Self.regularization)
        profileRevision = profile.revision
        self.kind = kind
        exampleCount = examples.count
        labels = fitted.labels
        weights = fitted.weights
    }

    /// Ranking only: callers must not interpret the top label as an accepted
    /// prediction. Even unfamiliar ink will have a largest regression score.
    func rankedCandidates(strokes: [InkStroke]) -> [Candidate] {
        guard let feature = Self.features(strokes: strokes) else { return [] }
        let scores = weights.map { Self.dot($0, feature) }
        guard scores.allSatisfy(\.isFinite) else { return [] }
        return zip(labels, scores).map { Candidate(label: $0, score: $1) }.sorted {
            $0.score == $1.score ? $0.label < $1.label : $0.score > $1.score
        }
    }

    /// Fixed label-blind spatial features use the existing aspect-preserving
    /// ink normalization. Reciprocal distance softens one-pixel raster edges;
    /// no text-recognition substitutions, root-specific rules, or learned-label lookup here.
    private static func features(strokes: [InkStroke]) -> [Double]? {
        guard let shape = PersonalInkShape(strokes: strokes) else { return nil }
        let values = shape.distances.map { 1.0 / (1.0 + Double($0)) }
        let norm = sqrt(dot(values, values))
        guard norm.isFinite, norm > 0 else { return nil }
        return values.map { $0 / norm }
    }

    private static func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
        zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
    }
}

/// Weighted ridge in the sample-sized dual system, then materialized as a
/// small immutable linear head. Equal total weight per class prevents six
/// lessons of one label from automatically outweighing one of another.
/// Fits sum_i w_i ||x_i W-y_i||^2 + lambda ||W||^2, w_i=1/count(label_i).
enum PersonalInkBalancedRidge {
    struct Model { let labels: [String]; let weights: [[Double]] }

    static func fit(features: [[Double]], labels: [String], regularization: Double) throws -> Model {
        typealias Failure = PersonalInkAdaptiveHead.Failure
        let count = features.count
        guard count > 0, count <= PersonalInkProfile.maximumExamples,
              count == labels.count, regularization.isFinite, regularization > 0,
              let dimension = features.first?.count, dimension > 0, dimension <= 2_048,
              features.allSatisfy({ $0.count == dimension && $0.allSatisfy(\.isFinite) }),
              labels.allSatisfy({ !$0.isEmpty }) else { throw Failure.invalidFeatures }
        let classes = Set(labels).sorted()
        guard classes.count >= 2 else { throw Failure.insufficientLabels }
        let frequencies = Dictionary(grouping: labels, by: { $0 }).mapValues(\.count)
        let sampleWeights = labels.map { 1.0 / sqrt(Double(frequencies[$0]!)) }
        let x = zip(features, sampleWeights).map { row, weight in row.map { $0 * weight } }

        // L L^T = sqrt(S) X X^T sqrt(S) + lambda I.
        var lower = [Double](repeating: 0, count: count * count)
        for i in 0..<count {
            for j in 0...i {
                var value = zip(x[i], x[j]).reduce(0.0) { $0 + $1.0 * $1.1 }
                if i == j { value += regularization }
                for k in 0..<j { value -= lower[i * count + k] * lower[j * count + k] }
                if i == j {
                    guard value.isFinite, value > 0 else { throw Failure.numericalFailure }
                    lower[i * count + j] = sqrt(value)
                } else {
                    lower[i * count + j] = value / lower[j * count + j]
                }
            }
        }
        let weights = try classes.map { label -> [Double] in
            var coefficients = zip(labels, sampleWeights).map { $0 == label ? $1 : 0 }
            // Forward solve L z = sqrt(S) y.
            for i in 0..<count {
                for j in 0..<i { coefficients[i] -= lower[i * count + j] * coefficients[j] }
                coefficients[i] /= lower[i * count + i]
            }
            // Back solve L^T alpha = z.
            for i in (0..<count).reversed() {
                if i + 1 < count {
                    for j in (i + 1)..<count { coefficients[i] -= lower[j * count + i] * coefficients[j] }
                }
                coefficients[i] /= lower[i * count + i]
            }
            var primal = [Double](repeating: 0, count: dimension)
            for i in 0..<count {
                for d in 0..<dimension { primal[d] += x[i][d] * coefficients[i] }
            }
            guard primal.allSatisfy(\.isFinite) else { throw Failure.numericalFailure }
            return primal
        }
        return Model(labels: classes, weights: weights)
    }
}
