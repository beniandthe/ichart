import XCTest
@testable import iChart

/// Safety regressions for visible, repeatedly tuned legacy fixtures.
///
/// Passing this suite does not measure accuracy on unseen writers and must not
/// be reported as user-agnostic recognition evidence.
// Keep the historical XCTest class/method names so old focused commands cannot
// silently select zero tests. The names are compatibility shims only; this is a
// legacy safety-regression suite, not writer-independent acceptance evidence.
final class ChordInkTrustAcceptanceTests: XCTestCase {
    private let recognizer = ChordInkMaximumTrustRecognizer()

    private enum Perturbation: String, CaseIterable {
        case identity
        case translated
        case scaledDown
        case scaledUp
        case rotatedCounterclockwise
        case rotatedClockwise
        case densityNormalized
        case thinnedPoints
        case thinnedThenResampled

        var isLossyStress: Bool {
            self == .thinnedPoints || self == .thinnedThenResampled
        }
    }

    private struct PerturbationAudit {
        var sampleCount = 0
        var trustedCorrectCount = 0
        var trustedWrongReads: [String] = []
        var trustedWithoutCorroboration: [String] = []
        var confirmationPrimaryCorrectCount = 0
        var confirmationRecoverableCount = 0
        var confirmationVisibleRecoveryCount = 0
        var confirmationHiddenRecoveryCount = 0
        var confirmationManualOnlyCount = 0
        var noReadCount = 0
        var confirmationRecoverableDetails: [String] = []
        var confirmationManualOnlyDetails: [String] = []
        var noReadDetails: [String] = []
        var trustedCorrectLedgerAgreements: [ChordInkSymbolLedgerAgreement: Int] = [:]
        var trustedWrongLedgerAgreements: [ChordInkSymbolLedgerAgreement: Int] = [:]
        var trustEvidenceOutcomes: [ChordInkTrustEvidenceOutcome: Int] = [:]
        var trustedCorrectWithCompetingEvidenceCount = 0
        var trustedWrongWithCompetingEvidenceCount = 0
        var validationMilliseconds: [Double] = []
        var totalMilliseconds: [Double] = []

        mutating func recordLedgerAgreement(
            _ assessment: ChordInkSymbolLedgerAssessment?,
            isCorrect: Bool
        ) {
            let resolvedAgreement = assessment?.agreement ?? .noLedgerEvidence
            if isCorrect {
                trustedCorrectLedgerAgreements[resolvedAgreement, default: 0] += 1
                if assessment?.competingDisplayTexts.isEmpty == false {
                    trustedCorrectWithCompetingEvidenceCount += 1
                }
            } else {
                trustedWrongLedgerAgreements[resolvedAgreement, default: 0] += 1
                if assessment?.competingDisplayTexts.isEmpty == false {
                    trustedWrongWithCompetingEvidenceCount += 1
                }
            }
        }
    }

    func testPerturbationAuditPreservesCapturedStrokeChronology() throws {
        let fixture = try InkFixtureLoader.load(
            "FSharpRaisedBarsSimpleDeviceCaptured01",
            file: #filePath
        )
        XCTAssertTrue(fixture.strokes.allSatisfy { $0.creationTimeOffset != nil })
        let creationTimes = fixture.strokes.map(\.creationTimeOffset)
        let startTimes = fixture.strokes.map(\.timelineStartTimeOffset)
        let endTimes = fixture.strokes.map(\.timelineEndTimeOffset)

        for perturbation in Perturbation.allCases {
            let perturbed = transformed(fixture.strokes, by: perturbation)
            XCTAssertEqual(perturbed.count, fixture.strokes.count, perturbation.rawValue)
            XCTAssertEqual(
                perturbed.map(\.creationTimeOffset),
                creationTimes,
                "\(perturbation.rawValue) must preserve captured cross-stroke chronology"
            )
            XCTAssertEqual(perturbed.map(\.timelineStartTimeOffset), startTimes, perturbation.rawValue)
            XCTAssertEqual(perturbed.map(\.timelineEndTimeOffset), endTimes, perturbation.rawValue)
        }
    }

    func testTrustAcceptanceFixtureSetIncludesRequiredFamilies() throws {
        let fixtureNames = Set(InkFixtureLoader.legacySafetyRegressionFixtureNames)

        XCTAssertTrue(fixtureNames.isSuperset(of: [
            "A",
            "B",
            "D",
            "E",
            "F",
            "G",
            "ARootSplitDevice01",
            "DFlatMinorCaptured01",
            "DFlat7susCaptured03",
            "GSlashBCaptured01",
            "CMajor7Captured01",
            "C7susCaptured03",
            "C7Flat9Captured01",
            "C7Sharp11Captured01",
            "C7altCaptured03",
            "DSlashFSharpLooseDevice01",
            "ChordRepeatCaptured01"
        ]))
    }

