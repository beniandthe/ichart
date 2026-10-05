import Foundation
import CryptoKit
import XCTest
@testable import iChart

/// Synthetic identity/commitment contracts, not recognition accuracy.
final class PersonalInkBlindAnchoredComparisonFreezeTests: XCTestCase {
    private enum EncoderError: Error { case technical }
    private final class Encoder: PersonalInkVisualEncoding {
        let identity = "synthetic/anchored-comparison/ø"
        let vocabulary = ["A", "B", "/"]
        let anchorBank: PersonalInkAnchorBank?
        var inputs: [[InkStroke]] = []
        var onEncode: (() -> Void)?
        var failureAt: Int?
        init(anchors: Bool) {
            let features = (0..<128).map { $0 == 0 ? 1.0 : 0.0 }
            anchorBank = anchors ? .init(vocabulary: vocabulary, features: Array(repeating: features, count: 3)) : nil
        }
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            inputs.append(strokes)
            onEncode?()
            if inputs.count == failureAt { throw EncoderError.technical }
            return .init(embedding: (0..<128).map { $0 == 0 ? 1.0 : 0.0 }, genericLogits: [-3, -3, 3])
        }
    }
    private let runtime = String(repeating: "a", count: 64)
    private let code = String(repeating: "b", count: 64)
    private var enabled: PersonalInkProfile {
        var value = PersonalInkProfile(); value.isEnabled = true; return value
    }
    private func source(_ count: Int) -> [InkStroke] {
        (0..<count).map { index in
            let x = Double(index * 200)
            return InkStroke(points: [.init(x: x, y: 2, timeOffset: 0.1),
                                      .init(x: x + 6, y: 20, timeOffset: 0.2)],
                bounds: .init(minX: x - 0.5, minY: 1.5, maxX: x + 6.5, maxY: 20.5),
                creationTimeOffset: Double(index) + 0.375)
        }
    }
    private func packet(_ strokes: [InkStroke]) throws -> Data {
        try ChordInkCanonicalTrajectoryPacket(strokes: strokes).canonicalData()
    }
    private func freeze(_ data: Data, model: PersonalInkLearnedComparison,
                        current: () -> PersonalInkProfile, groups: [[Int]]? = nil) throws
        -> PersonalInkBlindAnchoredComparisonFreeze {
        try .freeze(sourcePacketData: data, suppliedOriginalIndexGroups: groups,
            ownershipReceiptSHA256: nil, runtimeSHA256: runtime, codeSHA256: code,
            model: model, currentProfile: current)
    }

    func testExactLegacyBytesAndBothHeadsMatchDirectReaderOnIdenticalGroups() throws {
        var profile = enabled
        try profile.learn(strokes: source(1), label: "A", kind: .glyph, source: .setup)
        let encoder = Encoder(anchors: true)
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        var strokes = source(3)
        strokes[0].points[0].x = Double(bitPattern: 0x8000_0000_0000_0000)
        let data = try packet(strokes)
        let profileEncoder = JSONEncoder(); profileEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let profileData = try profileEncoder.encode(profile)
        let groups = [[2], [1, 0]]
        let legacy = try PersonalInkBlindPredictionFreeze.freeze(sourcePacketData: data,
            suppliedOriginalIndexGroups: groups, ownershipReceiptSHA256: nil,
            runtimeSHA256: runtime, codeSHA256: code, model: model, currentProfile: { profile })
        let result = try freeze(data, model: model, current: { profile }, groups: groups)
        XCTAssertEqual(result.legacyFreeze, legacy)
        XCTAssertEqual(result.legacyCanonicalData, try legacy.canonicalData())
        XCTAssertEqual(result.legacyCanonicalSHA256, digest(result.legacyCanonicalData))
        for arm in [result.automatic, try XCTUnwrap(result.supplied)] {
            XCTAssertEqual(arm.anchorStatus, .available)
            let direct = try model.readSuppliedOriginalGroups(strokes,
                originalIndexGroups: arm.glyphs.map(\.originalStrokeIndexes), currentProfile: profile)
            for (index, glyph) in arm.glyphs.enumerated() {
                XCTAssertEqual(glyph.sharedRanks, direct.glyphs[index].generic)
                XCTAssertEqual(glyph.originalResidualRanks, direct.glyphs[index].personal)
                XCTAssertEqual(glyph.anchoredRanks, direct.anchoredGlyphRanks?[index])
                XCTAssertEqual(glyph.anchoredTop1, direct.anchoredGlyphRanks?[index].first?.label)
            }
        }
        XCTAssertNotEqual(result.automatic.glyphs.first?.originalResidualTop1, result.automatic.glyphs.first?.anchoredTop1)
        XCTAssertEqual(try packet(strokes), data)
        XCTAssertEqual(try profileEncoder.encode(profile), profileData)
        XCTAssertEqual(try profileEncoder.encode(model.profile), profileData)
        XCTAssertEqual(result.legacyFreeze.profileSHA256, digest(profileData))
        XCTAssertEqual(try result.canonicalData(), try result.canonicalData())
    }

    func testAbsentAnchorsAreExplicitUnavailableNeverSharedFallback() throws {
        let profile = enabled, encoder = Encoder(anchors: false)
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let result = try freeze(packet(source(1)), model: model, current: { profile })
        XCTAssertEqual(result.automatic.anchorStatus, .unavailable)
        let glyph = try XCTUnwrap(result.automatic.glyphs.first)
        XCTAssertNotNil(glyph.sharedTop1)
        XCTAssertNotNil(glyph.originalResidualTop1)
        XCTAssertNil(glyph.anchoredRanks)
        XCTAssertNil(glyph.anchoredTop1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: result.canonicalData()) as? [String: Any])
        XCTAssertTrue(object["supplied"] is NSNull)
        let arm = try XCTUnwrap(object["automatic"] as? [String: Any])
        let glyphs = try XCTUnwrap(arm["glyphs"] as? [[String: Any]])
        XCTAssertTrue(glyphs[0]["anchoredRanks"] is NSNull)
        XCTAssertTrue(glyphs[0]["anchoredTop1"] is NSNull)
        XCTAssertEqual(object["nativeLiveResult"] as? Bool, false)
        XCTAssertEqual(object["accuracyMeasured"] as? Bool, false)
        XCTAssertEqual(object["trainingEligible"] as? Bool, false)
    }

    func testInvalidArmsAndIndependentSuppliedRouteRetainCompleteAttempt() throws {
        let profile = enabled, encoder = Encoder(anchors: true)
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let empty = try freeze(packet([]), model: model, current: { profile }, groups: [])
        XCTAssertEqual(empty.automatic.outcome, .invalidInk)
        XCTAssertEqual(empty.supplied?.outcome, .invalidInk)
        XCTAssertTrue(empty.automatic.glyphs.isEmpty)
        XCTAssertTrue(encoder.inputs.isEmpty)
        let many = try freeze(packet(source(17)), model: model, current: { profile }, groups: [Array(0..<17)])
        XCTAssertEqual(many.automatic.outcome, .invalidInk)
        XCTAssertEqual(many.automatic.anchorStatus, .available)
        XCTAssertEqual(many.supplied?.outcome, .read)
        XCTAssertEqual(many.supplied?.glyphs.first?.originalStrokeIndexes, Array(0..<17))
    }

    func testMalformedPartitionRejectedBeforeQueriesAndAlignedNullReadsStayNull() throws {
        let profile = enabled, encoder = Encoder(anchors: true)
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        XCTAssertThrowsError(try freeze(packet(source(2)), model: model, current: { profile }, groups: [[0], [0]]))
        XCTAssertTrue(encoder.inputs.isEmpty)
        let legacy = PersonalInkBlindPredictionFreeze.Arm(outcome: .read, glyphs: [
            .init(originalStrokeIndexes: [0], sharedTop1: nil, personalTop1: nil)])
        let reading = PersonalInkLearnedComparison.GroupIdentityReading(sourceStrokeCount: 1, encoderIdentity: encoder.identity,
            glyphs: [.init(originalStrokeIndexes: [0], generic: [], personal: [])], anchoredGlyphRanks: [[]])
        let arm = try PersonalInkBlindAnchoredComparisonFreeze.align(legacyArm: legacy, reading: reading,
            sourceStrokeCount: 1, encoderIdentity: encoder.identity, anchoredAvailable: true)
        XCTAssertEqual(arm.anchorStatus, .available)
        XCTAssertNil(arm.glyphs[0].sharedTop1)
        XCTAssertNil(arm.glyphs[0].originalResidualTop1)
        XCTAssertNil(arm.glyphs[0].anchoredTop1)
        XCTAssertEqual(arm.glyphs[0].anchoredRanks, [])
        let broken = PersonalInkLearnedComparison.GroupIdentityReading(sourceStrokeCount: 1, encoderIdentity: encoder.identity,
            glyphs: reading.glyphs, anchoredGlyphRanks: [])
        XCTAssertThrowsError(try PersonalInkBlindAnchoredComparisonFreeze.align(legacyArm: legacy, reading: broken,
            sourceStrokeCount: 1, encoderIdentity: encoder.identity, anchoredAvailable: true))
        let changed = PersonalInkLearnedComparison.GroupIdentityReading(sourceStrokeCount: 1, encoderIdentity: encoder.identity,
            glyphs: [.init(originalStrokeIndexes: [0], generic: [.init(label: "A", score: 1)], personal: [])],
            anchoredGlyphRanks: [[]])
        XCTAssertThrowsError(try PersonalInkBlindAnchoredComparisonFreeze.align(legacyArm: legacy, reading: changed,
            sourceStrokeCount: 1, encoderIdentity: encoder.identity, anchoredAvailable: true)) { error in
                XCTAssertEqual(error as? PersonalInkBlindAnchoredComparisonFreeze.Failure, .legacyTop1Mismatch)
            }
    }

    func testProfileMutationDisableAndTechnicalFailureDuringAnchoredRereadThrow() throws {
        for disables in [false, true] {
            var current = enabled
            let encoder = Encoder(anchors: true)
            let model = try PersonalInkLearnedComparison(profile: current, encoder: encoder)
            encoder.onEncode = {
                if encoder.inputs.count == 2 {
                    if disables { current.isEnabled = false } else { current.learnsFromReviews.toggle() }
                }
            }
            XCTAssertThrowsError(try freeze(packet(source(1)), model: model, current: { current })) { error in
                guard let failure = error as? PersonalInkLearnedComparison.Failure else {
                    return XCTFail("Profile failure must not become an invalid-ink artifact")
                }
                switch failure {
                case .disabled: XCTAssertTrue(disables)
                case .staleProfile: XCTAssertFalse(disables)
                default: XCTFail("Unexpected profile failure")
                }
            }
        }
        let profile = enabled, encoder = Encoder(anchors: true)
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        encoder.failureAt = 2
        XCTAssertThrowsError(try freeze(packet(source(1)), model: model, current: { profile })) { error in
            XCTAssertTrue(error is EncoderError)
        }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
