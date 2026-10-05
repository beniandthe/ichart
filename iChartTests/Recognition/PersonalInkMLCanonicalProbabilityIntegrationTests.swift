import XCTest
@testable import iChart

/// Synthetic adapter/decoder integration, not handwriting-accuracy evidence.
final class PersonalInkMLCanonicalProbabilityIntegrationTests: XCTestCase {
    private final class Encoder: PersonalInkVisualEncoding {
        let identity = "synthetic-full-distribution-only"
        let vocabulary = ["!", "?", "H", "C"]
        var inputs: [[InkStroke]] = []
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            inputs.append(strokes)
            return .init(embedding: [1] + Array(repeating: 0, count: 127),
                genericLogits: [0.4, 0.3, 0.2, 0.1].map { log($0) })
        }
    }
    private var ink: [InkStroke] {
        [.init(points: [.init(x: 0, y: 0), .init(x: 8, y: 20)]),
         .init(points: [.init(x: 6, y: 3), .init(x: 4, y: 12)])]
    }
    private func profile() -> PersonalInkProfile {
        var profile = PersonalInkProfile(); profile.isEnabled = true
        return profile
    }

    func testOptInFullDistributionRetainsRankFourEvidenceButDoesNotPromoteItPastForbiddenWinner() throws {
        let profile = profile(), encoder = Encoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder, grouping: .losslessSourceV2)
        let before = try model.readSuppliedOriginalGroups(ink, originalIndexGroups: [[1, 0]], currentProfile: profile)
        XCTAssertEqual(before.glyphs[0].generic.map(\.label), ["!", "?", "H"])
        let receipt = try model.readSuppliedOriginalCanonicalHypotheses(ink,
            originalIndexGroups: [[1, 0]], currentProfile: profile)
        XCTAssertEqual(receipt.genericVocabulary, encoder.vocabulary)
        XCTAssertEqual(receipt.columns[0].probabilities.count, 4)
        XCTAssertEqual(receipt.columns[0].probabilities.map(\.label), ["!", "?", "H", "C"])
        for (actual, expected) in zip(
            receipt.columns[0].probabilities.map(\.probability),
            [0.4, 0.3, 0.2, 0.1]
        ) {
            XCTAssertEqual(actual, expected, accuracy: 1e-12)
        }
        XCTAssertEqual(receipt.columns[0].originalStrokeIndexes, [0, 1])
        XCTAssertEqual(
            receipt.hypotheses.version,
            "canonical-probability-lattice-v2-chord-domain-v1"
        )
        XCTAssertEqual(receipt.hypotheses.totalSequenceCount, 4)
        XCTAssertEqual(receipt.hypotheses.examinedSequenceCount, 4)
        XCTAssertTrue(receipt.hypotheses.searchComplete)
        XCTAssertTrue(receipt.hypotheses.candidates.isEmpty)
        XCTAssertEqual(receipt.hypotheses.observedAcceptedProbabilityMass, 0, accuracy: 1e-12)
        XCTAssertEqual(receipt.hypotheses.rejectedGrammarProbabilityMass, 1, accuracy: 1e-12)
        XCTAssertEqual(receipt.hypotheses.examinedProbabilityMass, 1, accuracy: 1e-12)
        XCTAssertEqual(receipt.hypotheses.unexaminedProbabilityMassUpperBound, 0, accuracy: 1e-12)
        XCTAssertNil(receipt.hypotheses.rankingCertificate)
        XCTAssertEqual(encoder.inputs, [ink, ink])
        let after = try model.readSuppliedOriginalGroups(ink, originalIndexGroups: [[1, 0]], currentProfile: profile)
        XCTAssertEqual(after, before)
        XCTAssertEqual(model.profile, profile)
        XCTAssertTrue(profile.examples.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(PersonalInkLearnedComparison.CanonicalProbabilityIdentityReading.self,
            from: JSONEncoder().encode(receipt)), receipt)
    }

    func testSelectiveAndLegacyRoutesCannotBypassOwnershipBoundary() throws {
        for grouping in [PersonalInkLearnedComparison.Grouping.legacyGeometryV1, .selectiveLosslessOwnershipV3] {
            let profile = profile(), encoder = Encoder()
            let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder, grouping: grouping)
            XCTAssertThrowsError(try model.readSuppliedOriginalCanonicalHypotheses(ink,
                originalIndexGroups: [[0, 1]], currentProfile: profile)) { error in
                guard case PersonalInkLearnedComparison.Failure.unsupportedHypothesisGrouping = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertTrue(encoder.inputs.isEmpty)
        }
    }

    func testInvalidPartitionDisabledOrStaleProfileStopsBeforeQueryEncoding() throws {
        let profile = profile(), encoder = Encoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder, grouping: .losslessSourceV2)
        for groups in [[], [[0]], [[0], [0]], [[-1, 1]], [[0, 2]], [[0, 0, 1]]] {
            XCTAssertThrowsError(try model.readSuppliedOriginalCanonicalHypotheses(ink,
                originalIndexGroups: groups, currentProfile: profile))
        }
        var disabled = profile; disabled.isEnabled = false
        XCTAssertThrowsError(try model.readSuppliedOriginalCanonicalHypotheses(ink,
            originalIndexGroups: [[0, 1]], currentProfile: disabled))
        var stale = profile; stale.revision = UUID()
        XCTAssertThrowsError(try model.readSuppliedOriginalCanonicalHypotheses(ink,
            originalIndexGroups: [[0, 1]], currentProfile: stale))
        XCTAssertThrowsError(try model.readSuppliedOriginalCanonicalHypotheses(ink,
            originalIndexGroups: [[0, 1]], currentProfile: profile, maximumExaminedSequences: 0))
        XCTAssertThrowsError(try model.readSuppliedOriginalCanonicalHypotheses(ink,
            originalIndexGroups: [[0, 1]], currentProfile: profile, maximumReturnedCandidates: 0))
        XCTAssertTrue(encoder.inputs.isEmpty)
    }
}