    func testRecognizesTrustAcceptanceFixtureSet() throws {
        let fixtures = try InkFixtureLoader.loadLegacySafetyRegressionFixtures(file: #filePath)

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), scores: \(result.candidateScores.prefix(8))"

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, "\(fixture.name) \(debugSummary)")
            XCTAssertEqual(decision.acceptedText, fixture.expectedDisplayText, fixture.name)
        }
    }

    func testLooseDSlashFSharpDeviceFixtureStaysPrimaryButRequiresConfirmation() throws {
        let fixture = try InkFixtureLoader.load("DSlashFSharpLooseDevice01", file: #filePath)
        let result = recognizer.recognize(strokes: fixture.strokes)
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let rankedScores = ChordInkRecognitionPolicy.rankedSupportedScores(for: result)
        let rankedDisplayTexts = rankedScores.compactMap(\.displayText)
        let glyphSummary = result.glyphCandidates.map { group in
            group.prefix(8).map { "\($0.text):\($0.confidence)" }
        }
        let debugSummary = """
        raw: \(Array(result.rawCandidates.prefix(16)))
        glyphs: \(glyphSummary)
        scores: \(result.candidateScores.prefix(8))
        decision: \(decision)
        """

        XCTAssertEqual(result.match?.displayText, "D/F#", debugSummary)
        XCTAssertEqual(decision.acceptedText, "D/F#", debugSummary)
        XCTAssertEqual(decision.action, .confirm, debugSummary)
        // The captured single-bowl D now has stronger contour evidence. The
        // safety contract is confirmation without corroboration, not a frozen
        // D/B score-gap classification inside the primary decision.
        XCTAssertNotEqual(result.trustEvidence?.outcome, .corroborated, debugSummary)
        XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, debugSummary)
        XCTAssertEqual(result.glyphCandidates.first?.first?.text, "D", debugSummary)
        XCTAssertEqual(Array(rankedDisplayTexts.prefix(2)), ["D/F#", "B/F#"], debugSummary)
        XCTAssertTrue(
            Array(ChordInkRenderResolutionPolicy.candidateTexts(for: result).prefix(3))
                .contains("D/F#"),
            debugSummary
        )
    }

    func testDFlat13ScaleBoundaryNeverBecomesTrustedWrongRead() throws {
        let fixture = try InkFixtureLoader.load("DFlat13Captured03", file: #filePath)
        let variants: [Perturbation] = [.identity, .scaledDown, .scaledUp]
        var trustedWrongReads: [String] = []

        for variant in variants {
            let result = recognizer.recognize(
                strokes: transformed(fixture.strokes, by: variant),
                options: .includingSymbolLedgerDiagnostics
            )
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            let rankedScores = ChordInkRecognitionPolicy.rankedSupportedScores(for: result)
            let glyphs = result.glyphCandidates.map { column in
                column.prefix(8).map { "\($0.text):\(String(format: "%.3f", $0.confidence))" }
            }
            let summary = "\(variant.rawValue) decision=\(decision) scores=\(rankedScores) glyphs=\(glyphs) ledger=\(String(describing: result.symbolLedgerAssessment))"
            print("chord_trust_scale_boundary \(summary)")
            if decision.action == .trusted,
               decision.acceptedText != fixture.expectedDisplayText {
                trustedWrongReads.append(summary)
            }
        }

        XCTAssertTrue(
            trustedWrongReads.isEmpty,
            "Scale variation must confirm instead of trusting a wrong chord:\n\(trustedWrongReads.joined(separator: "\n"))"
        )
    }

    func testReviewRecoveryCannotPromoteAnUncorroboratedPrimaryRead() throws {
        let fixture = try InkFixtureLoader.load("FSharpm7Captured02", file: #filePath)
        let result = recognizer.recognize(
            strokes: transformed(fixture.strokes, by: .densityNormalized),
            options: .includingSymbolLedgerDiagnostics
        )
        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.acceptedText, "F#-7")
        XCTAssertEqual(decision.action, .confirm)
        XCTAssertNotEqual(result.trustEvidence?.outcome, .corroborated)
        XCTAssertTrue(
            ChordInkRenderResolutionPolicy.candidateTexts(for: result).contains("F#-7")
        )
    }

    func testTrustAcceptanceFixturesNeverProduceTrustedWrongReadsUnderDeterministicPerturbations() throws {
        let fixtures = try InkFixtureLoader.loadLegacySafetyRegressionFixtures(file: #filePath)

        try assertNoTrustedWrongReads(
            fixtures: fixtures,
            perturbations: Perturbation.allCases
        )
    }

    func testFullFixtureArchiveNeverProducesTrustedWrongReadsUnderDeterministicPerturbationsWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to audit the full fixture archive."
        )

        try assertNoTrustedWrongReads(
            fixtures: InkFixtureLoader.loadAll(file: #filePath),
            perturbations: Perturbation.allCases
        )
    }

    func testFullFixtureArchiveReportsLossyPointDensityStressWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to audit the full fixture archive."
        )

        try assertNoTrustedWrongReads(
            fixtures: InkFixtureLoader.loadAll(file: #filePath),
            perturbations: [.thinnedPoints]
        )
    }

    func testFullFixtureArchiveReportsIdentityTrustWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to audit the full fixture archive."
        )

        try assertNoTrustedWrongReads(
            fixtures: InkFixtureLoader.loadAll(file: #filePath),
            perturbations: [.identity]
        )
    }

    func testFullFixtureArchiveReportsRecognitionLatencyOutliersWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to audit the full fixture archive."
        )

        struct Observation {
            var fixtureName: String
            var expectedText: String
            var acceptedText: String?
            var action: ChordInkRecognitionAction
            var trustOutcome: ChordInkTrustEvidenceOutcome?
            var metrics: ChordInkRecognitionMetrics
        }

        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        let observations = fixtures.map { fixture in
            let result = recognizer.recognize(
                strokes: fixture.strokes,
                options: .includingSymbolLedgerDiagnostics
            )
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            return Observation(
                fixtureName: fixture.name,
                expectedText: fixture.expectedDisplayText,
                acceptedText: decision.acceptedText,
                action: decision.action,
                trustOutcome: result.trustEvidence?.outcome,
                metrics: result.metrics
            )
        }
        let slowest = observations
            .sorted { $0.metrics.totalMilliseconds > $1.metrics.totalMilliseconds }
            .prefix(20)

        for observation in slowest {
            let metrics = observation.metrics
            let acceptedText = observation.acceptedText ?? "nil"
            let trustOutcome = observation.trustOutcome?.rawValue ?? "none"
            let totalMilliseconds = String(format: "%.3f", metrics.totalMilliseconds)
            let clusterMilliseconds = String(format: "%.3f", metrics.clusterMilliseconds)
            let glyphMilliseconds = String(format: "%.3f", metrics.glyphMilliseconds)
            let contextualMilliseconds = String(format: "%.3f", metrics.contextualGlyphMilliseconds)
            let composeMilliseconds = String(format: "%.3f", metrics.composeMilliseconds)
            let semanticMilliseconds = String(format: "%.3f", metrics.semanticMilliseconds)
            let matchMilliseconds = String(format: "%.3f", metrics.matchMilliseconds)
            let validationMilliseconds = String(
                format: "%.3f",
                observation.metrics.totalMilliseconds
                    - metrics.clusterMilliseconds
                    - metrics.glyphMilliseconds
                    - metrics.contextualGlyphMilliseconds
                    - metrics.composeMilliseconds
                    - metrics.semanticMilliseconds
                    - metrics.matchMilliseconds
            )
            print(
                [
                    "chord_latency_outlier",
                    "fixture=\(observation.fixtureName)",
                    "expected=\(observation.expectedText)",
                    "accepted=\(acceptedText)",
                    "action=\(observation.action.rawValue)",
                    "trust=\(trustOutcome)",
                    "total_ms=\(totalMilliseconds)",
                    "cluster_ms=\(clusterMilliseconds)",
                    "glyph_ms=\(glyphMilliseconds)",
                    "context_ms=\(contextualMilliseconds)",
                    "compose_ms=\(composeMilliseconds)",
                    "semantic_ms=\(semanticMilliseconds)",
                    "match_ms=\(matchMilliseconds)",
                    "validation_ms=\(validationMilliseconds)",
                    "strokes=\(metrics.strokeCount)",
                    "clusters=\(metrics.clusterCount)",
                    "selected_columns=\(metrics.compositionMetrics.selectedColumnCount)",
                    "generated=\(metrics.compositionMetrics.generatedSequenceCount)",
                    "limit_hit=\(metrics.compositionMetrics.hitGeneratedSequenceLimit)"
                ].joined(separator: " ")
            )
        }

        XCTAssertEqual(observations.count, fixtures.count)
    }

    func testFullFixtureArchiveReportsCandidateSequenceBudgetTradeoffsWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to audit the full fixture archive."
        )

        struct UserFacingFingerprint: Equatable {
            var acceptedText: String?
            var action: ChordInkRecognitionAction
            var suggestions: [String]
        }

        struct BudgetAudit {
            var durationMilliseconds: [Double] = []
            var userFacingDifferences: [String] = []
            var exactPrimaryDifferences: [String] = []
            var sequenceLimitHitCount = 0
        }

        func recognizer(sequenceBudget: Int) -> ChordInkRecognizer {
            var configuration = ChordInkCandidateComposerConfiguration.chordSymbols
            configuration.maxGeneratedSequences = sequenceBudget
            return ChordInkRecognizer(
                candidateComposer: ChordInkCandidateComposer(configuration: configuration)
            )
        }

        func fingerprint(_ result: ChordInkRecognitionResult) -> UserFacingFingerprint {
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            return UserFacingFingerprint(
                acceptedText: decision.acceptedText,
                action: decision.action,
                suggestions: ChordInkRenderResolutionPolicy.candidateTexts(for: result)
            )
        }

        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        let baselineRecognizer = recognizer(sequenceBudget: 4_096)
        let budgets = [3_072, 2_048, 1_536, 1_024, 768, 512]
        let alternatives = Dictionary(
            uniqueKeysWithValues: budgets.map { ($0, recognizer(sequenceBudget: $0)) }
        )
        var audits = Dictionary(
            uniqueKeysWithValues: budgets.map { ($0, BudgetAudit()) }
        )

        for fixture in fixtures {
            let baseline = baselineRecognizer.recognize(strokes: fixture.strokes)
            let baselineFingerprint = fingerprint(baseline)

            for budget in budgets {
                guard let alternativeRecognizer = alternatives[budget] else {
                    XCTFail("Missing recognizer for candidate sequence budget \(budget)")
                    continue
                }
                let alternative = alternativeRecognizer.recognize(strokes: fixture.strokes)
                audits[budget, default: BudgetAudit()]
                    .durationMilliseconds.append(alternative.metrics.totalMilliseconds)
                if alternative.metrics.compositionMetrics.hitGeneratedSequenceLimit {
                    audits[budget, default: BudgetAudit()].sequenceLimitHitCount += 1
                }

                let alternativeFingerprint = fingerprint(alternative)
                if alternativeFingerprint != baselineFingerprint {
                    audits[budget, default: BudgetAudit()].userFacingDifferences.append(
                        "\(fixture.name) expected=\(fixture.expectedDisplayText) baseline=\(baselineFingerprint) alternative=\(alternativeFingerprint)"
                    )
                }
                if alternative.match?.displayText != baseline.match?.displayText
                    || alternative.confidence != baseline.confidence {
                    audits[budget, default: BudgetAudit()].exactPrimaryDifferences.append(
                        "\(fixture.name) expected=\(fixture.expectedDisplayText) baseline=\(baseline.match?.displayText ?? "nil")@\(baseline.confidence) alternative=\(alternative.match?.displayText ?? "nil")@\(alternative.confidence)"
                    )
                }
            }
        }

        for budget in budgets {
            let audit = audits[budget, default: BudgetAudit()]
            print(
                [
                    "chord_candidate_budget_audit",
                    "budget=\(budget)",
                    "samples=\(fixtures.count)",
                    "user_facing_differences=\(audit.userFacingDifferences.count)",
                    "exact_primary_differences=\(audit.exactPrimaryDifferences.count)",
                    "sequence_limit_hits=\(audit.sequenceLimitHitCount)",
                    "latency_ms=\(latencySummary(audit.durationMilliseconds))",
                    "user_facing_examples=\(Array(audit.userFacingDifferences.prefix(8)))",
                    "primary_examples=\(Array(audit.exactPrimaryDifferences.prefix(8)))"
                ].joined(separator: " ")
            )
        }

        XCTAssertEqual(audits.count, budgets.count)
    }

    func testFullFixtureArchiveReportsResampledPointDensityStressWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to audit the full fixture archive."
        )

        try assertNoTrustedWrongReads(
            fixtures: InkFixtureLoader.loadAll(file: #filePath),
            perturbations: [.thinnedThenResampled]
        )
    }

    func testFullFixtureArchiveAcceptsAdaptivePointDensityNormalizationWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to audit the full fixture archive."
        )

        try assertNoTrustedWrongReads(
            fixtures: InkFixtureLoader.loadAll(file: #filePath),
            perturbations: [.densityNormalized]
        )
    }

    func testFullFixtureArchiveReportsSevenNineAmbiguityWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to audit the full fixture archive."
        )

        let baseRecognizer = ChordInkRecognizer()
        var caseCount = 0
        for fixture in try InkFixtureLoader.loadAll(file: #filePath) {
            for perturbation in [Perturbation.identity, .thinnedPoints] {
                let strokes = transformed(fixture.strokes, by: perturbation)
                let result = baseRecognizer.recognize(strokes: strokes)
                let decision = ChordInkRecognitionPolicy.decision(for: result)
                let clusters = StrokeClusterer().cluster(strokes)
                for (columnIndex, column) in result.glyphCandidates.enumerated()
                where column.first?.text == "7" {
                    guard let nine = column.first(where: { $0.text == "9" }),
                          nine.confidence >= 0.50 else {
                        continue
                    }

                    caseCount += 1
                    let cluster = clusters.indices.contains(columnIndex)
                        ? clusters[columnIndex]
                        : InkCluster(strokes: [])
                    let segmentLengths = cluster.strokes.flatMap { stroke in
                        zip(stroke.points, stroke.points.dropFirst()).map { start, end in
                            hypot(end.x - start.x, end.y - start.y)
                        }
                    }.sorted()
                    let medianSegmentLength = segmentLengths.isEmpty
                        ? 0
                        : segmentLengths[segmentLengths.count / 2]
                    print(
                        "chord_seven_nine_case fixture=\(fixture.name) expected=\(fixture.expectedDisplayText) perturbation=\(perturbation.rawValue) base_decision=\(decision.action.rawValue) base_accepted=\(decision.acceptedText ?? "nil") column=\(columnIndex) seven=\(column[0].confidence) nine=\(nine.confidence) cluster_points=\(cluster.strokes.map { $0.points.count }) cluster_median_segment=\(medianSegmentLength) points=\(strokes.map { $0.points.count })"
                    )
                }
            }
        }

        print("chord_seven_nine_summary cases=\(caseCount)")
    }

    func testPreviouslyHiddenRecoveryCandidatesAreVisibleForOneTapReview() throws {
        let cases: [(fixtureName: String, perturbation: Perturbation)] = [
            ("C7Sharp11", .scaledDown),
            ("C7Sharp11Captured01", .scaledDown),
            ("BFlat7Sharp11Captured01", .scaledUp),
            ("BSharp7Flat5Captured02", .scaledUp),
            ("BSharp7Sharp5", .scaledUp),
            ("BFlat7Sharp11", .rotatedCounterclockwise),
            ("FSharp7Flat13", .rotatedCounterclockwise),
            ("DFlat7Flat9Captured02", .thinnedPoints)
        ]

        for testCase in cases {
            let fixture = try InkFixtureLoader.load(testCase.fixtureName, file: #filePath)
            let result = recognizer.recognize(
                strokes: transformed(fixture.strokes, by: testCase.perturbation),
                options: .includingSymbolLedgerDiagnostics
            )
            let candidates = ChordInkRenderResolutionPolicy.candidateTexts(for: result)
            print(
                "chord_hidden_recovery fixture=\(testCase.fixtureName) perturbation=\(testCase.perturbation.rawValue) expected=\(fixture.expectedDisplayText) candidates=\(candidates) primary_scores=\(result.candidateScores) review_scores=\(result.reviewCandidateScores)"
            )

            XCTAssertTrue(
                candidates.contains(fixture.expectedDisplayText),
                "\(testCase.fixtureName) lost its review recovery: \(candidates)"
            )
            XCTAssertTrue(
                candidates.prefix(3).contains(fixture.expectedDisplayText),
                "\(testCase.fixtureName) still hides the correct recovery beyond the three visible choices: \(candidates)"
            )
        }
    }

    private func assertNoTrustedWrongReads(
        fixtures: [InkFixture],
        perturbations: [Perturbation]
    ) throws {
        var audits = Dictionary(
            uniqueKeysWithValues: perturbations.map { ($0, PerturbationAudit()) }
        )

        for fixture in fixtures {
            for perturbation in perturbations {
                let strokes = transformed(fixture.strokes, by: perturbation)
                let result = recognizer.recognize(
                    strokes: strokes,
                    options: .includingSymbolLedgerDiagnostics
                )
                let decision = ChordInkRecognitionPolicy.decision(for: result)
                let primaryText = decision.acceptedText
                let suggestions = ChordInkRenderResolutionPolicy.candidateTexts(for: result)
                let visibleSuggestions = Array(suggestions.prefix(3))
                let label = "\(fixture.name)[\(perturbation.rawValue)]"
                audits[perturbation, default: PerturbationAudit()].sampleCount += 1
                if let outcome = result.trustEvidence?.outcome {
                    audits[perturbation, default: PerturbationAudit()]
                        .trustEvidenceOutcomes[outcome, default: 0] += 1
                    audits[perturbation, default: PerturbationAudit()]
                        .validationMilliseconds.append(result.trustEvidence?.validationMilliseconds ?? 0)
                }
                audits[perturbation, default: PerturbationAudit()]
                    .totalMilliseconds.append(result.metrics.totalMilliseconds)

                switch decision.action {
                case .trusted:
                    let isCorrect = primaryText == fixture.expectedDisplayText
                    if result.trustEvidence?.isCorroborated != true {
                        audits[perturbation, default: PerturbationAudit()]
                            .trustedWithoutCorroboration.append(
                                candidateLossDetail(
                                    category: "trusted_without_corroboration",
                                    label: label,
                                    fixture: fixture,
                                    result: result,
                                    primaryText: primaryText,
                                    suggestions: suggestions
                                )
                            )
                    }
                    audits[perturbation, default: PerturbationAudit()].recordLedgerAgreement(
                        result.symbolLedgerAssessment,
                        isCorrect: isCorrect
                    )
                    if isCorrect {
                        audits[perturbation, default: PerturbationAudit()].trustedCorrectCount += 1
                    } else {
                        let glyphs = result.glyphCandidates.map { column in
                            column.prefix(8).map { "\($0.text):\(String(format: "%.3f", $0.confidence))" }
                        }
                        let pointCounts = strokes.map { $0.points.count }
                        let ledger = result.symbolLedgerAssessment
                        let detail = "\(label) expected=\(fixture.expectedDisplayText) trusted=\(primaryText ?? "nil") suggestions=\(suggestions) raw=\(Array(result.rawCandidates.prefix(16))) scores=\(Array(result.candidateScores.prefix(12))) points=\(pointCounts) glyphs=\(glyphs) ledger=\(ledger?.agreement.rawValue ?? "none") support=\(ledger?.supportCount ?? 0) competing=\(ledger?.competingDisplayTexts ?? []) overlap=\(ledger?.unresolvedOverlapCount ?? 0)"
                        audits[perturbation, default: PerturbationAudit()].trustedWrongReads.append(detail)
                    }
                case .confirm:
                    if primaryText == fixture.expectedDisplayText {
                        audits[perturbation, default: PerturbationAudit()].confirmationPrimaryCorrectCount += 1
                    } else if visibleSuggestions.contains(fixture.expectedDisplayText) {
                        audits[perturbation, default: PerturbationAudit()].confirmationRecoverableCount += 1
                        audits[perturbation, default: PerturbationAudit()].confirmationVisibleRecoveryCount += 1
                        audits[perturbation, default: PerturbationAudit()]
                            .confirmationRecoverableDetails.append(
                                candidateLossDetail(
                                    category: "visible_recovery",
                                    label: label,
                                    fixture: fixture,
                                    result: result,
                                    primaryText: primaryText,
                                    suggestions: suggestions
                                )
                            )
                    } else if suggestions.contains(fixture.expectedDisplayText) {
                        audits[perturbation, default: PerturbationAudit()].confirmationRecoverableCount += 1
                        audits[perturbation, default: PerturbationAudit()].confirmationHiddenRecoveryCount += 1
                        audits[perturbation, default: PerturbationAudit()]
                            .confirmationRecoverableDetails.append(
                                candidateLossDetail(
                                    category: "hidden_recovery",
                                    label: label,
                                    fixture: fixture,
                                    result: result,
                                    primaryText: primaryText,
                                    suggestions: suggestions
                                )
                            )
                    } else if primaryText == nil {
                        audits[perturbation, default: PerturbationAudit()].noReadCount += 1
                        audits[perturbation, default: PerturbationAudit()]
                            .noReadDetails.append(
                                candidateLossDetail(
                                    category: "no_read",
                                    label: label,
                                    fixture: fixture,
                                    result: result,
                                    primaryText: primaryText,
                                    suggestions: suggestions
                                )
                            )
                    } else {
                        audits[perturbation, default: PerturbationAudit()].confirmationManualOnlyCount += 1
                        audits[perturbation, default: PerturbationAudit()]
                            .confirmationManualOnlyDetails.append(
                                candidateLossDetail(
                                    category: "manual_only",
                                    label: label,
                                    fixture: fixture,
                                    result: result,
                                    primaryText: primaryText,
                                    suggestions: suggestions
                                )
                            )
                    }
                }
            }
        }

        for perturbation in perturbations {
            let audit = audits[perturbation, default: PerturbationAudit()]
            print(
                [
                    "chord_trust_audit",
                    "perturbation=\(perturbation.rawValue)",
                    "samples=\(audit.sampleCount)",
                    "lossy_stress=\(perturbation.isLossyStress)",
                    "trusted_correct=\(audit.trustedCorrectCount)",
                    "trusted_wrong=\(audit.trustedWrongReads.count)",
                    "confirm_primary_correct=\(audit.confirmationPrimaryCorrectCount)",
                    "confirm_recoverable=\(audit.confirmationRecoverableCount)",
                    "confirm_visible_recovery=\(audit.confirmationVisibleRecoveryCount)",
                    "confirm_hidden_recovery=\(audit.confirmationHiddenRecoveryCount)",
                    "confirm_manual_only=\(audit.confirmationManualOnlyCount)",
                    "no_read=\(audit.noReadCount)",
                    "trusted_correct_ledger=\(ledgerSummary(audit.trustedCorrectLedgerAgreements))",
                    "trusted_wrong_ledger=\(ledgerSummary(audit.trustedWrongLedgerAgreements))",
                    "trusted_correct_with_competing=\(audit.trustedCorrectWithCompetingEvidenceCount)",
                    "trusted_wrong_with_competing=\(audit.trustedWrongWithCompetingEvidenceCount)",
                    "trust_evidence=\(trustEvidenceSummary(audit.trustEvidenceOutcomes))",
                    "validation_ms=\(latencySummary(audit.validationMilliseconds))",
                    "total_ms=\(latencySummary(audit.totalMilliseconds))"
                ].joined(separator: " ")
            )
            if !audit.trustedWrongReads.isEmpty {
                print(
                    "chord_trust_wrong_reads perturbation=\(perturbation.rawValue)\n"
                        + audit.trustedWrongReads.joined(separator: "\n")
                )
            }
            if !audit.trustedWithoutCorroboration.isEmpty {
                print(
                    "chord_trust_missing_corroboration perturbation=\(perturbation.rawValue)\n"
                        + audit.trustedWithoutCorroboration.joined(separator: "\n")
                )
            }
            let candidateLossDetails = audit.confirmationRecoverableDetails
                + audit.confirmationManualOnlyDetails
                + audit.noReadDetails
            let reportedCandidateLossDetails = perturbation.isLossyStress
                ? audit.confirmationRecoverableDetails.filter {
                    $0.hasPrefix("category=hidden_recovery")
                }
                : candidateLossDetails
            if !reportedCandidateLossDetails.isEmpty {
                print(
                    "chord_trust_candidate_losses perturbation=\(perturbation.rawValue)\n"
                        + reportedCandidateLossDetails.joined(separator: "\n")
                )
            }
        }

        let trustedWrongReads = perturbations
            .flatMap { audits[$0, default: PerturbationAudit()].trustedWrongReads }
        XCTAssertTrue(
            trustedWrongReads.isEmpty,
            "No deterministic perturbation, including destructive density stress, may produce a trusted wrong read:\n\(trustedWrongReads.joined(separator: "\n"))"
        )
        let trustedWithoutCorroboration = perturbations.flatMap {
            audits[$0, default: PerturbationAudit()].trustedWithoutCorroboration
        }
        XCTAssertTrue(
            trustedWithoutCorroboration.isEmpty,
            "Maximum-trust output may never render without corroborated evidence:\n\(trustedWithoutCorroboration.joined(separator: "\n"))"
        )
        let hiddenRecoveries = perturbations.flatMap { perturbation in
            audits[perturbation, default: PerturbationAudit()]
                .confirmationRecoverableDetails
                .filter { $0.hasPrefix("category=hidden_recovery") }
        }
        XCTAssertTrue(
            hiddenRecoveries.isEmpty,
            "A correct recovery candidate may not be hidden beyond the three one-tap choices:\n\(hiddenRecoveries.joined(separator: "\n"))"
        )

        if perturbations.contains(.identity) {
            let identityAudit = audits[.identity, default: PerturbationAudit()]
            let correctPrimaryCount = identityAudit.trustedCorrectCount
                + identityAudit.confirmationPrimaryCorrectCount
            XCTAssertEqual(
                correctPrimaryCount,
                identityAudit.sampleCount,
                "Every native-size fixture must keep the labeled chord as its primary read."
            )
        }
    }

    private func candidateLossDetail(
        category: String,
        label: String,
        fixture: InkFixture,
        result: ChordInkRecognitionResult,
        primaryText: String?,
        suggestions: [String]
    ) -> String {
        let ledger = result.symbolLedgerAssessment
        return "category=\(category) case=\(label) expected=\(fixture.expectedDisplayText) primary=\(primaryText ?? "nil") suggestions=\(suggestions) raw=\(Array(result.rawCandidates.prefix(8))) trust=\(result.trustEvidence?.outcome.rawValue ?? "none") ledger=\(ledger?.agreement.rawValue ?? "none") support=\(ledger?.supportCount ?? 0)"
    }

    private func ledgerSummary(
        _ counts: [ChordInkSymbolLedgerAgreement: Int]
    ) -> String {
        ChordInkSymbolLedgerAgreement.allCases
            .map { "\($0.rawValue):\(counts[$0, default: 0])" }
            .joined(separator: ",")
    }

    private func trustEvidenceSummary(
        _ counts: [ChordInkTrustEvidenceOutcome: Int]
    ) -> String {
        ChordInkTrustEvidenceOutcome.allCases
            .map { "\($0.rawValue):\(counts[$0, default: 0])" }
            .joined(separator: ",")
    }

    private func latencySummary(_ values: [Double]) -> String {
        guard !values.isEmpty else {
            return "count:0"
        }

        let sorted = values.sorted()
        func percentile(_ value: Double) -> Double {
            let index = min(
                sorted.count - 1,
                max(0, Int((Double(sorted.count - 1) * value).rounded()))
            )
            return sorted[index]
        }
        let average = sorted.reduce(0, +) / Double(sorted.count)
        return [
            "count:\(sorted.count)",
            "avg:\(String(format: "%.3f", average))",
            "p50:\(String(format: "%.3f", percentile(0.50)))",
            "p95:\(String(format: "%.3f", percentile(0.95)))",
            "max:\(String(format: "%.3f", sorted.last ?? 0))"
        ].joined(separator: ",")
    }

    private func transformed(_ strokes: [InkStroke], by perturbation: Perturbation) -> [InkStroke] {
        guard perturbation != .identity else {
            return strokes
        }

        let bounds = InkBounds.enclosing(strokes.map(\.bounds))
        let centerX = (bounds.minX + bounds.maxX) / 2
        let centerY = (bounds.minY + bounds.maxY) / 2

        return strokes.map { stroke in
            let sourcePoints: [InkPoint]
            let shouldThin = perturbation.isLossyStress && stroke.points.count > 6
            if shouldThin {
                let retainedPoints = stroke.points.enumerated().compactMap { index, point in
                    index.isMultiple(of: 2) ? point : nil
                }
                sourcePoints = retainedPoints.last == stroke.points.last
                    ? retainedPoints
                    : retainedPoints + [stroke.points.last!]
            } else {
                sourcePoints = stroke.points
            }

            let transformedPoints = sourcePoints.map { point in
                let centeredX = point.x - centerX
                let centeredY = point.y - centerY
                let transformedPoint: (x: Double, y: Double)

                switch perturbation {
                case .identity, .densityNormalized, .thinnedPoints, .thinnedThenResampled:
                    transformedPoint = (point.x, point.y)
                case .translated:
                    transformedPoint = (point.x + 137, point.y - 83)
                case .scaledDown:
                    transformedPoint = (centerX + centeredX * 0.90, centerY + centeredY * 0.90)
                case .scaledUp:
                    transformedPoint = (centerX + centeredX * 1.10, centerY + centeredY * 1.10)
                case .rotatedCounterclockwise:
                    transformedPoint = rotated(
                        x: centeredX,
                        y: centeredY,
                        radians: -.pi / 60,
                        centerX: centerX,
                        centerY: centerY
                    )
                case .rotatedClockwise:
                    transformedPoint = rotated(
                        x: centeredX,
                        y: centeredY,
                        radians: .pi / 60,
                        centerX: centerX,
                        centerY: centerY
                    )
                }

                return InkPoint(
                    x: transformedPoint.x,
                    y: transformedPoint.y,
                    timeOffset: point.timeOffset
                )
            }

            if perturbation == .densityNormalized
                || (perturbation == .thinnedThenResampled && shouldThin) {
                return InkStroke(
                    points: resampled(transformedPoints, targetSpacing: 3.4),
                    creationTimeOffset: stroke.creationTimeOffset
                )
            }

            return InkStroke(
                points: transformedPoints,
                creationTimeOffset: stroke.creationTimeOffset
            )
        }
    }

    private func resampled(_ points: [InkPoint], targetSpacing: Double) -> [InkPoint] {
        guard let firstPoint = points.first,
              let lastPoint = points.last,
              points.count > 1 else {
            return points
        }

        let pathLength = zip(points, points.dropFirst())
            .map { start, end in hypot(end.x - start.x, end.y - start.y) }
            .reduce(0, +)
        let sampleCount = max(2, Int((pathLength / targetSpacing).rounded(.up)) + 1)
        guard pathLength > 0, sampleCount > points.count else {
            return points
        }

        let interval = pathLength / Double(sampleCount - 1)
        var sampledPoints = [firstPoint]
        var distanceSinceLastSample = 0.0
        var previousPoint = firstPoint
        var sourceIndex = points.index(after: points.startIndex)

        while sourceIndex < points.endIndex, sampledPoints.count < sampleCount {
            let currentPoint = points[sourceIndex]
            let segmentLength = hypot(
                currentPoint.x - previousPoint.x,
                currentPoint.y - previousPoint.y
            )
            guard segmentLength > 0 else {
                previousPoint = currentPoint
                sourceIndex = points.index(after: sourceIndex)
                continue
            }

            if distanceSinceLastSample + segmentLength >= interval {
                let amount = (interval - distanceSinceLastSample) / segmentLength
                let timeOffset: TimeInterval?
                if let startTime = previousPoint.timeOffset,
                   let endTime = currentPoint.timeOffset {
                    timeOffset = startTime + (endTime - startTime) * amount
                } else {
                    timeOffset = previousPoint.timeOffset ?? currentPoint.timeOffset
                }
                sampledPoints.append(InkPoint(
                    x: previousPoint.x + (currentPoint.x - previousPoint.x) * amount,
                    y: previousPoint.y + (currentPoint.y - previousPoint.y) * amount,
                    timeOffset: timeOffset
                ))
                previousPoint = sampledPoints[sampledPoints.count - 1]
                distanceSinceLastSample = 0
            } else {
                distanceSinceLastSample += segmentLength
                previousPoint = currentPoint
                sourceIndex = points.index(after: sourceIndex)
            }
        }

        if sampledPoints.last != lastPoint {
            sampledPoints.append(lastPoint)
        }
        return sampledPoints
    }

    private func rotated(
        x: Double,
        y: Double,
        radians: Double,
        centerX: Double,
        centerY: Double
    ) -> (x: Double, y: Double) {
        let cosine = cos(radians)
        let sine = sin(radians)
        return (
            centerX + x * cosine - y * sine,
            centerY + x * sine + y * cosine
        )
    }
}
