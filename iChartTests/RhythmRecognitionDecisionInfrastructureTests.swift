import XCTest
@testable import iChart

final class RhythmRecognitionDecisionInfrastructureTests: XCTestCase {
    func testDecisionContractDocumentsRecognizerOutputSurface() throws {
        let projectRoot = try Self.projectRoot()
        let contractText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("docs/rhythm-recognition/recognizer-decision-contract.md")
        )
        let recognitionTypesText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("iChart/Features/Editor/Components/RhythmicNotationRecognitionTypes.swift")
        )

        XCTAssertTrue(contractText.contains("Recognizer Decision Contract"))
        XCTAssertTrue(contractText.contains("commit"))
        XCTAssertTrue(contractText.contains("keepWriting"))
        XCTAssertTrue(contractText.contains("needsReview"))
        XCTAssertTrue(contractText.contains("neighboring notes cannot donate noteheads"))
        XCTAssertTrue(contractText.contains("visualTokens"))
        XCTAssertTrue(contractText.contains("groupingBoundaries"))
        XCTAssertTrue(recognitionTypesText.contains("enum RhythmRecognitionDecision"))
        XCTAssertTrue(recognitionTypesText.contains("case commit"))
        XCTAssertTrue(recognitionTypesText.contains("case keepWriting"))
        XCTAssertTrue(recognitionTypesText.contains("case needsReview"))
        XCTAssertTrue(recognitionTypesText.contains("struct RhythmPhraseHypothesis"))
    }

    func testGoldenFixtureMatrixCoversCurrentSafetyHotspots() throws {
        let projectRoot = try Self.projectRoot()
        let matrixText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("docs/rhythm-recognition/golden-fixture-matrix.md")
        )
        let fixtureIDs = Self.goldenFixtures.map(\.id)

        XCTAssertEqual(Set(fixtureIDs).count, fixtureIDs.count)
        XCTAssertTrue(matrixText.contains("Golden Fixture Matrix"))
        XCTAssertTrue(matrixText.contains("mustCommit"))
        XCTAssertTrue(matrixText.contains("mustKeepWriting"))
        XCTAssertTrue(matrixText.contains("mustReview"))
        XCTAssertTrue(matrixText.contains("mustRejectAutoCommit"))

        for fixture in Self.goldenFixtures {
            XCTAssertTrue(
                matrixText.contains(fixture.id),
                "Missing fixture id in matrix: \(fixture.id)"
            )
        }

        XCTAssertTrue(
            Self.goldenFixtures.contains {
                $0.id == "eighth-rest-plus-eighth-not-note-pair"
                    && $0.decision == .mustRejectAutoCommit
                    && $0.expectedValues == [.eighthRest, .eighth]
            }
        )
        XCTAssertTrue(
            Self.goldenFixtures.contains {
                $0.id == "dotted-quarter-eighth-eighth-dotted-quarter"
                    && $0.decision == .mustRejectAutoCommit
                    && $0.expectedValues == [.dottedQuarter, .eighth, .eighth, .dottedQuarter]
            }
        )
        XCTAssertTrue(
            Self.goldenFixtures.contains {
                $0.id == "underfilled-clean-pair"
                    && $0.decision == .mustKeepWriting
                    && $0.expectedValues == [.eighthRest, .eighth]
            }
        )
        XCTAssertTrue(
            Self.goldenFixtures.contains {
                $0.id == "overflow-five-quarters"
                    && $0.decision == .mustReview
                    && $0.expectedValues == [.quarter, .quarter, .quarter, .quarter, .quarter]
            }
        )
    }

    func testGoldenSupportedFixturesUseOnlyCurrentRhythmValues() {
        let currentAutoCommitFixtures = Self.goldenFixtures.filter { $0.decision == .mustCommit }

        XCTAssertFalse(currentAutoCommitFixtures.isEmpty)
        XCTAssertTrue(
            currentAutoCommitFixtures.allSatisfy { fixture in
                fixture.expectedValues.allSatisfy(\.isCurrentlyCommitSupportedByGoldenMatrix)
            }
        )
    }

    private static func projectRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static let goldenFixtures: [GoldenRhythmFixture] = [
        GoldenRhythmFixture(
            id: "slash-four-beats",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.slash, .slash, .slash, .slash],
            decision: .mustCommit
        ),
        GoldenRhythmFixture(
            id: "quarter-four-beats",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.quarter, .quarter, .quarter, .quarter],
            decision: .mustCommit
        ),
        GoldenRhythmFixture(
            id: "whole-note-full-measure",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.whole],
            decision: .mustCommit
        ),
        GoldenRhythmFixture(
            id: "two-half-notes",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.half, .half],
            decision: .mustCommit
        ),
        GoldenRhythmFixture(
            id: "dotted-half-quarter",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.dottedHalf, .quarter],
            decision: .mustCommit
        ),
        GoldenRhythmFixture(
            id: "dotted-quarter-eighth-half",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.dottedQuarter, .eighth, .half],
            decision: .mustCommit
        ),
        GoldenRhythmFixture(
            id: "quarter-rest-quarter-rest-half",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.quarterRest, .quarter, .quarterRest, .quarter],
            decision: .mustCommit
        ),
        GoldenRhythmFixture(
            id: "eighth-pair-first-beat",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.eighth, .eighth, .quarter, .quarter, .quarter],
            decision: .mustCommit
        ),
        GoldenRhythmFixture(
            id: "eighth-rest-eighth-quarter-half",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.eighthRest, .eighth, .quarter, .half],
            decision: .mustCommit
        ),
        GoldenRhythmFixture(
            id: "eighth-rest-plus-eighth-not-note-pair",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.eighthRest, .eighth],
            decision: .mustRejectAutoCommit
        ),
        GoldenRhythmFixture(
            id: "dotted-quarter-eighth-eighth-dotted-quarter",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.dottedQuarter, .eighth, .eighth, .dottedQuarter],
            decision: .mustRejectAutoCommit
        ),
        GoldenRhythmFixture(
            id: "underfilled-clean-pair",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.eighthRest, .eighth],
            decision: .mustKeepWriting
        ),
        GoldenRhythmFixture(
            id: "overflow-five-quarters",
            meter: Meter(numerator: 4, denominator: 4),
            expectedValues: [.quarter, .quarter, .quarter, .quarter, .quarter],
            decision: .mustReview
        )
    ]
}

private struct GoldenRhythmFixture: Hashable {
    let id: String
    let meter: Meter
    let expectedValues: [RhythmValue]
    let decision: GoldenRhythmDecision
}

private enum GoldenRhythmDecision: Hashable {
    case mustCommit
    case mustKeepWriting
    case mustReview
    case mustRejectAutoCommit
}

private extension RhythmValue {
    var isCurrentlyCommitSupportedByGoldenMatrix: Bool {
        switch self {
        case .slash, .eighth, .eighthRest, .quarter, .quarterRest, .dottedQuarter,
                .half, .halfRest, .dottedHalf, .whole, .wholeRest:
            return true
        case .tiedContinuation:
            return false
        }
    }
}
