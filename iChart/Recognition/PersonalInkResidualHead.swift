import Foundation

/// Comparison-only learned corrections to a frozen model's normalized scores.
/// Neither the input normalization nor the corrected ranks are calibrated trust.
/// No editor or live recognition path invokes this experimental head.
struct PersonalInkResidualHead {
    static let version = "personal-residual-ridge-v1"
    static let regularization = 0.1

    struct Context: Equatable {
        var isEnabled: Bool
        var profileRevision: UUID
        var encoderIdentity: String
    }
    struct Lesson {
        var label: String
        var features: [Double]
        var baseScores: [Double]
    }
    struct Candidate: Equatable { var label: String; var score: Double }
    enum Failure: Error, Equatable {
        case disabled, staleContext, invalidContext, invalidFeatures, invalidScores, invalidLabels, numericalFailure
    }

    let context: Context
    let vocabulary: [String]
    let featureCount: Int
    let lessonCount: Int
    private let corrections: [[Double]]

    init(context: Context, vocabulary: [String], featureCount: Int, lessons: [Lesson]) throws {
        guard context.isEnabled else { throw Failure.disabled }
        guard !context.encoderIdentity.isEmpty else { throw Failure.invalidContext }
        guard (1...2_048).contains(featureCount), lessons.count <= PersonalInkProfile.maximumExamples else {
            throw Failure.invalidFeatures
        }
        guard (2...512).contains(vocabulary.count), Set(vocabulary).count == vocabulary.count,
              vocabulary.allSatisfy({ !$0.isEmpty }), lessons.allSatisfy({ vocabulary.contains($0.label) }) else {
            throw Failure.invalidLabels
        }
        for lesson in lessons {
            try Self.validateFeatures(lesson.features, count: featureCount)
            try Self.validateScores(lesson.baseScores, count: vocabulary.count)
        }
        self.context = context
        self.vocabulary = vocabulary
        self.featureCount = featureCount
        lessonCount = lessons.count
        guard !lessons.isEmpty else {
            corrections = vocabulary.map { _ in Array(repeating: 0, count: featureCount) }
            return
        }
        let count = lessons.count
        let frequencies = Dictionary(grouping: lessons, by: \.label).mapValues(\.count)
        let sampleWeights = lessons.map { 1 / sqrt(Double(frequencies[$0.label]!)) }
        let x = zip(lessons, sampleWeights).map { lesson, weight in lesson.features.map { $0 * weight } }
        var lower = [Double](repeating: 0, count: count * count)
        for i in 0..<count {
            for j in 0...i {
                var value = Self.dot(x[i], x[j])
                if i == j { value += Self.regularization }
                for k in 0..<j { value -= lower[i * count + k] * lower[j * count + k] }
                if i == j {
                    guard value.isFinite, value > 0 else { throw Failure.numericalFailure }
                    lower[i * count + j] = sqrt(value)
                } else {
                    lower[i * count + j] = value / lower[j * count + j]
                }
            }
        }
        corrections = try vocabulary.enumerated().map { column, label in
            var coefficients = lessons.indices.map { i in
                ((lessons[i].label == label ? 1.0 : 0.0) - lessons[i].baseScores[column]) * sampleWeights[i]
            }
            for i in 0..<count {
                for j in 0..<i { coefficients[i] -= lower[i * count + j] * coefficients[j] }
                coefficients[i] /= lower[i * count + i]
            }
            for i in (0..<count).reversed() {
                if i + 1 < count {
                    for j in (i + 1)..<count { coefficients[i] -= lower[j * count + i] * coefficients[j] }
                }
                coefficients[i] /= lower[i * count + i]
            }
            var weights = [Double](repeating: 0, count: featureCount)
            for i in 0..<count {
                for d in 0..<featureCount { weights[d] += x[i][d] * coefficients[i] }
            }
            guard weights.allSatisfy(\.isFinite) else { throw Failure.numericalFailure }
            return weights
        }
    }

    /// The caller must supply the current context. Opt-out, lesson removal,
    /// correction or encoder replacement cannot use a stale cached model.
    func rankedCandidates(features: [Double], baseScores: [Double], currentContext: Context) throws -> [Candidate] {
        guard currentContext.isEnabled else { throw Failure.disabled }
        guard currentContext == context else { throw Failure.staleContext }
        try Self.validateFeatures(features, count: featureCount)
        try Self.validateScores(baseScores, count: vocabulary.count)
        var candidates: [Candidate] = []
        for i in vocabulary.indices {
            let score = baseScores[i] + Self.dot(features, corrections[i])
            guard score.isFinite else { throw Failure.numericalFailure }
            candidates.append(Candidate(label: vocabulary[i], score: score))
        }
        return candidates.sorted { $0.score == $1.score ? $0.label < $1.label : $0.score > $1.score }
    }

    static func normalizedScores(logits: [Double]) throws -> [Double] {
        guard (2...512).contains(logits.count), logits.allSatisfy({ $0.isFinite && abs($0) <= 1e6 }),
              let maximum = logits.max() else { throw Failure.invalidScores }
        let values = logits.map { exp($0 - maximum) }
        let total = values.reduce(0, +)
        guard total.isFinite, total > 0 else { throw Failure.numericalFailure }
        return values.map { $0 / total }
    }

    private static func validateFeatures(_ features: [Double], count: Int) throws {
        guard features.count == count, features.allSatisfy(\.isFinite),
              abs(sqrt(dot(features, features)) - 1) <= 1e-3 else { throw Failure.invalidFeatures }
    }

    private static func validateScores(_ scores: [Double], count: Int) throws {
        guard scores.count == count, scores.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
              abs(scores.reduce(0, +) - 1) <= 1e-8 else { throw Failure.invalidScores }
    }

    private static func dot(_ left: [Double], _ right: [Double]) -> Double {
        zip(left, right).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
