import Foundation
import CryptoKit
import XCTest
@testable import iChart

/// Synthetic artifact contracts only; no handwriting-quality or live-use claim.
final class PersonalInkBlindLocalAnchoredComparisonFreezeTests: XCTestCase {
    private enum EncoderError: Error { case technical }
    private final class Encoder: PersonalInkVisualEncoding {
        let identity = "synthetic/local-anchored-freeze/ø"
        let vocabulary = ["A", "B", "/", "ø"]
        let anchorBank: PersonalInkAnchorBank?
        var inputs: [[InkStroke]] = []
        var onEncode: (() -> Void)?
        var technicalFailure = false
        init() {
            anchorBank = .init(vocabulary: vocabulary,
                features: (0..<4).map { index in (0..<128).map { $0 == index ? 1.0 : 0.0 } })
        }
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            inputs.append(strokes); onEncode?()
            if technicalFailure { throw EncoderError.technical }
            return .init(embedding: (0..<128).map { $0 == 0 ? 1.0 : 0.0 }, genericLogits: [-3, -3, 3, -3])
        }
    }
    private let runtime = String(repeating: "a", count: 64)
    private let code = String(repeating: "b", count: 64)
    private var enabled: PersonalInkProfile {
        var profile = PersonalInkProfile(); profile.isEnabled = true; return profile
    }
    private func source(_ count: Int) -> [InkStroke] {
        (0..<count).map { index in
            let x = Double(index * 200)
            return InkStroke(points: [.init(x: x, y: 2, timeOffset: 0.1), .init(x: x + 6, y: 20, timeOffset: 0.2)],
                bounds: .init(minX: x - 0.5, minY: 1.5, maxX: x + 6.5, maxY: 20.5),
                creationTimeOffset: Double(index) + 0.375)
        }
    }
    private func packet(_ strokes: [InkStroke]) throws -> Data {
        try ChordInkCanonicalTrajectoryPacket(strokes: strokes).canonicalData()
    }
    private func freeze(_ data: Data, model: PersonalInkLocalAnchoredComparison,
                        current: () -> PersonalInkProfile, groups: [[Int]]? = nil,
                        receipt: String? = nil) throws -> PersonalInkBlindLocalAnchoredComparisonFreeze {
        try .freeze(sourcePacketData: data, suppliedOriginalIndexGroups: groups,
            ownershipReceiptSHA256: receipt, runtimeSHA256: runtime, codeSHA256: code,
            model: model, currentProfile: current)
    }
    private func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func testFullRankDirectParityExactSourceProfileAndSupportWithNovelPadding() throws {
        var profile = enabled
        try profile.learn(strokes: source(1), label: "△", kind: .glyph, source: .setup)
        let encoder = Encoder(), model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        encoder.inputs = []
        var strokes = source(3)
        strokes[0].points[0].x = Double(bitPattern: 0x8000_0000_0000_0000)
        let data = try packet(strokes), before = try canonical(profile)
        let result = try freeze(data, model: model, current: { profile }, groups: [[2], [1, 0]], receipt: code)
        XCTAssertEqual(result.sourceCanonicalData, data)
        XCTAssertEqual(result.sourcePacketSHA256, digest(data))
        XCTAssertEqual(result.profileSHA256, digest(before))
        XCTAssertEqual(result.supportCanonicalData, try canonical(model.support))
        XCTAssertEqual(result.supportCanonicalSHA256, digest(result.supportCanonicalData))
        XCTAssertEqual(result.ownershipReceiptSHA256, code)
        XCTAssertEqual(result.vocabulary, encoder.vocabulary + ["△"])
        let automatic = try XCTUnwrap(result.automatic.reading), supplied = try XCTUnwrap(result.supplied?.reading)
        let policyGroups = StrokeClusterer(wrapperPolicy: .preserveOriginalInk)
            .indexedClusters(strokes.map { InkStroke(points: $0.points) }).map { $0.originalIndexes.sorted() }
        XCTAssertEqual(automatic.glyphs.map(\.originalStrokeIndexes), policyGroups)
        XCTAssertEqual(supplied.glyphs.map(\.originalStrokeIndexes), [[2], [0, 1]])
        for reading in [automatic, supplied] {
            let direct = try model.readSuppliedOriginalGroups(strokes,
                originalIndexGroups: reading.glyphs.map(\.originalStrokeIndexes), currentProfile: { profile })
            XCTAssertEqual(reading, direct)
            for glyph in reading.glyphs {
                for ranks in [glyph.sharedRanks, glyph.controlRanks, glyph.localRanks] {
                    XCTAssertEqual(ranks.count, model.vocabulary.count)
                    XCTAssertEqual(Set(ranks.map(\.label)), Set(model.vocabulary))
                    XCTAssertTrue(ranks.allSatisfy { $0.score.isFinite })
                }
                XCTAssertEqual(glyph.baseScores.last, 0)
                XCTAssertEqual(glyph.embedding.count, 128)
                XCTAssertEqual(reading.sharedChord, PersonalInkLearnedComparison.compose(reading.glyphs.map { $0.sharedRanks.first?.label }))
                XCTAssertEqual(reading.controlChord, PersonalInkLearnedComparison.compose(reading.glyphs.map { $0.controlRanks.first?.label }))
                XCTAssertEqual(reading.localChord, PersonalInkLearnedComparison.compose(reading.glyphs.map { $0.localRanks.first?.label }))
            }
        }
        XCTAssertEqual(try packet(strokes), data)
        XCTAssertEqual(try canonical(profile), before)
        XCTAssertEqual(try canonical(model.profile), before)
        XCTAssertEqual(try result.canonicalData(), try result.canonicalData())
        XCTAssertTrue(encoder.inputs.allSatisfy { input in input.allSatisfy { strokes.contains($0) } })
    }

    func testInvalidAttemptsIndependentSuppliedArmAndExplicitNullAssurances() throws {
        let profile = enabled, encoder = Encoder()
        let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        let empty = try freeze(packet([]), model: model, current: { profile }, groups: [])
        XCTAssertEqual(empty.automatic.outcome, .invalidInk)
        XCTAssertEqual(empty.supplied?.outcome, .invalidInk)
        XCTAssertNil(empty.automatic.reading)
        XCTAssertTrue(encoder.inputs.isEmpty)
        let many = try freeze(packet(source(17)), model: model, current: { profile }, groups: [Array(0..<17)])
        XCTAssertEqual(many.automatic.outcome, .invalidInk)
        XCTAssertEqual(many.supplied?.outcome, .read)
        XCTAssertEqual(many.supplied?.reading?.glyphs.first?.originalStrokeIndexes, Array(0..<17))
        let noSupplied = try freeze(packet(source(1)), model: model, current: { profile })
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: noSupplied.canonicalData()) as? [String: Any])
        XCTAssertTrue(object["supplied"] is NSNull)
        XCTAssertTrue(object["ownershipReceiptSHA256"] is NSNull)
        for key in ["nativeLiveResult", "ownershipVerified", "accuracyMeasured", "trainingEligible", "predictionChronologyVerified"] {
            XCTAssertEqual(object[key] as? Bool, false)
        }
        let emptyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: empty.canonicalData()) as? [String: Any])
        XCTAssertTrue((emptyObject["automatic"] as? [String: Any])?["reading"] is NSNull)
    }

    func testMalformedPartitionsCommitmentsAndPacketBudgetsRejectBeforeQueries() throws {
        let profile = enabled, encoder = Encoder()
        let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        let data = try packet(source(2))
        for groups in [[[0], [0]], [[0]], [[0, 1, 2]], [[0], []]] {
            XCTAssertThrowsError(try freeze(data, model: model, current: { profile }, groups: groups))
        }
        XCTAssertThrowsError(try freeze(packet(source(257)), model: model, current: { profile }))
        XCTAssertThrowsError(try freeze(data + Data([10]), model: model, current: { profile }))
        XCTAssertThrowsError(try freeze(data, model: model, current: { profile }, receipt: "unverified"))
        XCTAssertThrowsError(try PersonalInkBlindLocalAnchoredComparisonFreeze.freeze(sourcePacketData: data,
            ownershipReceiptSHA256: nil, runtimeSHA256: String(repeating: "A", count: 64), codeSHA256: code,
            model: model, currentProfile: { profile }))
        XCTAssertTrue(encoder.inputs.isEmpty)
    }

    func testProfileMutationOptOutAndTechnicalEncoderFailureAreNotInvalidInk() throws {
        for disables in [false, true] {
            var current = enabled
            let encoder = Encoder(), model = try PersonalInkLocalAnchoredComparison(profile: current, encoder: encoder)
            encoder.onEncode = { if disables { current.isEnabled = false } else { current.learnsFromReviews.toggle() } }
            XCTAssertThrowsError(try freeze(packet(source(1)), model: model, current: { current })) { error in
                guard let failure = error as? PersonalInkLearnedComparison.Failure else {
                    return XCTFail("Profile failure must throw, not turn into a geometry no-read")
                }
                switch failure {
                case .disabled: XCTAssertTrue(disables)
                case .staleProfile: XCTAssertFalse(disables)
                default: XCTFail("Unexpected profile failure")
                }
            }
        }
        let profile = enabled, encoder = Encoder()
        let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        encoder.technicalFailure = true
        XCTAssertThrowsError(try freeze(packet(source(1)), model: model, current: { profile })) { error in
            XCTAssertTrue(error is EncoderError)
        }
    }

    func testMalformedFullRankCoverageVectorHashAndFixedFirstChordFailClosed() throws {
        let profile = enabled, encoder = Encoder()
        let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        let data = try packet(source(1))
        let result = try freeze(data, model: model, current: { profile })
        let reading = try XCTUnwrap(result.automatic.reading)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: canonical(reading)) as? [String: Any])
        for defect in 0..<7 {
            var object = original
            var glyphs = try XCTUnwrap(object["glyphs"] as? [[String: Any]])
            switch defect {
            case 0:
                var ranks = try XCTUnwrap(glyphs[0]["sharedRanks"] as? [[String: Any]])
                ranks.removeLast(); glyphs[0]["sharedRanks"] = ranks
            case 1: glyphs[0]["embeddingSHA256"] = String(repeating: "0", count: 64)
            case 2: glyphs[0]["originalStrokeIndexes"] = [1]
            case 3: object["localChord"] = "C"
            case 4: object["version"] = "unbound-reading-version"
            case 5:
                var identity = try XCTUnwrap(object["modelIdentity"] as? [String: Any])
                identity["canonicalAnchorBankSHA256"] = String(repeating: "0", count: 64)
                object["modelIdentity"] = identity
            default:
                var support = try XCTUnwrap(object["support"] as? [String: Any])
                support["sha256"] = String(repeating: "0", count: 64)
                object["support"] = support
            }
            object["glyphs"] = glyphs
            let modified = try JSONDecoder().decode(PersonalInkLocalAnchoredComparison.Reading.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try PersonalInkBlindLocalAnchoredComparisonFreeze.validateReading(modified,
                groups: [[0]], sourceStrokeCount: 1, sourceSHA256: digest(data), model: model))
        }
    }
}
