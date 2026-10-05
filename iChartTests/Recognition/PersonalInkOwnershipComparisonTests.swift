import XCTest
@testable import iChart

/// Synthetic contract checks, not handwriting accuracy or ownership calibration.
final class PersonalInkOwnershipComparisonTests: XCTestCase {
    private final class Encoder: PersonalInkVisualEncoding {
        let identity = "synthetic-ownership-contract-only"
        let vocabulary = ["A", "B"]
        var inputs: [[InkStroke]] = []
        var anchorBank: PersonalInkAnchorBank? {
            .init(vocabulary: vocabulary, features: [unit(0), unit(1)])
        }
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            inputs.append(strokes)
            return .init(embedding: unit(0), genericLogits: [3, 0])
        }
        private func unit(_ index: Int) -> [Double] {
            (0..<128).map { $0 == index ? 1 : 0 }
        }
    }

    private var ink: [InkStroke] {
        [.init(points: [.init(x: 100, y: 100, timeOffset: 0),
                        .init(x: 100, y: 120, timeOffset: 0.1),
                        .init(x: 113, y: 116, timeOffset: 0.2)], creationTimeOffset: 7)]
    }
    private var enabled: PersonalInkProfile { var value = PersonalInkProfile(); value.isEnabled = true; return value }

    func testInkOnlyAssessmentPreservesProposalOrderAndRejectsEveryInvalidPartition() throws {
        let proposal = [[2, 0], [1]]
        let assessment = try PersonalInkOwnershipAssessment.assess(sourceStrokeCount: 3, proposedGroups: proposal)
        XCTAssertEqual(assessment.proposedGroups, proposal)
        XCTAssertEqual(assessment.sourceStrokeCount, 3)
        XCTAssertTrue(assessment.hasCompleteCoverage)
        XCTAssertEqual(assessment.disposition, .unresolved)
        XCTAssertEqual(assessment.reason, .uncalibratedGeometryProposal)
        for (count, groups) in [(0, [[Int]]()), (1, []), (1, [[]]), (2, [[0]]),
                                (2, [[0, 0], [1]]), (2, [[-1, 1]]), (2, [[0, 2]]),
                                (1, [[Int.max]]), (17, (0..<17).map { [$0] })] {
            XCTAssertThrowsError(try PersonalInkOwnershipAssessment.assess(sourceStrokeCount: count, proposedGroups: groups))
        }
        let limit = ChordInkFeatureSchema.maximumStrokeCount
        XCTAssertNoThrow(try PersonalInkOwnershipAssessment.assess(sourceStrokeCount: limit, proposedGroups: [Array(0..<limit)]))
        XCTAssertThrowsError(try PersonalInkOwnershipAssessment.assess(sourceStrokeCount: limit + 1, proposedGroups: [Array(0...limit)]))
    }

    func testAssessmentCodableRevalidatesVersionDispositionReasonAndCoverage() throws {
        let original = try PersonalInkOwnershipAssessment.assess(sourceStrokeCount: 2, proposedGroups: [[1, 0]])
        let bytes = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(PersonalInkOwnershipAssessment.self, from: bytes)
        XCTAssertEqual(restored.proposedGroups, original.proposedGroups)
        XCTAssertEqual(restored.version, original.version)
        XCTAssertEqual(restored.disposition, .unresolved)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for (field, value) in [("version", "unknown-version" as Any), ("disposition", "resolved" as Any),
                               ("reason", "calibrated" as Any), ("hasCompleteCoverage", false as Any),
                               ("proposedGroups", [[0, 0]] as Any)] {
            var changed = json; changed[field] = value
            XCTAssertThrowsError(try JSONDecoder().decode(PersonalInkOwnershipAssessment.self,
                from: JSONSerialization.data(withJSONObject: changed)))
        }
    }

    func testSelectivePreservesOriginalProposalWithoutEncodingQueryOrWholeChord() throws {
        let profile = try lessons()
        let encoder = Encoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        encoder.inputs.removeAll()
        let source = ink
        let prediction = try model.predict(source, currentProfile: profile, grouping: .selectiveLosslessOwnershipV3)
        XCTAssertTrue(encoder.inputs.isEmpty, "Neither query groups nor a whole-chord query may be encoded")
        XCTAssertNil(prediction.genericChord); XCTAssertNil(prediction.personalChord); XCTAssertNil(prediction.anchored)
        XCTAssertTrue(prediction.glyphs.isEmpty); XCTAssertTrue(prediction.wholeChordRanks.isEmpty)
        let ownership = try XCTUnwrap(prediction.ownership)
        let expected = StrokeClusterer(wrapperPolicy: .preserveOriginalInk)
            .indexedClusters(source.map { InkStroke(points: $0.points) }).map { $0.originalIndexes.sorted() }
        XCTAssertEqual(ownership.proposedGroups, expected)
        XCTAssertEqual(ownership.disposition, .unresolved)
        XCTAssertTrue(ownership.hasCompleteCoverage)
        XCTAssertEqual(source, ink, "Original points, timing and drawing metadata stay unchanged")
    }

    func testAnswersWrittenCountsProfileLessonsAndRankAgreementCannotResolveOwnership() throws {
        for profile in [enabled, try lessons()] {
            var run = makeRun(profile: profile)
            var proposal: [[Int]]?
            for (answer, count) in [("A", 1), ("B7", 4), ("F#m7", 64)] {
                run.records[0].intended = answer; run.expectedChordCount = count
                run.records[0].baseline = "A"; run.records[0].personalized = "A"
                let pair = try PersonalInkOwnershipComparisonReport.compare(run, encoder: Encoder())
                let prediction = try XCTUnwrap(pair.selective.rows[0].prediction)
                let evidence = try XCTUnwrap(prediction.ownership)
                XCTAssertEqual(evidence.disposition, .unresolved)
                XCTAssertNil(prediction.genericChord); XCTAssertNil(prediction.personalChord); XCTAssertNil(prediction.anchored)
                if let proposal { XCTAssertEqual(evidence.proposedGroups, proposal) }
                proposal = evidence.proposedGroups
                XCTAssertEqual(pair.legacy.rows[0].prediction?.genericChord, "A", "Retain the controlled legacy hypothesis")
            }
        }
    }

    func testLegacyDefaultAndLosslessV2KeepTheirOriginalEncoderInputsAndNoOwnershipClaim() throws {
        let profile = enabled
        let source = ink
        let geometry = source.map { InkStroke(points: $0.points) }
        let legacyEncoder = Encoder()
        let legacy = try PersonalInkLearnedComparison(profile: profile, encoder: legacyEncoder)
        let defaultPrediction = try legacy.predict(source, currentProfile: profile)
        let explicitPrediction = try legacy.predict(source, currentProfile: profile, grouping: .legacyGeometryV1)
        XCTAssertEqual(defaultPrediction, explicitPrediction)
        XCTAssertNil(defaultPrediction.ownership)
        let expectedLegacy = StrokeClusterer(wrapperPolicy: .semanticNormalization).indexedClusters(geometry).map { $0.cluster.strokes }
        XCTAssertEqual(Array(legacyEncoder.inputs.prefix(expectedLegacy.count)), expectedLegacy)
        let losslessEncoder = Encoder()
        let lossless = try PersonalInkLearnedComparison(profile: profile, encoder: losslessEncoder, grouping: .losslessSourceV2)
        let prediction = try lossless.predict(source, currentProfile: profile)
        XCTAssertNil(prediction.ownership)
        XCTAssertEqual(losslessEncoder.inputs, prediction.glyphs.map { $0.originalStrokeIndexes.map { source[$0] } })
        XCTAssertEqual(prediction.glyphs.flatMap(\.originalStrokeIndexes).sorted(), Array(source.indices))
    }

    func testOlderCodableReportsAndPredictionsDoNotInventOwnershipEvidence() throws {
        let report = try PersonalInkLearnedRunReport.compare(makeRun(profile: enabled), encoder: Encoder(), grouping: .selectiveLosslessOwnershipV3)
        var prediction = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try XCTUnwrap(report.rows[0].prediction))) as? [String: Any])
        prediction.removeValue(forKey: "ownership")
        let oldPrediction = try JSONDecoder().decode(PersonalInkLearnedComparison.Prediction.self,
            from: JSONSerialization.data(withJSONObject: prediction))
        XCTAssertNil(oldPrediction.ownership)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        json.removeValue(forKey: "ownershipPairID")
        var scorecard = try XCTUnwrap(json["scorecard"] as? [String: Any])
        scorecard.removeValue(forKey: "ownershipUnresolvedCount"); json["scorecard"] = scorecard
        let oldReport = try JSONDecoder().decode(PersonalInkLearnedRunReport.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(oldReport.scorecard?.ownershipUnresolvedCount)
        XCTAssertNil(oldReport.ownershipPairID)
        XCTAssertEqual(oldReport.sourceRunSHA256, report.sourceRunSHA256)
    }

    func testPairFitsFrozenLessonsOnceAndRetainsLegacyHypotheses() throws {
        let profile = try lessons()
        var run = makeRun(profile: profile)
        run.profileLineage = .init(profile: profile, querySessionID: run.id)
        let encoderJSON = JSONEncoder(); encoderJSON.outputFormatting = [.sortedKeys]
        let before = try encoderJSON.encode(run)
        let encoder = Encoder()
        let pair = try PersonalInkOwnershipComparisonReport.compare(run, encoder: encoder)
        XCTAssertEqual(pair.legacy.glyphLessonCount, 2); XCTAssertEqual(pair.legacy.wholeChordLessonCount, 2)
        let legacy = try XCTUnwrap(pair.legacy.rows[0].prediction)
        XCTAssertFalse(legacy.wholeChordRanks.isEmpty)
        XCTAssertEqual(encoder.inputs.count, profile.examples.count + legacy.glyphs.count + 1,
            "Fit each glyph/chord lesson once, then only legacy query groups and its whole query")
        XCTAssertEqual(pair.selective.rows[0].prediction?.ownership?.disposition, .unresolved)
        XCTAssertEqual(pair.legacy.profileRevision, profile.revision)
        XCTAssertEqual(pair.selective.profileRevision, profile.revision)
        XCTAssertEqual(pair.legacy.profileLineage, run.profileLineage)
        XCTAssertEqual(pair.selective.profileLineage, run.profileLineage)
        let restored = try JSONDecoder().decode(PersonalInkOwnershipComparisonReport.self,
                                                from: encoderJSON.encode(pair))
        XCTAssertEqual(restored.legacy.profileLineage, run.profileLineage)
        XCTAssertEqual(restored.selective.profileLineage, run.profileLineage)
        XCTAssertEqual(try encoderJSON.encode(run), before)
    }

    func testPairRejectsDifferentOrOneMissingFrozenLineageAtConstructionAndDecode() throws {
        var run = makeRun(profile: try lessons())
        run.profileLineage = .init(profile: run.profile, querySessionID: run.id)
        let pair = try PersonalInkOwnershipComparisonReport.compare(run, encoder: Encoder())
        let pairJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pair)) as? [String: Any])
        let original = try reportJSON(pair.selective)
        let summary = try XCTUnwrap(original["profileLineage"] as? [String: Any])
        for key in ["missing", "querySessionID", "untrackedExampleIDs", "isMetadataComplete"] {
            var child = original
            if key == "missing" { child.removeValue(forKey: "profileLineage") }
            else {
                var changed = summary
                switch key {
                case "querySessionID": changed[key] = UUID().uuidString
                case "untrackedExampleIDs": changed[key] = [] as [String]
                default: changed[key] = true
                }
                child["profileLineage"] = changed
            }
            let selective = try decodeReport(child)
            XCTAssertThrowsError(try PersonalInkOwnershipComparisonReport(legacy: pair.legacy, selective: selective), key)
            var changedPair = pairJSON; changedPair["selective"] = child
            XCTAssertThrowsError(try JSONDecoder().decode(PersonalInkOwnershipComparisonReport.self,
                from: JSONSerialization.data(withJSONObject: changedPair)), key)
        }
    }

    func testOlderPairWithBothLineagesAbsentDecodesWithoutInventingMetadata() throws {
        var run = makeRun(profile: enabled)
        run.profileLineage = .init(profile: run.profile, querySessionID: run.id)
        let pair = try PersonalInkOwnershipComparisonReport.compare(run, encoder: Encoder())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pair)) as? [String: Any])
        for arm in ["legacy", "selective"] {
            var child = try XCTUnwrap(json[arm] as? [String: Any])
            child.removeValue(forKey: "profileLineage"); json[arm] = child
        }
        let restored = try JSONDecoder().decode(PersonalInkOwnershipComparisonReport.self,
            from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.legacy.profileLineage)
        XCTAssertNil(restored.selective.profileLineage)
        XCTAssertEqual(restored.legacy.scorecard, pair.legacy.scorecard)
        XCTAssertEqual(restored.selective.scorecard, pair.selective.scorecard)
        XCTAssertEqual(restored.legacy.rows.map(\.prediction), pair.legacy.rows.map(\.prediction))
        XCTAssertEqual(restored.selective.rows.map(\.prediction), pair.selective.rows.map(\.prediction))
        XCTAssertEqual(restored.id, pair.id)
    }

    func testCommonEligibilityCountsUnresolvedSeparatelyFromUnsupportedAndKeepsMissingAttempts() throws {
        var run = makeRun(profile: enabled)
        var unsupported = run.records[0]; unsupported.id = UUID(); unsupported.recognitionStrokes = []
        run.records.append(unsupported); run.expectedChordCount = 3
        let pair = try PersonalInkOwnershipComparisonReport.compare(run, encoder: Encoder())
        let legacy = try XCTUnwrap(pair.legacy.scorecard), selective = try XCTUnwrap(pair.selective.scorecard)
        XCTAssertEqual(legacy.eligibleCount, 2); XCTAssertEqual(selective.eligibleCount, 2)
        XCTAssertEqual(legacy.wholeChartDenominator, 3); XCTAssertEqual(selective.wholeChartDenominator, 3)
        XCTAssertEqual(selective.missingCount, 1)
        XCTAssertEqual(legacy.unsupportedInputCount, 1); XCTAssertEqual(selective.unsupportedInputCount, 1)
        XCTAssertNil(legacy.ownershipUnresolvedCount); XCTAssertEqual(selective.ownershipUnresolvedCount, 1)
        for score in selective.scores where [.sharedML, .personalML, .anchoredML].contains(score.method) {
            XCTAssertEqual(score.correct, 0); XCTAssertEqual(score.wrongReads, 0); XCTAssertEqual(score.noReads, 2)
        }
        var grouped = run.records[0]; grouped.id = UUID(); grouped.groupingIssue = true
        var known = run.records[0]; known.id = UUID(); known.knownInk = true
        run.records.append(contentsOf: [grouped, known]); run.expectedChordCount = 4
        let excluded = try PersonalInkOwnershipComparisonReport.compare(run, encoder: Encoder())
        XCTAssertEqual(excluded.legacy.scorecard?.eligibleCount, excluded.selective.scorecard?.eligibleCount)
        XCTAssertEqual(excluded.selective.scorecard?.eligibleCount, 2)
        XCTAssertNil(excluded.selective.scorecard?.wholeChartDenominator)
        XCTAssertEqual(excluded.selective.scorecard?.groupingIssueCount, 1)
        XCTAssertEqual(excluded.selective.scorecard?.knownInkCount, 1)
        let groupedLegacy = try XCTUnwrap(excluded.legacy.rows.first { $0.id == grouped.id })
        let groupedSelective = try XCTUnwrap(excluded.selective.rows.first { $0.id == grouped.id })
        XCTAssertNil(groupedLegacy.prediction)
        XCTAssertNotNil(groupedSelective.prediction?.ownership)
        XCTAssertEqual(groupedSelective.prediction?.ownership?.disposition, .unresolved)
        XCTAssertEqual(groupedSelective.exclusion, groupedLegacy.exclusion)
        XCTAssertNotNil(groupedSelective.exclusion)
        XCTAssertEqual(excluded.selective.scorecard?.ownershipUnresolvedCount, 1,
            "Excluded capture proposals stay reviewable without entering the eligible unresolved count")

        var knownInvalidRun = makeRun(profile: enabled)
        knownInvalidRun.records[0].knownInk = true
        knownInvalidRun.records[0].recognitionStrokes = []
        let standalone = try PersonalInkLearnedRunReport.compare(knownInvalidRun, encoder: Encoder())
        XCTAssertEqual(standalone.scorecard?.eligibleCount, 0)
        XCTAssertEqual(standalone.scorecard?.knownInkCount, 1)
        XCTAssertEqual(standalone.rows[0].exclusion,
            "Input or segmentation unsupported; counted as a failed complete read when this is a labeled fresh chord.",
            "The historical standalone classification remains unchanged")
        let knownInvalid = try PersonalInkOwnershipComparisonReport.compare(knownInvalidRun, encoder: Encoder())
        for arm in [knownInvalid.legacy, knownInvalid.selective] {
            XCTAssertEqual(arm.rows[0].exclusion, "Matches previously learned ink; not a fresh sample.")
            XCTAssertEqual(arm.scorecard?.eligibleCount, 0)
            XCTAssertEqual(arm.scorecard?.knownInkCount, 1)
            XCTAssertEqual(arm.scorecard?.unsupportedInputCount, 0)
        }
        XCTAssertEqual(knownInvalid.selective.scorecard?.ownershipUnresolvedCount, 0)
        knownInvalidRun.records[0].groupingIssue = true
        let groupingFirst = try PersonalInkOwnershipComparisonReport.compare(knownInvalidRun, encoder: Encoder())
        for arm in [groupingFirst.legacy, groupingFirst.selective] {
            XCTAssertEqual(arm.rows[0].exclusion, "Incorrect grouping; not scored as one chord.")
            XCTAssertEqual(arm.scorecard?.eligibleCount, 0)
            XCTAssertEqual(arm.scorecard?.groupingIssueCount, 1)
        }
    }

    func testPairRejectsMismatchedSourceModelProfileLessonsRowsAndEligibility() throws {
        let pair = try PersonalInkOwnershipComparisonReport.compare(makeRun(profile: enabled), encoder: Encoder())
        let replacements: [(String, Any)] = [
            ("runID", UUID().uuidString), ("sourceRunSHA256", String(repeating: "0", count: 64)),
            ("evaluationSourceSHA256", String(repeating: "0", count: 64)), ("encoderIdentity", "another-encoder"),
            ("profileRevision", UUID().uuidString), ("profileGeneration", UUID().uuidString),
            ("ownershipPairID", UUID().uuidString),
            ("glyphLessonCount", 1), ("wholeChordLessonCount", 1),
            ("groupingVersion", PersonalInkLearnedComparison.Grouping.legacyGeometryV1.rawValue)
        ]
        for (key, value) in replacements {
            let changed = try replacing(pair.selective, key: key, value: value)
            XCTAssertThrowsError(try PersonalInkOwnershipComparisonReport(legacy: pair.legacy, selective: changed), key)
        }
        var json = try reportJSON(pair.selective)
        var rows = try XCTUnwrap(json["rows"] as? [[String: Any]])
        rows[0]["id"] = UUID().uuidString; json["rows"] = rows
        XCTAssertThrowsError(try PersonalInkOwnershipComparisonReport(legacy: pair.legacy, selective: decodeReport(json)))
        let pairJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pair)) as? [String: Any])
        for key in ["id", "version"] {
            var changed = pairJSON; changed[key] = key == "id" ? UUID().uuidString : "unknown-pair-version"
            XCTAssertThrowsError(try JSONDecoder().decode(PersonalInkOwnershipComparisonReport.self,
                from: JSONSerialization.data(withJSONObject: changed)), key)
        }
        var changed = pairJSON
        var child = try XCTUnwrap(changed["selective"] as? [String: Any])
        child["ownershipPairID"] = UUID().uuidString; changed["selective"] = child
        XCTAssertThrowsError(try JSONDecoder().decode(PersonalInkOwnershipComparisonReport.self,
            from: JSONSerialization.data(withJSONObject: changed)))
        json = try reportJSON(pair.selective)
        var card = try XCTUnwrap(json["scorecard"] as? [String: Any]); card["eligibleCount"] = 9; json["scorecard"] = card
        XCTAssertThrowsError(try PersonalInkOwnershipComparisonReport(legacy: pair.legacy, selective: decodeReport(json)))
    }

    func testPairSavesOneRoundTrippableAppendOnlyFileAndFailureCannotSaveHalfPair() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pair = try PersonalInkOwnershipComparisonReport.compare(makeRun(profile: enabled), encoder: Encoder())
        try pair.save(in: folder)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let file = try XCTUnwrap(files.first), before = try Data(contentsOf: file)
        let saved = try JSONDecoder().decode(PersonalInkOwnershipComparisonReport.self, from: before)
        XCTAssertEqual(saved.id, pair.id); XCTAssertEqual(saved.runID, pair.runID)
        XCTAssertEqual(saved.legacy.sourceRunSHA256, saved.selective.sourceRunSHA256)
        XCTAssertEqual(saved.selective.rows[0].prediction?.ownership?.disposition, .unresolved)
        XCTAssertThrowsError(try pair.save(in: folder))
        XCTAssertEqual(try Data(contentsOf: file), before)
        let obstruction = folder.appendingPathComponent("not-a-directory")
        try Data("keep".utf8).write(to: obstruction)
        XCTAssertThrowsError(try pair.save(in: obstruction))
        XCTAssertEqual(try Data(contentsOf: obstruction), Data("keep".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
    }

    func testPairRejectsEqualTotalOutcomeSwapAndMatchingCapturedCountTampering() throws {
        let pair = try PersonalInkOwnershipComparisonReport.compare(makeRun(profile: enabled), encoder: Encoder())
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pair)) as? [String: Any])
        var selective = try reportJSON(pair.selective)
        var card = try XCTUnwrap(selective["scorecard"] as? [String: Any])
        card["ownershipUnresolvedCount"] = 0; card["unsupportedInputCount"] = 1
        selective["scorecard"] = card
        XCTAssertThrowsError(try PersonalInkOwnershipComparisonReport(legacy: pair.legacy, selective: decodeReport(selective)),
            "An equal aggregate total cannot relabel an actual unresolved proposal as unsupported")
        var changed = original; changed["selective"] = selective
        XCTAssertThrowsError(try JSONDecoder().decode(PersonalInkOwnershipComparisonReport.self,
            from: JSONSerialization.data(withJSONObject: changed)))

        var legacy = try reportJSON(pair.legacy); selective = try reportJSON(pair.selective)
        var oldCard = try XCTUnwrap(legacy["scorecard"] as? [String: Any])
        card = try XCTUnwrap(selective["scorecard"] as? [String: Any])
        oldCard["capturedCount"] = 2; card["capturedCount"] = 2
        legacy["scorecard"] = oldCard; selective["scorecard"] = card
        XCTAssertThrowsError(try PersonalInkOwnershipComparisonReport(legacy: decodeReport(legacy), selective: decodeReport(selective)),
            "Matching metadata must still equal the actual saved row count")
        changed = original; changed["legacy"] = legacy; changed["selective"] = selective
        XCTAssertThrowsError(try JSONDecoder().decode(PersonalInkOwnershipComparisonReport.self,
            from: JSONSerialization.data(withJSONObject: changed)))
    }

    private func lessons() throws -> PersonalInkProfile {
        var profile = enabled
        let vertical = [InkStroke(points: [.init(x: 0, y: 0), .init(x: 0, y: 20)])]
        let horizontal = [InkStroke(points: [.init(x: 0, y: 0), .init(x: 20, y: 0)])]
        try profile.learn(strokes: vertical, label: "A", kind: .glyph, source: .setup)
        try profile.learn(strokes: horizontal, label: "B", kind: .glyph, source: .setup)
        try profile.learn(strokes: vertical, label: "C", kind: .chord, source: .setup)
        try profile.learn(strokes: horizontal, label: "D", kind: .chord, source: .setup)
        return profile
    }

    private func makeRun(profile: PersonalInkProfile) -> PersonalInkEvaluationRun {
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
            pipeline: "synthetic-ownership-contract", profile: profile)
        run.status = .complete; run.expectedChordCount = 1
        run.records = [.init(measureIndex: 1, fraction: 0, strokes: ink, fingerprint: "synthetic",
            baseline: "A", personalized: "A", baselineAction: "confirm", personalizedAction: "confirm", knownInk: false,
            recognitionMilliseconds: 1, totalMilliseconds: 1, cacheHit: false, intended: "A", recognitionStrokes: ink)]
        return run
    }

    private func reportJSON(_ report: PersonalInkLearnedRunReport) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
    }
    private func decodeReport(_ json: [String: Any]) throws -> PersonalInkLearnedRunReport {
        try JSONDecoder().decode(PersonalInkLearnedRunReport.self, from: JSONSerialization.data(withJSONObject: json))
    }
    private func replacing(_ report: PersonalInkLearnedRunReport, key: String, value: Any) throws -> PersonalInkLearnedRunReport {
        var json = try reportJSON(report); json[key] = value; return try decodeReport(json)
    }
}
