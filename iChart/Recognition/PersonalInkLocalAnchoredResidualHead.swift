import Foundation

/// Comparison-only local residual fit over a frozen unit embedding. Untaught
/// shared classes contribute zero-residual RBF anchors. Nothing in the live
/// recognition or editor path invokes this experimental head.
struct PersonalInkLocalAnchoredResidualHead {
    static let version = "personal-local-untaught-anchor-v1"
    static let kernelWidth = 0.16684838059285878
    static let regularization = PersonalInkResidualHead.regularization
    static let maximumFeatureCount = 128
    static let maximumAnchorCount = 512
    static let maximumFitPointCount = PersonalInkProfile.maximumExamples + maximumAnchorCount

    typealias Context = PersonalInkResidualHead.Context
    typealias Lesson = PersonalInkResidualHead.Lesson
    typealias Candidate = PersonalInkResidualHead.Candidate
    typealias Failure = PersonalInkResidualHead.Failure

    let context: Context
    let vocabulary: [String]
    let featureCount: Int
    let lessonCount: Int
    let activeAnchorCount: Int
    private let points: [[Double]]
    private let coefficients: [[Double]]

    init(context: Context, vocabulary: [String], featureCount: Int, lessons: [Lesson], bank: PersonalInkAnchorBank) throws {
        guard context.isEnabled else { throw Failure.disabled }
        guard !context.encoderIdentity.isEmpty else { throw Failure.invalidContext }
        guard (1...Self.maximumFeatureCount).contains(featureCount),
              lessons.count <= PersonalInkProfile.maximumExamples else { throw Failure.invalidFeatures }
        let vocabularySet = Set(vocabulary)
        guard (2...512).contains(vocabulary.count), vocabularySet.count == vocabulary.count,
              vocabulary.allSatisfy({ !$0.isEmpty }), lessons.allSatisfy({ vocabularySet.contains($0.label) }) else {
            throw Failure.invalidLabels
        }
        for lesson in lessons {
            try Self.validateFeature(lesson.features, count: featureCount)
            try Self.validateScores(lesson.baseScores, count: vocabulary.count)
        }
        guard (2...Self.maximumAnchorCount).contains(bank.vocabulary.count),
              bank.features.count == bank.vocabulary.count,
              Set(bank.vocabulary).count == bank.vocabulary.count,
              Set(bank.vocabulary).isSubset(of: vocabularySet) else { throw Failure.invalidLabels }
        for anchor in bank.features { try Self.validateFeature(anchor, count: featureCount) }

        self.context = context
        self.vocabulary = vocabulary
        self.featureCount = featureCount
        lessonCount = lessons.count
        let taught = Set(lessons.map(\.label))
        let anchors = zip(bank.vocabulary, bank.features).compactMap { label, feature in
            taught.contains(label) ? nil : feature
        }
        activeAnchorCount = anchors.count

        // The Python reference returns its empty local head before adding
        // anchors. Public anchors can constrain a learned correction, but can
        // never create one in the absence of an explicit lesson.
        guard !lessons.isEmpty else {
            points = []
            coefficients = []
            return
        }
        let fittedPoints = lessons.map(\.features) + anchors
        guard fittedPoints.count <= Self.maximumFitPointCount else { throw Failure.invalidFeatures }
        points = fittedPoints

        let frequencies = Dictionary(grouping: lessons, by: \.label).mapValues(\.count)
        let balance = lessons.map { 1 / sqrt(Double(frequencies[$0.label]!)) }
            + Array(repeating: 1.0, count: anchors.count)
        let count = fittedPoints.count
        var lower = [Double](repeating: 0, count: count * count)
        for i in 0..<count {
            for j in 0...i {
                var value = Self.rbf(fittedPoints[i], fittedPoints[j]) * balance[i] * balance[j]
                if i == j { value += Self.regularization }
                for k in 0..<j { value -= lower[i * count + k] * lower[j * count + k] }
                if i == j {
                    guard value.isFinite, value > 0 else { throw Failure.numericalFailure }
                    lower[i * count + j] = sqrt(value)
                } else {
                    let diagonal = lower[j * count + j]
                    guard diagonal.isFinite, diagonal > 0 else { throw Failure.numericalFailure }
                    lower[i * count + j] = value / diagonal
                }
            }
        }

        var solved = Array(repeating: Array(repeating: 0.0, count: vocabulary.count), count: count)
        for column in vocabulary.indices {
            var beta = [Double](repeating: 0, count: count)
            for i in lessons.indices {
                beta[i] = ((lessons[i].label == vocabulary[column] ? 1.0 : 0.0)
                    - lessons[i].baseScores[column]) * balance[i]
            }
            for i in 0..<count {
                for j in 0..<i { beta[i] -= lower[i * count + j] * beta[j] }
                beta[i] /= lower[i * count + i]
            }
            for i in (0..<count).reversed() {
                if i + 1 < count {
                    for j in (i + 1)..<count { beta[i] -= lower[j * count + i] * beta[j] }
                }
                beta[i] /= lower[i * count + i]
            }
            for i in 0..<count {
                let coefficient = beta[i] * balance[i]
                guard coefficient.isFinite else { throw Failure.numericalFailure }
                solved[i][column] = coefficient
            }
        }
        coefficients = solved
    }

    func rankedCandidates(features: [Double], baseScores: [Double], currentContext: Context) throws -> [Candidate] {
        guard currentContext.isEnabled else { throw Failure.disabled }
        guard currentContext == context else { throw Failure.staleContext }
        try Self.validateFeature(features, count: featureCount)
        try Self.validateScores(baseScores, count: vocabulary.count)
        var adjusted = baseScores
        for i in points.indices {
            let similarity = Self.rbf(features, points[i])
            for column in vocabulary.indices { adjusted[column] += similarity * coefficients[i][column] }
        }
        guard adjusted.allSatisfy(\.isFinite) else { throw Failure.numericalFailure }
        return vocabulary.indices.map { Candidate(label: vocabulary[$0], score: adjusted[$0]) }
            .sorted { $0.score == $1.score ? $0.label < $1.label : $0.score > $1.score }
    }

    private static func rbf(_ left: [Double], _ right: [Double]) -> Double {
        var leftNorm = 0.0
        var rightNorm = 0.0
        var innerProduct = 0.0
        for i in left.indices {
            leftNorm += left[i] * left[i]
            rightNorm += right[i] * right[i]
            innerProduct += left[i] * right[i]
        }
        let squaredDistance = max(leftNorm + rightNorm - 2 * innerProduct, 0)
        return exp(-max(squaredDistance, 0) / kernelWidth)
    }

    private static func validateFeature(_ features: [Double], count: Int) throws {
        guard features.count == count, features.allSatisfy(\.isFinite),
              abs(sqrt(zip(features, features).reduce(0) { $0 + $1.0 * $1.1 }) - 1) <= 1e-3 else {
            throw Failure.invalidFeatures
        }
    }

    private static func validateScores(_ scores: [Double], count: Int) throws {
        guard scores.count == count, scores.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
              abs(scores.reduce(0, +) - 1) <= 1e-8 else { throw Failure.invalidScores }
    }
}
