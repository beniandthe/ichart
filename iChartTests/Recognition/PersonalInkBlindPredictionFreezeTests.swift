import Foundation
import CryptoKit
import XCTest
@testable import iChart

/// Synthetic contract checks. They establish source replay, commitment and
/// blind-query boundaries, not ownership correctness or handwriting accuracy.
final class PersonalInkBlindPredictionFreezeTests: XCTestCase {
    private final class SpyEncoder: PersonalInkVisualEncoding {
        let identity = "synthetic/blind-freeze/ø"
        let vocabulary = ["A", "B", "/"]
        var inputs: [[InkStroke]] = []
        var onEncode: (() -> Void)?
        var failureAt: Int?
        var failure: Error = EncoderFailure.technical
        var invalidFeatures = false

        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            inputs.append(strokes)
            onEncode?()
            if inputs.count == failureAt { throw failure }
            return .init(
                embedding: (0..<128).map { $0 == 0 ? 1 : 0 },
                genericLogits: invalidFeatures ? [0] : [-3, -3, 3]
            )
        }
    }

    private enum EncoderFailure: Error, Equatable { case technical }
    private let runtimeDigest = String(repeating: "a", count: 64)
    private let codeDigest = String(repeating: "b", count: 64)
    private let ownershipDigest = String(repeating: "c", count: 64)

    private var enabledProfile: PersonalInkProfile {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        return profile
    }

    func testBothArmsReplayExactPacketMetadataAndPreserveDeclaredSuppliedOrder() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        var source = makeSource(count: 4)
        let negativeZero = Double(bitPattern: 0x8000_0000_0000_0000)
        let payloadNaN = Double(bitPattern: 0x7ff8_0000_0000_0042)
        source[0].points[0].x = negativeZero
        source[0].points[0].timeOffset = payloadNaN
        source[0].creationTimeOffset = -.infinity
        source[1].points[1].timeOffset = nil
        let data = try packetData(source)
        let originalData = data
        let groups = [[3, 1], [2, 0]]

        let frozen = try freeze(data, model: model, profile: profile, groups: groups)

        XCTAssertEqual(frozen.automatic.outcome, .read)
        XCTAssertEqual(frozen.supplied?.outcome, .read)
        XCTAssertEqual(frozen.supplied?.glyphs.map(\.originalStrokeIndexes), [[1, 3], [0, 2]])
        let automaticGroups = frozen.automatic.glyphs.map(\.originalStrokeIndexes)
        let expected = automaticGroups.map { indexes in indexes.map { source[$0] } }
            + [[source[1], source[3]], [source[0], source[2]]]
        XCTAssertEqual(encoder.inputs.count, expected.count)
        for (actual, intended) in zip(encoder.inputs, expected) {
            XCTAssertEqual(try packetData(actual), try packetData(intended))
        }
        XCTAssertEqual(encoder.inputs[0][0].points[0].x.bitPattern, negativeZero.bitPattern)
        XCTAssertEqual(encoder.inputs[0][0].points[0].timeOffset?.bitPattern, payloadNaN.bitPattern)
        XCTAssertEqual(try packetData(source), originalData)
        XCTAssertEqual(data, originalData)
        XCTAssertEqual(model.profile, profile)
    }

    func testAutomaticGroupsAndTopChoicesMatchSameModelLosslessPolicy() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        var source = makeSource(count: 4)
        // Bring two source strokes together and provide timing rich metadata.
        source[1] = InkStroke(points: [
            .init(x: 8, y: 9, timeOffset: 80),
            .init(x: 10, y: 21, timeOffset: 80.1)
        ], creationTimeOffset: -30)
        let prediction = try model.predict(source, currentProfile: profile, grouping: .losslessSourceV2)
        encoder.inputs.removeAll()

        let frozen = try freeze(packetData(source), model: model, profile: profile)

        XCTAssertEqual(frozen.automatic.outcome, .read)
        XCTAssertEqual(frozen.automatic.glyphs.map(\.originalStrokeIndexes),
            prediction.glyphs.map(\.originalStrokeIndexes))
        XCTAssertEqual(frozen.automatic.glyphs.map(\.sharedTop1),
            prediction.glyphs.map { $0.generic.first?.label })
        XCTAssertEqual(frozen.automatic.glyphs.map(\.personalTop1),
            prediction.glyphs.map { $0.personal.first?.label })
        XCTAssertEqual(encoder.inputs.count, prediction.glyphs.count)
        XCTAssertNil(frozen.supplied)
    }

    func testProfileAndSourceDigestsCommitExactCanonicalValues() throws {
        let profile = try profileWithWholeChordLessons()
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        encoder.inputs.removeAll()
        let source = makeSource(count: 3)
        let data = try packetData(source)
        let profileEncoder = JSONEncoder()
        profileEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let frozen = try freeze(data, model: model, profile: profile)

        XCTAssertEqual(frozen.version, "blind-ink-prediction-freeze-v1")
        XCTAssertEqual(frozen.artifactKind, "engineering-only-blind-evaluation-v1")
        XCTAssertEqual(frozen.sourcePacketSHA256, sha256(data))
        XCTAssertEqual(frozen.profileSHA256, sha256(try profileEncoder.encode(model.profile)))
        XCTAssertEqual(frozen.encoderIdentity, model.encoderIdentity)
        XCTAssertEqual(frozen.ownershipReceiptSHA256, ownershipDigest)
        XCTAssertEqual(frozen.runtimeSHA256, runtimeDigest)
        XCTAssertEqual(frozen.codeSHA256, codeDigest)
        XCTAssertEqual(frozen.sourceStrokeCount, source.count)
        // A revision-only digest would miss a change to this ordinary setting.
        var different = profile
        different.learnsFromReviews.toggle()
        XCTAssertEqual(different.revision, profile.revision)
        XCTAssertNotEqual(frozen.profileSHA256, sha256(try profileEncoder.encode(different)))
        var differentInk = source
        differentInk[0].bounds.minX -= 0.125
        let altered = try freeze(packetData(differentInk), model: model, profile: profile)
        XCTAssertNotEqual(altered.sourcePacketSHA256, frozen.sourcePacketSHA256)
    }

    func testNoWholeSourceQueryOrCompositionEvenWhenWholeChordHeadExists() throws {
        let profile = try profileWithWholeChordLessons()
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        XCTAssertEqual(model.wholeChordLessonCount, 2)
        encoder.inputs.removeAll()
        let source = makeSource(count: 4)

        let frozen = try freeze(packetData(source), model: model, profile: profile,
            groups: [[3, 1], [2, 0]])

        let automaticGroups = frozen.automatic.glyphs.map(\.originalStrokeIndexes)
        XCTAssertGreaterThan(automaticGroups.count, 1)
        XCTAssertEqual(encoder.inputs.count, automaticGroups.count + 2)
        XCTAssertTrue(encoder.inputs.allSatisfy { $0.count < source.count })
        XCTAssertTrue(frozen.automatic.glyphs.allSatisfy { $0.sharedTop1 == "/" })
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: frozen.canonicalData()) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set([
            "version", "artifactKind", "sourcePacketSHA256", "ownershipReceiptSHA256",
            "sourceStrokeCount", "encoderIdentity", "profileSHA256", "runtimeSHA256",
            "codeSHA256", "automatic", "supplied"
        ]))
        XCTAssertNil(object["genericChord"])
        XCTAssertNil(object["personalChord"])
        XCTAssertNil(object["wholeChordRanks"])
    }

    func testInvalidSuppliedPartitionsFailBeforeEitherArmQueriesEncoder() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let data = try packetData(makeSource(count: 3))
        let invalidPartitions = [
            [], [[0], [], [1, 2]], [[0, 1]], [[0, 0], [1]],
            [[0, 1, -1]], [[0, 1, 3]], [[0], [1], [2], [2]]
        ]
        for groups in invalidPartitions {
            XCTAssertThrowsError(try freeze(data, model: model, profile: profile, groups: groups)) { error in
                XCTAssertEqual(error as? PersonalInkBlindPredictionFreeze.Failure, .invalidSuppliedPartition)
            }
            XCTAssertTrue(encoder.inputs.isEmpty)
        }
    }

    func testMalformedDigestCommitmentsFailBeforeEncoding() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let data = try packetData(makeSource(count: 1))
        let cases = [
            (String(repeating: "A", count: 64), codeDigest, ownershipDigest, "runtimeSHA256"),
            (runtimeDigest, String(repeating: "b", count: 63), ownershipDigest, "codeSHA256"),
            (runtimeDigest, codeDigest, String(repeating: "z", count: 64), "ownershipReceiptSHA256")
        ]
        for (runtime, code, ownership, field) in cases {
            XCTAssertThrowsError(try PersonalInkBlindPredictionFreeze.freeze(sourcePacketData: data,
                ownershipReceiptSHA256: ownership, runtimeSHA256: runtime,
                codeSHA256: code, model: model, currentProfile: { profile })) { error in
                XCTAssertEqual(error as? PersonalInkBlindPredictionFreeze.Failure,
                    .invalidCommitment(field: field))
            }
        }
        XCTAssertTrue(encoder.inputs.isEmpty)
    }

    func testPacketBudgetsAndCanonicalValidationFailBeforeEncoding() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let point = InkPoint(x: 4, y: 5)
        let cases: [Data] = [
            Data(repeating: 0x20, count: PersonalInkBlindPredictionFreeze.maximumPacketBytes + 1),
            try packetData((0..<257).map { _ in InkStroke(points: [point]) }),
            try packetData([InkStroke(points: Array(repeating: point, count: 8_193))]),
            try packetData((0..<4).map { _ in InkStroke(points: Array(repeating: point, count: 8_192)) }
                + [InkStroke(points: [point])])
        ]
        for data in cases {
            XCTAssertThrowsError(try freeze(data, model: model, profile: profile)) { error in
                XCTAssertEqual(error as? PersonalInkBlindPredictionFreeze.Failure, .packetBudgetExceeded)
            }
        }
        let canonical = try packetData(makeSource(count: 1))
        for malformed in [Data(" ".utf8) + canonical, Data("{}".utf8)] {
            XCTAssertThrowsError(try freeze(malformed, model: model, profile: profile)) { error in
                XCTAssertEqual(error as? PersonalInkBlindPredictionFreeze.Failure, .invalidPacket)
            }
        }
        XCTAssertTrue(encoder.inputs.isEmpty)
    }

    func testBudgetBoundaryPacketsRemainAttemptsWhenModelCannotRepresentThem() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let point = InkPoint(x: 4, y: 5)
        let totalLimit = (0..<4).map { _ in
            InkStroke(points: Array(repeating: point, count: 8_192))
        }
        let strokeLimit = (0..<256).map { index in
            InkStroke(points: [InkPoint(x: Double(index) * 200, y: 7)])
        }
        let frozen = try freeze(packetData(totalLimit), model: model, profile: profile,
            groups: [Array(totalLimit.indices)])
        XCTAssertEqual(frozen.automatic, .invalidInk)
        XCTAssertEqual(frozen.supplied, .invalidInk)
        XCTAssertEqual(frozen.sourceStrokeCount, 4)
        let strokeBoundary = try freeze(packetData(strokeLimit), model: model, profile: profile)
        XCTAssertEqual(strokeBoundary.sourceStrokeCount, 256)
        XCTAssertEqual(strokeBoundary.automatic, .invalidInk)
        XCTAssertTrue(encoder.inputs.isEmpty)

        let singleStrokeBoundary = [InkStroke(points: Array(repeating: point, count: 8_192))]
        let readable = try freeze(packetData(singleStrokeBoundary), model: model,
            profile: profile, groups: [[0]])
        XCTAssertEqual(readable.automatic.outcome, .read)
        XCTAssertEqual(readable.supplied?.outcome, .read)
        XCTAssertEqual(encoder.inputs.count, 2)
    }

    func testEmptyAndInvalidBoundsKeepCompleteInvalidInkArms() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let empty = try freeze(packetData([]), model: model, profile: profile, groups: [])
        XCTAssertEqual(empty.sourceStrokeCount, 0)
        XCTAssertEqual(empty.automatic, .invalidInk)
        XCTAssertEqual(empty.supplied, .invalidInk)
        var badBounds = makeSource(count: 2)
        badBounds[1].bounds.minX = badBounds[1].bounds.maxX + 1
        let invalid = try freeze(packetData(badBounds), model: model, profile: profile, groups: [[0], [1]])
        XCTAssertEqual(invalid.automatic, .invalidInk)
        XCTAssertEqual(invalid.supplied, .invalidInk)
        let emptyStroke = try freeze(packetData([InkStroke(points: [])]), model: model,
            profile: profile, groups: [[0]])
        XCTAssertEqual(emptyStroke.automatic, .invalidInk)
        XCTAssertEqual(emptyStroke.supplied, .invalidInk)
        let extreme = [InkStroke(points: [
            .init(x: -Double.greatestFiniteMagnitude, y: 0),
            .init(x: Double.greatestFiniteMagnitude, y: 1)
        ])]
        let unrepresentable = try freeze(packetData(extreme), model: model, profile: profile)
        XCTAssertEqual(unrepresentable.automatic, .invalidInk)
        XCTAssertTrue(encoder.inputs.isEmpty)
    }

    func testArmsRemainIndependentWhenAutomaticOrSuppliedHasTooManyGroups() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let source = makeSource(count: 17)
        let suppliedReadable = try freeze(packetData(source), model: model, profile: profile,
            groups: [Array(source.indices.reversed())])
        XCTAssertEqual(suppliedReadable.automatic, .invalidInk)
        XCTAssertEqual(suppliedReadable.supplied?.outcome, .read)
        XCTAssertEqual(suppliedReadable.supplied?.glyphs.first?.originalStrokeIndexes, Array(source.indices))
        XCTAssertEqual(encoder.inputs.count, 1)
        encoder.inputs.removeAll()
        let tooMany = try freeze(packetData(source), model: model, profile: profile,
            groups: source.indices.map { [$0] })
        XCTAssertEqual(tooMany.automatic, .invalidInk)
        XCTAssertEqual(tooMany.supplied, .invalidInk)
        XCTAssertTrue(encoder.inputs.isEmpty)
        // The opposite direction: two strokes overlap, so automatic grouping
        // fits within 16 groups while the independently supplied 17 do not.
        var overlapping = source
        overlapping[16] = overlapping[0]
        let automaticReadable = try freeze(packetData(overlapping), model: model,
            profile: profile, groups: overlapping.indices.map { [$0] })
        XCTAssertEqual(automaticReadable.automatic.outcome, .read)
        XCTAssertEqual(automaticReadable.supplied, .invalidInk)
        XCTAssertEqual(encoder.inputs.count, automaticReadable.automatic.glyphs.count)
    }

    func testDisabledStaleAndMidInferenceProfileChangesThrow() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let data = try packetData(makeSource(count: 2))
        var disabled = profile
        disabled.isEnabled = false
        assertModelFailure(.disabled) { try freeze(data, model: model, profile: disabled) }
        var stale = profile
        stale.learnsFromReviews.toggle()
        assertModelFailure(.staleProfile) { try freeze(data, model: model, profile: stale) }
        XCTAssertTrue(encoder.inputs.isEmpty)

        var liveProfile = profile
        encoder.onEncode = { liveProfile.learnsFromReviews = !profile.learnsFromReviews }
        assertModelFailure(.staleProfile) {
            try PersonalInkBlindPredictionFreeze.freeze(sourcePacketData: data,
                suppliedOriginalIndexGroups: [[0], [1]], ownershipReceiptSHA256: ownershipDigest,
                runtimeSHA256: runtimeDigest, codeSHA256: codeDigest, model: model,
                currentProfile: { liveProfile })
        }
        XCTAssertEqual(encoder.inputs.count, 2, "Supplied arm cannot run after an automatic-arm profile mutation")
        XCTAssertEqual(model.profile, profile)
        encoder.inputs.removeAll()
        liveProfile = profile
        encoder.onEncode = { liveProfile.isEnabled = false }
        assertModelFailure(.disabled) {
            try PersonalInkBlindPredictionFreeze.freeze(sourcePacketData: data,
                ownershipReceiptSHA256: ownershipDigest, runtimeSHA256: runtimeDigest,
                codeSHA256: codeDigest, model: model, currentProfile: { liveProfile })
        }
    }

    func testTechnicalEncoderFailuresThrowAndTypedNoReadRetainsNoPartialGlyphs() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let data = try packetData(makeSource(count: 3))
        encoder.failureAt = 2
        XCTAssertThrowsError(try freeze(data, model: model, profile: profile)) { error in
            XCTAssertEqual(error as? EncoderFailure, .technical)
        }
        encoder.inputs.removeAll()
        encoder.failure = ChordInkFeatureEncodingError.noRead(.representationCannotFit(requiredMinimumSamples: 257, capacity: 256))
        let noRead = try freeze(data, model: model, profile: profile)
        XCTAssertEqual(noRead.automatic, .invalidInk)
        XCTAssertTrue(noRead.automatic.glyphs.isEmpty)
        XCTAssertEqual(encoder.inputs.count, 2)
        encoder.inputs.removeAll()
        encoder.failureAt = nil
        encoder.invalidFeatures = true
        assertModelFailure(.invalidEncoder) { try freeze(data, model: model, profile: profile) }
    }

    func testCanonicalOutputIsDeterministicHasExplicitNullsAndLiteralUnicodeSlashes() throws {
        let profile = enabledProfile
        let encoder = SpyEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let data = try packetData(makeSource(count: 1))
        let frozen = try PersonalInkBlindPredictionFreeze.freeze(sourcePacketData: data,
            ownershipReceiptSHA256: nil, runtimeSHA256: runtimeDigest,
            codeSHA256: codeDigest, model: model, currentProfile: { profile })
        let first = try frozen.canonicalData()
        XCTAssertEqual(first, try frozen.canonicalData())
        XCTAssertEqual(first, try PersonalInkBlindPredictionFreeze.freeze(sourcePacketData: data,
            ownershipReceiptSHA256: nil, runtimeSHA256: runtimeDigest,
            codeSHA256: codeDigest, model: model, currentProfile: { profile }).canonicalData())
        let text = try XCTUnwrap(String(data: first, encoding: .utf8))
        XCTAssertTrue(text.contains("\"ownershipReceiptSHA256\":null"))
        XCTAssertTrue(text.contains("\"supplied\":null"))
        XCTAssertTrue(text.contains("synthetic/blind-freeze/ø"))
        XCTAssertFalse(text.contains("\\/"))
        let sortedObject = try JSONSerialization.data(withJSONObject:
            JSONSerialization.jsonObject(with: first), options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertEqual(first, sortedObject)

        let nullGlyph = PersonalInkBlindPredictionFreeze.Glyph(originalStrokeIndexes: [0],
            sharedTop1: nil, personalTop1: nil)
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        XCTAssertEqual(try jsonEncoder.encode(nullGlyph),
            Data(#"{"originalStrokeIndexes":[0],"personalTop1":null,"sharedTop1":null}"#.utf8))
    }

    #if DEBUG && canImport(CoreML)
    /// Opt-in integration/export gate for a caller-provided small synthetic
    /// source packet. It loads the same pinned research runtime, never a corpus,
    /// identity annotation, expected answer, or another inference engine.
    func testProvidedSyntheticPacketExportsActualCoreMLBlindFreeze() throws {
        let env = ProcessInfo.processInfo.environment
        guard let runtimePath = env["ICHART_PERSONAL_ML_RUNTIME_DIRECTORY"],
              let sourcePath = env["ICHART_BLIND_EVALUATION_SOURCE_PACKET"],
              let groupsJSON = env["ICHART_BLIND_EVALUATION_GROUPS"],
              let ownershipSHA = env["ICHART_BLIND_EVALUATION_OWNERSHIP_SHA256"],
              let runtimeSHA = env["ICHART_BLIND_EVALUATION_RUNTIME_SHA256"],
              let codeSHA = env["ICHART_BLIND_EVALUATION_CODE_SHA256"],
              let reportPath = env["ICHART_BLIND_EVALUATION_REPORT"] else {
            throw XCTSkip("Provide the pinned runtime, small synthetic source packet, independent groups, verified commitments and new report path")
        }
        guard [runtimePath, sourcePath, groupsJSON, ownershipSHA, runtimeSHA, codeSHA, reportPath]
            .allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            XCTFail("Blind evaluation environment values must be nonempty")
            return
        }
        let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL.resolvingSymlinksInPath()
        let runtimeURL = URL(fileURLWithPath: runtimePath).standardizedFileURL.resolvingSymlinksInPath()
        let reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL.resolvingSymlinksInPath()
        guard reportURL != sourceURL, reportURL != runtimeURL,
              !reportURL.path.hasPrefix(runtimeURL.path + "/"),
              !FileManager.default.fileExists(atPath: reportURL.path) else {
            XCTFail("The report must be a new file outside the source and runtime package")
            return
        }
        guard let sourceBytes = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              sourceBytes <= PersonalInkBlindPredictionFreeze.maximumPacketBytes else {
            XCTFail("Synthetic source packet exceeds the byte budget")
            return
        }
        // Read source bytes before the encoder is constructed or queried.
        let sourceData = try Data(contentsOf: sourceURL)
        let packet = try PersonalInkBlindPredictionFreeze.decodeBoundedPacket(sourceData)
        let source = packet.preparedStrokes()
        let groups = try JSONDecoder().decode([[Int]].self, from: Data(groupsJSON.utf8))
        guard (2...3).contains(groups.count), (2...12).contains(source.count),
              source.reduce(0, { $0 + $1.points.count }) <= 128 else {
            XCTFail("This runtime bridge gate accepts only a small synthetic packet with two or three supplied groups")
            return
        }
        let manifestURL = runtimeURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let profile = enabledProfile
        let profileEncoder = JSONEncoder()
        profileEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let runtimeFiles = try runtimeFileDigests(runtimeURL)
        guard runtimeSHA == sha256(try profileEncoder.encode(runtimeFiles)) else {
            XCTFail("Runtime commitment must match all runtime relative paths and exact file digests")
            return
        }
        XCTAssertTrue([PersonalInkVisualEncoder.manifestSHA256,
            PersonalInkVisualEncoder.anchoredManifestSHA256].contains(sha256(manifestData)))
        let profileData = try profileEncoder.encode(profile)
        defer {
            XCTAssertEqual(try? Data(contentsOf: sourceURL), sourceData,
                "Synthetic source packet bytes must stay unchanged")
            XCTAssertEqual(try? Data(contentsOf: manifestURL), manifestData,
                "Runtime manifest bytes must stay unchanged")
            XCTAssertEqual(try? runtimeFileDigests(runtimeURL), runtimeFiles,
                "Every runtime file and its relative path must stay unchanged")
            XCTAssertEqual(try? profileEncoder.encode(profile), profileData,
                "Frozen profile bytes must stay unchanged")
        }
        let encoder = try PersonalInkVisualEncoder(directory: runtimeURL)
        XCTAssertEqual(encoder.vocabulary.count, 97)
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        XCTAssertTrue(model.profile.examples.isEmpty)
        let frozen = try PersonalInkBlindPredictionFreeze.freeze(sourcePacketData: sourceData,
            suppliedOriginalIndexGroups: groups, ownershipReceiptSHA256: ownershipSHA,
            runtimeSHA256: runtimeSHA, codeSHA256: codeSHA, model: model,
            currentProfile: { profile })
        let supplied = try XCTUnwrap(frozen.supplied)
        guard frozen.automatic.outcome == .read, supplied.outcome == .read else {
            XCTFail("The small synthetic integration fixture must be representable in both arms")
            return
        }
        for arm in [frozen.automatic, supplied] {
            let direct = try model.readSuppliedOriginalGroups(source,
                originalIndexGroups: arm.glyphs.map(\.originalStrokeIndexes),
                currentProfile: profile)
            let expected = direct.glyphs.map { glyph in
                PersonalInkBlindPredictionFreeze.Glyph(
                    originalStrokeIndexes: glyph.originalStrokeIndexes,
                    sharedTop1: glyph.generic.first?.label,
                    personalTop1: glyph.personal.first?.label)
            }
            guard arm.glyphs == expected else {
                XCTFail("Blind freeze must equal the same actual CoreML fit's direct supplied-group top choices")
                return
            }
        }
        XCTAssertEqual(frozen.profileSHA256, sha256(profileData))
        XCTAssertEqual(try profileEncoder.encode(model.profile), profileData)
        guard try Data(contentsOf: sourceURL) == sourceData,
              try Data(contentsOf: manifestURL) == manifestData,
              try runtimeFileDigests(runtimeURL) == runtimeFiles else {
            XCTFail("Source or runtime bytes changed during the bridge gate")
            return
        }
        try frozen.canonicalData().write(to: reportURL, options: .withoutOverwriting)
        print("PERSONAL_BLIND_FREEZE_COREML_BRIDGE sourceStrokes=\(source.count) automaticGroups=\(frozen.automatic.glyphs.count) suppliedGroups=\(supplied.glyphs.count) sourcePreserved=true profilePreserved=true noTeaching=true")
    }

    /// Source-only natural capture gate. The independently hashed private
    /// envelope supplies the exact saved profile; target groups are NOT glyph
    /// ownership and are never supplied to prediction. No truth is joined.
    func testProvidedNaturalSourceExportsAutomaticCoreMLBlindFreeze() throws {
        try providedNaturalCoreMLBlindFreeze(perLiveTarget: false)
    }

    /// Conditional automatic glyph evidence on every retained live chord target.
    /// Routing is observed app input, NOT independently verified glyph ownership.
    func testProvidedNaturalLiveTargetsExportAutomaticCoreMLBlindFreeze() throws {
        try providedNaturalCoreMLBlindFreeze(perLiveTarget: true)
    }

    /// Same unverified live routing, with original and anchored top-three ranks
    /// retained on identical automatic glyph groups. Still NOT a native result.
    func testProvidedNaturalLiveTargetsExportAnchoredCoreMLComparison() throws {
        try providedNaturalCoreMLBlindFreeze(perLiveTarget: true, includeAnchored: true)
    }

    private func providedNaturalCoreMLBlindFreeze(perLiveTarget: Bool, includeAnchored: Bool = false) throws {
        let env = ProcessInfo.processInfo.environment
        let names = ["ICHART_PERSONAL_ML_RUNTIME_DIRECTORY", "ICHART_BLIND_EVALUATION_SOURCE_PACKET",
            "ICHART_BLIND_EVALUATION_SOURCE_ENVELOPE", "ICHART_BLIND_EVALUATION_SOURCE_ENVELOPE_SHA256",
            "ICHART_BLIND_EVALUATION_SOURCE_SHA256", "ICHART_BLIND_EVALUATION_RUNTIME_SHA256",
            "ICHART_BLIND_EVALUATION_CODE_SHA256", "ICHART_BLIND_EVALUATION_CODE_FILES_JSON",
            "ICHART_BLIND_EVALUATION_REPOSITORY_ROOT", "ICHART_BLIND_EVALUATION_REPORT"]
        guard names.allSatisfy({ env[$0] != nil }) else {
            throw XCTSkip("Provide exact source/envelope, frozen profile, pinned runtime/code map and exclusive report path")
        }
        guard names.allSatisfy({ !(env[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              env["ICHART_BLIND_EVALUATION_GROUPS"] == nil,
              env["ICHART_BLIND_EVALUATION_OWNERSHIP_SHA256"] == nil else {
            XCTFail("Natural source gate is automatic-only; no supplied ownership or empty environment values")
            return
        }
        func url(_ name: String) -> URL {
            URL(fileURLWithPath: env[name]!).standardizedFileURL.resolvingSymlinksInPath()
        }
        let sourceURL = url(names[1]), envelopeURL = url(names[2]), runtimeURL = url(names[0])
        let codeMapURL = url(names[7]), repositoryURL = url(names[8]), reportURL = url(names[9])
        guard ![sourceURL, envelopeURL, codeMapURL].contains(reportURL),
              !reportURL.path.hasPrefix(runtimeURL.path + "/"),
              !reportURL.path.hasPrefix(repositoryURL.path + "/"),
              !FileManager.default.fileExists(atPath: reportURL.path),
              (try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max)
                <= PersonalInkBlindPredictionFreeze.maximumPacketBytes,
              (try envelopeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 24 * 1_024 * 1_024,
              (try codeMapURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_024 * 1_024 else {
            XCTFail("Source inputs must be bounded; report must be new and outside source/runtime/repository")
            return
        }
        // Exact immutable reads precede constructing or querying the encoder.
        let sourceData = try Data(contentsOf: sourceURL)
        let envelopeData = try Data(contentsOf: envelopeURL)
        let codeMapData = try Data(contentsOf: codeMapURL)
        let packet = try PersonalInkBlindPredictionFreeze.decodeBoundedPacket(sourceData)
        let envelope = try JSONDecoder().decode(NaturalBlindSourceEnvelope.self, from: envelopeData)
        let profile = envelope.frozenProfile
        let json = JSONEncoder(); json.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let profileData = try json.encode(profile)
        let codeFiles = try JSONDecoder().decode([String: String].self, from: codeMapData)
        let requiredCodePaths = includeAnchored ? naturalBlindCodePaths.union([
            "iChart/Recognition/PersonalInkBlindAnchoredComparisonFreeze.swift",
            "iChartTests/Recognition/PersonalInkBlindAnchoredComparisonFreezeTests.swift"
        ]) : naturalBlindCodePaths
        guard envelope.version == "blind-ink-capture-source-envelope-v1",
              envelope.artifactKind == "engineering-only-local-development-capture-v1",
              !envelope.trainingEligible, profile.isEnabled,
              envelope.profileLineage == PersonalInkProfileLineageSummary(profile: profile, querySessionID: envelope.runID),
              envelope.sourceSnapshot.canonicalVisibleTrajectoryData == sourceData,
              sha256(sourceData) == env[names[4]], sha256(envelopeData) == env[names[3]],
              try json.encode(codeFiles) == codeMapData,
              sha256(codeMapData) == env[names[6]],
              requiredCodePaths.isSubset(of: Set(codeFiles.keys)),
              try sourceCodeDigests(repositoryURL, paths: Set(codeFiles.keys)) == codeFiles else {
            XCTFail("Source/envelope/profile or actual source-code hash bindings disagree")
            return
        }
        // Snapshot decoding invokes existing request/revision/geometry/index
        // validation. These IDs remain source context, not glyph truth.
        try envelope.sourceSnapshot.validate()
        let manifestURL = runtimeURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let runtimeFiles = try runtimeFileDigests(runtimeURL)
        guard sha256(manifestData) == PersonalInkVisualEncoder.anchoredManifestSHA256,
              sha256(try json.encode(runtimeFiles)) == env[names[5]] else {
            XCTFail("Runtime must match the pinned anchored manifest and complete verified file map")
            return
        }
        let encoder = try PersonalInkVisualEncoder(directory: runtimeURL)
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder, grouping: .losslessSourceV2)
        guard encoder.vocabulary.count == 97, model.anchoredAvailable else {
            XCTFail("Natural gate requires the same pinned anchored CoreML reader")
            return
        }
        let reportData: Data
        let statusLog: String
        if perLiveTarget {
            let source = packet.preparedStrokes()
            let snapshot = envelope.sourceSnapshot
            var targets: [NaturalLiveTargetPrediction] = []
            for group in snapshot.ownership.targetGroups {
                let childToParent = group.visibleFragmentIndices
                let child = childToParent.map { source[$0] }
                let childData = try ChordInkCanonicalTrajectoryPacket(strokes: child).canonicalData()
                let anchored: PersonalInkBlindAnchoredComparisonFreeze?
                let prediction: PersonalInkBlindPredictionFreeze
                if includeAnchored {
                    let comparison = try PersonalInkBlindAnchoredComparisonFreeze.freeze(sourcePacketData: childData,
                        suppliedOriginalIndexGroups: nil, ownershipReceiptSHA256: nil,
                        runtimeSHA256: env[names[5]]!, codeSHA256: env[names[6]]!, model: model,
                        currentProfile: { profile })
                    anchored = comparison
                    prediction = comparison.legacyFreeze
                } else {
                    anchored = nil
                    prediction = try PersonalInkBlindPredictionFreeze.freeze(sourcePacketData: childData,
                        suppliedOriginalIndexGroups: nil, ownershipReceiptSHA256: nil,
                        runtimeSHA256: env[names[5]]!, codeSHA256: env[names[6]]!, model: model,
                        currentProfile: { profile })
                }
                guard prediction.supplied == nil, prediction.ownershipReceiptSHA256 == nil,
                      prediction.profileSHA256 == sha256(profileData) else {
                    XCTFail("Live target must preserve exact profile and automatic-only boundary")
                    return
                }
                let globalGlyphs = prediction.automatic.glyphs.map { glyph in
                    PersonalInkBlindPredictionFreeze.Glyph(
                        originalStrokeIndexes: glyph.originalStrokeIndexes.map { childToParent[$0] },
                        sharedTop1: glyph.sharedTop1, personalTop1: glyph.personalTop1)
                }
                let globalAnchoredGlyphs = anchored?.automatic.glyphs.map { glyph in
                    PersonalInkBlindAnchoredComparisonFreeze.Glyph(
                        originalStrokeIndexes: glyph.originalStrokeIndexes.map { childToParent[$0] },
                        sharedRanks: glyph.sharedRanks, originalResidualRanks: glyph.originalResidualRanks,
                        anchoredRanks: glyph.anchoredRanks)
                }
                if prediction.automatic.outcome == .read {
                    let direct = try model.readSuppliedOriginalGroups(child,
                        originalIndexGroups: prediction.automatic.glyphs.map(\.originalStrokeIndexes), currentProfile: profile)
                    let expected = direct.glyphs.map { PersonalInkBlindPredictionFreeze.Glyph(
                        originalStrokeIndexes: $0.originalStrokeIndexes,
                        sharedTop1: $0.generic.first?.label, personalTop1: $0.personal.first?.label) }
                    let readIndexes = globalGlyphs.flatMap(\.originalStrokeIndexes)
                    guard prediction.automatic.glyphs == expected,
                          readIndexes.count == childToParent.count, Set(readIndexes) == Set(childToParent) else {
                        XCTFail("Live target automatic evidence must match the same reader and preserve every child index")
                        return
                    }
                    if let anchored {
                        let expectedAnchored = try PersonalInkBlindAnchoredComparisonFreeze.align(
                            legacyArm: prediction.automatic, reading: direct,
                            sourceStrokeCount: child.count, encoderIdentity: model.encoderIdentity,
                            anchoredAvailable: model.anchoredAvailable)
                        guard anchored.automatic == expectedAnchored,
                              anchored.legacyCanonicalData == (try prediction.canonicalData()),
                              globalAnchoredGlyphs?.map(\.originalStrokeIndexes) == globalGlyphs.map(\.originalStrokeIndexes) else {
                            XCTFail("Anchored and original evidence must match the same direct reader and exact global glyph mapping")
                            return
                        }
                    }
                }
                targets.append(.init(parentSourcePacketSHA256: sha256(sourceData),
                    sourceRequestID: snapshot.requestID, sourceInkRevision: snapshot.inkRevision,
                    targetOrdinal: group.targetOrdinal, childToParentOriginalStrokeIndexes: childToParent,
                    childCanonicalTrajectoryData: childData, prediction: prediction,
                    globalAutomaticGlyphs: globalGlyphs, anchoredComparison: anchored,
                    globalAnchoredGlyphs: globalAnchoredGlyphs))
            }
            let attempted = targets.flatMap(\.childToParentOriginalStrokeIndexes)
            let retainedRemainder = snapshot.ownership.barlineVisibleFragmentIndices
                + snapshot.ownership.unassignedVisibleFragmentIndices
            guard targets.map(\.targetOrdinal) == snapshot.ownership.targetGroups.map(\.targetOrdinal),
                  attempted.count == Set(attempted).count,
                  Set(attempted).isDisjoint(with: Set(retainedRemainder)),
                  Set(attempted + retainedRemainder) == Set(source.indices),
                  Set(attempted + snapshot.ownership.unassignedVisibleFragmentIndices)
                    == Set(snapshot.recognitionVisibleFragmentIndices) else {
                XCTFail("Conditional target diagnostic must account for the complete parent, including unassigned ink")
                return
            }
            reportData = try json.encode(NaturalLiveTargetDiagnostic(
                version: includeAnchored ? "blind-live-target-anchored-comparison-v1" : "blind-live-target-conditional-predictions-v1",
                nativeLiveResult: includeAnchored ? false : nil,
                runID: envelope.runID, parentSourcePacketSHA256: sha256(sourceData),
                sourceEnvelopeSHA256: sha256(envelopeData), parentCanonicalTrajectoryData: sourceData,
                sourceRequestID: snapshot.requestID, sourceInkRevision: snapshot.inkRevision,
                parentOwnership: snapshot.ownership, recognitionVisibleFragmentIndices: snapshot.recognitionVisibleFragmentIndices,
                profileSHA256: sha256(profileData), encoderIdentity: model.encoderIdentity,
                runtimeSHA256: env[names[5]]!, codeSHA256: env[names[6]]!, targets: targets))
            statusLog = "PERSONAL_BLIND_LIVE_TARGETS_COREML anchoredComparison=\(includeAnchored) parentSHA256=\(sha256(sourceData)) profileSHA256=\(sha256(profileData)) profileExamples=\(profile.examples.count) targetsAttempted=\(targets.count) readTargets=\(targets.filter { $0.prediction.automatic.outcome == .read }.count) invalidTargets=\(targets.filter { $0.prediction.automatic.outcome == .invalidInk }.count) unassigned=\(snapshot.ownership.unassignedVisibleFragmentIndices) wholeChartCompletenessClaimed=false glyphOwnershipVerified=false noTruthJoin=true noTeaching=true"
        } else {
        let frozen = try PersonalInkBlindPredictionFreeze.freeze(sourcePacketData: sourceData,
            suppliedOriginalIndexGroups: nil, ownershipReceiptSHA256: nil,
            runtimeSHA256: env[names[5]]!, codeSHA256: env[names[6]]!, model: model, currentProfile: { profile })
        if frozen.automatic.outcome == .read {
            let direct = try model.readSuppliedOriginalGroups(packet.preparedStrokes(),
                originalIndexGroups: frozen.automatic.glyphs.map(\.originalStrokeIndexes), currentProfile: profile)
            let expected = direct.glyphs.map { PersonalInkBlindPredictionFreeze.Glyph(
                originalStrokeIndexes: $0.originalStrokeIndexes,
                sharedTop1: $0.generic.first?.label, personalTop1: $0.personal.first?.label) }
            guard frozen.automatic.glyphs == expected else {
                XCTFail("Automatic top choices must match the same frozen model's exact group reader")
                return
            }
        }
        // Invalid ink (including more than 16 automatic groups) is exported,
        // not excluded or repaired with captured chord targets/answer labels.
        guard frozen.supplied == nil, frozen.ownershipReceiptSHA256 == nil,
              frozen.profileSHA256 == sha256(profileData) else {
            XCTFail("Full-source freeze must preserve exact profile and automatic-only boundary")
            return
        }
        reportData = try frozen.canonicalData()
        statusLog = "PERSONAL_BLIND_NATURAL_COREML sourceSHA256=\(frozen.sourcePacketSHA256) envelopeSHA256=\(sha256(envelopeData)) requestID=\(envelope.sourceSnapshot.requestID) inkRevision=\(envelope.sourceSnapshot.inkRevision) profileSHA256=\(frozen.profileSHA256) profileExamples=\(profile.examples.count) automaticOutcome=\(frozen.automatic.outcome.rawValue) automaticGroups=\(frozen.automatic.glyphs.count) supplied=null ownershipReceipt=null noTruthJoin=true noTeaching=true"
        }
        guard try json.encode(model.profile) == profileData,
              try Data(contentsOf: sourceURL) == sourceData,
              try Data(contentsOf: envelopeURL) == envelopeData,
              try Data(contentsOf: codeMapURL) == codeMapData,
              try Data(contentsOf: manifestURL) == manifestData,
              try runtimeFileDigests(runtimeURL) == runtimeFiles,
              try sourceCodeDigests(repositoryURL, paths: Set(codeFiles.keys)) == codeFiles else {
            XCTFail("Frozen source/envelope/profile/code/runtime changed before publication")
            return
        }
        try reportData.write(to: reportURL, options: .withoutOverwriting)
        print(statusLog)
    }

    private struct NaturalLiveTargetPrediction: Encodable {
        let parentSourcePacketSHA256: String
        let sourceRequestID: UUID
        let sourceInkRevision: UInt64
        let targetOrdinal: Int
        let childToParentOriginalStrokeIndexes: [Int]
        let childCanonicalTrajectoryData: Data
        let prediction: PersonalInkBlindPredictionFreeze
        let globalAutomaticGlyphs: [PersonalInkBlindPredictionFreeze.Glyph]
        // Omitted for the legacy exporter, preserving its artifact shape.
        let anchoredComparison: PersonalInkBlindAnchoredComparisonFreeze?
        let globalAnchoredGlyphs: [PersonalInkBlindAnchoredComparisonFreeze.Glyph]?
    }

    private struct NaturalLiveTargetDiagnostic: Encodable {
        let version: String
        let artifactKind = "engineering-only-unverified-live-routing-diagnostic-v1"
        let nativeLiveResult: Bool?
        let trainingEligible = false
        let glyphOwnershipVerified = false
        let chordRoutingVerified = false
        let accuracyMeasured = false
        let predictionChronologyVerified = false
        let writerIdentityVerified = false
        let consentVerified = false
        let rawOriginalDrawingArchived = false
        let fullChordAccuracyMeasured = false
        let automaticPolicy = PersonalInkLearnedComparison.Grouping.losslessSourceV2.rawValue
        let wholeChartCompletenessClaimed = false
        let unassignedGlyphInferencePerformed = false
        let allRetainedLiveTargetsAttempted = true
        let runID: UUID
        let parentSourcePacketSHA256: String
        let sourceEnvelopeSHA256: String
        let parentCanonicalTrajectoryData: Data
        let sourceRequestID: UUID
        let sourceInkRevision: UInt64
        let parentOwnership: ChordInkTargetOwnershipSnapshot
        let recognitionVisibleFragmentIndices: [Int]
        let profileSHA256: String
        let encoderIdentity: String
        let runtimeSHA256: String
        let codeSHA256: String
        let targets: [NaturalLiveTargetPrediction]
    }

    private struct NaturalBlindSourceEnvelope: Decodable {
        let version: String
        let artifactKind: String
        let trainingEligible: Bool
        let runID: UUID
        let sourceSnapshot: PersonalInkEvaluationSourceSnapshot
        let frozenProfile: PersonalInkProfile
        let profileLineage: PersonalInkProfileLineageSummary
    }

    private var naturalBlindCodePaths: Set<String> { [
        "iChart/Recognition/PersonalInkBlindPredictionFreeze.swift",
        "iChart/Recognition/PersonalInkLearnedComparison.swift",
        "iChart/Recognition/PersonalInkVisualEncoder.swift",
        "iChart/Recognition/PersonalInkResidualHead.swift",
        "iChart/Recognition/PersonalInkAnchoredResidualHead.swift",
        "iChart/Recognition/PersonalInkAdaptiveHead.swift",
        "iChart/Recognition/ChordInkPersonalization.swift",
        "iChart/Recognition/PersonalInkLearningLineage.swift",
        "iChart/Recognition/PersonalInkEvaluationSource.swift",
        "iChart/Recognition/ChordInkTargetOwnershipSnapshot.swift",
        "iChart/Recognition/ChordInkCanonicalTrajectoryPacket.swift",
        "iChart/Recognition/InkTrajectoryTypes.swift",
        "iChart/Recognition/StrokeClusterer.swift",
        "iChart/Recognition/StrokeClustererSupport.swift",
        "iChart/Recognition/Learned/ChordInkRasterizer.swift",
        "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
        "iChart/Services/ChordRecognitionCompendium.swift",
        "iChartTests/Recognition/PersonalInkBlindPredictionFreezeTests.swift"
    ] }

    private func sourceCodeDigests(_ root: URL, paths: Set<String>) throws -> [String: String] {
        guard (1...1_024).contains(paths.count) else { throw PersonalInkLearnedComparison.Failure.invalidEncoder }
        var result: [String: String] = [:]
        for path in paths {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw PersonalInkLearnedComparison.Failure.invalidEncoder
            }
            let file = root.appendingPathComponent(path).standardizedFileURL
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard file.path.hasPrefix(root.path + "/"), file.resolvingSymlinksInPath() == file,
                  properties.isRegularFile == true, properties.isSymbolicLink != true,
                  (properties.fileSize ?? Int.max) <= 4 * 1_024 * 1_024 else {
                throw PersonalInkLearnedComparison.Failure.invalidEncoder
            }
            result[path] = sha256(try Data(contentsOf: file))
        }
        return result
    }

    private func runtimeFileDigests(_ directory: URL) throws -> [String: String] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: directory.path))
        var files: [String: String] = [:]
        for case let relativePath as String in enumerator {
            let url = directory.appendingPathComponent(relativePath)
            let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isSymbolicLink != true else {
                XCTFail("Verified runtime fixture cannot contain a symbolic link")
                throw PersonalInkLearnedComparison.Failure.invalidEncoder
            }
            if properties.isRegularFile == true {
                files[relativePath] = sha256(try Data(contentsOf: url))
            }
        }
        guard !files.isEmpty else { throw PersonalInkLearnedComparison.Failure.invalidEncoder }
        return files
    }
    #endif

    private func freeze(_ data: Data, model: PersonalInkLearnedComparison,
                        profile: PersonalInkProfile, groups: [[Int]]? = nil) throws
        -> PersonalInkBlindPredictionFreeze {
        try .freeze(sourcePacketData: data, suppliedOriginalIndexGroups: groups,
            ownershipReceiptSHA256: ownershipDigest, runtimeSHA256: runtimeDigest,
            codeSHA256: codeDigest, model: model, currentProfile: { profile })
    }

    private func packetData(_ strokes: [InkStroke]) throws -> Data {
        try ChordInkCanonicalTrajectoryPacket(strokes: strokes).canonicalData()
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeSource(count: Int) -> [InkStroke] {
        (0..<count).map { index in
            let x = Double(index * 200)
            let points = [
                InkPoint(x: x, y: 7, timeOffset: Double(index) * 0.01 + 0.001),
                InkPoint(x: x + 5, y: 19, timeOffset: Double(index) * 0.01 + 0.041),
                InkPoint(x: x + 9, y: 13, timeOffset: Double(index) * 0.01 + 0.083)
            ]
            return InkStroke(points: points,
                bounds: InkBounds(minX: x - 0.25, minY: 6.5, maxX: x + 9.75, maxY: 19.75),
                creationTimeOffset: Double(index) + 0.375)
        }
    }

    private func profileWithWholeChordLessons() throws -> PersonalInkProfile {
        var profile = enabledProfile
        try profile.learn(strokes: [InkStroke(points: [.init(x: 0, y: 0), .init(x: 0, y: 20)])],
            label: "C", kind: .chord, source: .setup)
        try profile.learn(strokes: [InkStroke(points: [.init(x: 0, y: 0), .init(x: 20, y: 0)])],
            label: "D", kind: .chord, source: .setup)
        return profile
    }

    private func assertModelFailure<T>(_ expected: PersonalInkLearnedComparison.Failure,
                                      file: StaticString = #filePath, line: UInt = #line,
                                      operation: () throws -> T) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard let actual = error as? PersonalInkLearnedComparison.Failure else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            switch (expected, actual) {
            case (.disabled, .disabled), (.staleProfile, .staleProfile), (.invalidEncoder, .invalidEncoder):
                break
            default:
                XCTFail("Unexpected model failure: \(actual)", file: file, line: line)
            }
        }
    }
}
