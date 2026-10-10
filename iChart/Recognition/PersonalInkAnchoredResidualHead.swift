import Foundation

/// Means of public training embeddings, not personal lessons or pseudo-labels.
/// The runtime loader binds their bytes to the frozen visual encoder.
struct PersonalInkAnchorBank: Codable, Equatable {
    let vocabulary: [String]
    let features: [[Double]]
}

/// Comparison-only residual fit with zero-correction constraints at untaught
/// shared shapes. This is not a confidence estimator or an acceptance policy.
struct PersonalInkAnchoredResidualHead {
    static let version = "personal-untaught-anchor-v1"
    typealias Context = PersonalInkResidualHead.Context
    typealias Lesson = PersonalInkResidualHead.Lesson
    typealias Candidate = PersonalInkResidualHead.Candidate
    typealias Failure = PersonalInkResidualHead.Failure

    let context: Context
    let vocabulary: [String]
    let featureCount: Int
    let lessonCount: Int
    let activeAnchorCount: Int
    private let original: PersonalInkResidualHead
    private let corrections: [[Double]]?

    init(context: Context, vocabulary: [String], featureCount: Int, lessons: [Lesson], bank: PersonalInkAnchorBank) throws {
        // Reuse the established lesson validation, with exact empty/full-profile
        // behavior. The fixed encoder has 128 features; do not allocate an
        // arbitrary quadratic matrix from malformed artifact dimensions.
        guard (1...128).contains(featureCount) else { throw Failure.invalidFeatures }
        original = try .init(context: context, vocabulary: vocabulary, featureCount: featureCount, lessons: lessons)
        guard (2...512).contains(bank.vocabulary.count), Set(bank.vocabulary).count == bank.vocabulary.count,
              Set(bank.vocabulary).isSubset(of: Set(vocabulary)), bank.features.count == bank.vocabulary.count else {
            throw Failure.invalidLabels
        }
        for anchor in bank.features { try Self.validateFeature(anchor, count: featureCount) }
        self.context = context
        self.vocabulary = vocabulary
        self.featureCount = featureCount
        lessonCount = lessons.count
        let taught = Set(lessons.map(\.label))
        let anchors = zip(bank.vocabulary, bank.features).filter { !taught.contains($0.0) }.map(\.1)
        activeAnchorCount = anchors.count
        guard !lessons.isEmpty, !anchors.isEmpty else { corrections = nil; return }

        let frequencies = Dictionary(grouping: lessons, by: \.label).mapValues(\.count)
        let balance = lessons.map { 1 / sqrt(Double(frequencies[$0.label]!)) }
        let x = zip(lessons, balance).map { lesson, weight in lesson.features.map { $0 * weight } }
        let d = featureCount
        // Cholesky of X'X + A'A + lambda I. Anchor targets are exactly zero;
        // anchors never enter the explicitly labeled support residuals.
        var lower = [Double](repeating: 0, count: d * d)
        for i in 0..<d {
            for j in 0...i {
                var value = i == j ? PersonalInkResidualHead.regularization : 0
                for row in x { value += row[i] * row[j] }
                for row in anchors { value += row[i] * row[j] }
                for k in 0..<j { value -= lower[i * d + k] * lower[j * d + k] }
                if i == j {
                    guard value.isFinite, value > 0 else { throw Failure.numericalFailure }
                    lower[i * d + j] = sqrt(value)
                } else { lower[i * d + j] = value / lower[j * d + j] }
            }
        }
        corrections = try vocabulary.enumerated().map { column, label in
            var weights = [Double](repeating: 0, count: d)
            for index in lessons.indices {
                let residual = ((lessons[index].label == label ? 1.0 : 0.0) - lessons[index].baseScores[column]) * balance[index]
                for i in 0..<d { weights[i] += x[index][i] * residual }
            }
            for i in 0..<d {
                for j in 0..<i { weights[i] -= lower[i * d + j] * weights[j] }
                weights[i] /= lower[i * d + i]
            }
            for i in (0..<d).reversed() {
                if i + 1 < d {
                    for j in (i + 1)..<d { weights[i] -= lower[j * d + i] * weights[j] }
                }
                weights[i] /= lower[i * d + i]
            }
            guard weights.allSatisfy(\.isFinite) else { throw Failure.numericalFailure }
            return weights
        }
    }

    func rankedCandidates(features: [Double], baseScores: [Double], currentContext: Context) throws -> [Candidate] {
        // Reuse the same opt-out, stale-context and query validation as the
        // original learner. The old ranks remain independently reproducible.
        let baseline = try original.rankedCandidates(features: features, baseScores: baseScores, currentContext: currentContext)
        guard let corrections else { return baseline }
        return try vocabulary.indices.map { i in
            let score = baseScores[i] + Self.dot(features, corrections[i])
            guard score.isFinite else { throw Failure.numericalFailure }
            return Candidate(label: vocabulary[i], score: score)
        }.sorted { $0.score == $1.score ? $0.label < $1.label : $0.score > $1.score }
    }

    private static func validateFeature(_ features: [Double], count: Int) throws {
        guard features.count == count, features.allSatisfy(\.isFinite),
              abs(sqrt(dot(features, features)) - 1) <= 1e-3 else { throw Failure.invalidFeatures }
    }
    private static func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
}
