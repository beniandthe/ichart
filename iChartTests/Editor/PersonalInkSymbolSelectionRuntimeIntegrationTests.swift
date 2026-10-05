#if DEBUG && canImport(UIKit) && canImport(CoreML)
import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// One synthetic lesson-intake/runtime connection check. The explicit label
/// is test supervision, not an adjudicated read or evidence of transfer.
@MainActor
final class PersonalInkSymbolSelectionRuntimeIntegrationTests: XCTestCase {
    func testRepairedSelectionPersistsAndReachesPinnedRuntimeWithoutChangingSharedReads() async throws {
        guard let runtime = PersonalInkVisualEncoder.bundledDirectory() else {
            throw XCTSkip("Requires the explicitly opted-in Debug v2 comparison package")
        }
        let resourceBytes = try resourceFiles(runtime)
        XCTAssertEqual(resourceBytes.count, 5)
        XCTAssertEqual(digest(try XCTUnwrap(resourceBytes["manifest.json"])),
                       PersonalInkVisualEncoder.anchoredManifestSHA256)
        XCTAssertEqual(digest(try XCTUnwrap(resourceBytes["public-anchors.json"])),
                       PersonalInkVisualEncoder.anchorSHA256)
        defer { XCTAssertEqual(try? resourceFiles(runtime), resourceBytes) }
        guard testRun?.failureCount == 0 else { return }

        let encoder = try PersonalInkVisualEncoder(directory: runtime)
        XCTAssertEqual(encoder.vocabulary.count, 97)
        XCTAssertTrue(encoder.vocabulary.contains("D"))
        XCTAssertNotNil(encoder.anchorBank)
        guard testRun?.failureCount == 0 else { return }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profileURL = folder.appendingPathComponent("profile.json")
        let journalURL = folder.appendingPathComponent("evaluation.json")
        let store = PersonalInkProfileStore(url: profileURL)
        let source = [
            InkStroke(points: [.init(x: 10, y: 2, timeOffset: 0),
                               .init(x: 10, y: 26, timeOffset: 0.3)],
                      bounds: .init(minX: 9.5, minY: 1.5, maxX: 10.5, maxY: 26.5),
                      creationTimeOffset: 0.2),
            InkStroke(points: [.init(x: 42, y: 2, timeOffset: 0),
                               .init(x: 53, y: 2, timeOffset: 0.1),
                               .init(x: 44, y: 25, timeOffset: 0.4)],
                      bounds: .init(minX: 41.5, minY: 1.5, maxX: 53.5, maxY: 25.5),
                      creationTimeOffset: 0.8),
            InkStroke(points: [.init(x: 10, y: 2, timeOffset: 0),
                               .init(x: 22, y: 4, timeOffset: 0.1),
                               .init(x: 24, y: 15, timeOffset: 0.2),
                               .init(x: 20, y: 25, timeOffset: 0.3),
                               .init(x: 10, y: 26, timeOffset: 0.4)],
                      bounds: .init(minX: 9.5, minY: 1.5, maxX: 24.5, maxY: 26.5),
                      creationTimeOffset: 1.5)
        ]
        let context = PersonalInkCaptureContext(sessionID: UUID(), captureID: UUID(),
            capturedAt: Date(timeIntervalSinceReferenceDate: 100), origin: .savedEvaluation,
            chartStyle: "simple-chord-sheet")
        var parent = PersonalInkExample(kind: .chord, label: "D7", strokes: source,
                                       source: .explicitCorrection)
        parent.learningProvenance = try .make(context: context,
            taughtAt: Date(timeIntervalSinceReferenceDate: 101), originalInput: source, storedInput: source)
        try store.update { $0.isEnabled = true; $0.examples = [parent] }
        let beforeProfile = store.snapshot().profile
        var historical = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet",
            phase: .beforeCorrections, pipeline: "synthetic-selection-runtime-connection", profile: beforeProfile)
        historical.status = .complete
        let journalBytes = try JSONEncoder().encode(PersonalInkEvaluationJournal(runs: [historical]))
        try journalBytes.write(to: journalURL)

        let review = try PersonalInkSymbolTeachingReview(exampleID: parent.id, profile: beforeProfile)
        var draft = PersonalInkSymbolSelectionDraft(review: try review.selectingOriginalGroups([]))
        try draft.replacePiece(at: nil, withStrokeIndexes: [2, 0])
        XCTAssertEqual(draft.unassignedStrokeIndexes, [1])
        XCTAssertEqual(draft.labels, [nil])
        try draft.setLabel("D", forPiece: 0)
        let selected = try draft.makeReview()
        let piece = try XCTUnwrap(selected.pieces.first)
        XCTAssertEqual(piece.originalStrokeIndexes, [0, 2])
        XCTAssertEqual(piece.strokes, [source[0], source[2]])

        let beforeLocal = try PersonalInkLocalAnchoredComparison(profile: beforeProfile, encoder: encoder)
        let baselineLocal = try beforeLocal.readSuppliedOriginalGroups(piece.strokes,
            originalIndexGroups: [[1, 0]], currentProfile: { beforeProfile })
        let beforeApp = try PersonalInkLearnedComparison(profile: beforeProfile, encoder: encoder)
        let baselineApp = try beforeApp.readSuppliedOriginalGroups(piece.strokes,
            originalIndexGroups: [[1, 0]], currentProfile: beforeProfile)
        XCTAssertEqual(beforeLocal.support.supportExampleCount, 0)
        XCTAssertEqual(beforeApp.glyphLessonCount, 0)

        let app = PersonalHandwritingModel(store: store,
            evaluationStore: PersonalInkEvaluationStore(url: journalURL))
        let saved = expectation(description: "explicit repaired lesson saved by the app")
        app.teachSymbols(selected, labels: draft.labels) { receipt in
            XCTAssertEqual(receipt.selectedSymbolCount, 1)
            XCTAssertEqual(receipt.changedSymbolCount, 1)
            XCTAssertEqual(receipt.previousExampleCount, 1)
            XCTAssertEqual(receipt.savedExampleCount, 2)
            saved.fulfill()
        }
        await fulfillment(of: [saved], timeout: 5)
        XCTAssertFalse(app.busy)
        XCTAssertNil(app.error)
        let reloaded = PersonalInkProfileStore(url: profileURL)
        XCTAssertNil(reloaded.loadError)
        let profile = reloaded.snapshot().profile
        XCTAssertEqual(profile, app.profile)
        XCTAssertEqual(profile.generation, beforeProfile.generation)
        XCTAssertNotEqual(profile.revision, beforeProfile.revision)
        XCTAssertEqual(profile.examples.first, parent)
        XCTAssertEqual(profile.examples.count, 2)
        let lesson = try XCTUnwrap(profile.examples.first { $0.kind == .glyph })
        XCTAssertEqual(lesson.label, "D")
        XCTAssertEqual(lesson.source, .explicitCorrection)
        XCTAssertEqual(lesson.verifiedSymbolOrigin?.chordExampleID, parent.id)
        XCTAssertEqual(lesson.verifiedSymbolOrigin?.chordLabel, parent.label)
        XCTAssertEqual(lesson.verifiedSymbolOrigin?.originalStrokeIndexes, [0, 2])
        XCTAssertEqual(lesson.strokes, try XCTUnwrap(PersonalInkShape(strokes: piece.strokes)).normalizedStrokes)
        XCTAssertEqual(lesson.recognitionStrokes, piece.strokes)
        let provenance = try XCTUnwrap(lesson.learningProvenance)
        var selectedContext = context
        selectedContext.origin = .selectedSavedSymbol
        XCTAssertEqual(provenance.context, selectedContext)
        XCTAssertEqual(provenance.originalInputSHA256,
                       try PersonalInkLearningProvenance.inputSHA256(strokes: piece.strokes))
        XCTAssertNoThrow(try provenance.validate(storedInput: lesson.recognitionInput))
        XCTAssertEqual(try Data(contentsOf: journalURL), journalBytes)
        XCTAssertEqual(historical.profile, beforeProfile)
        guard testRun?.failureCount == 0 else { return }
        let profileBytes = try Data(contentsOf: profileURL)
        defer {
            XCTAssertEqual(try? Data(contentsOf: profileURL), profileBytes)
            XCTAssertEqual(try? Data(contentsOf: journalURL), journalBytes)
            XCTAssertEqual(reloaded.snapshot().profile, profile)
            XCTAssertEqual(store.snapshot().profile, profile)
        }

        // The concrete overload verifies pinned package lineage; both heads
        // remain comparison-only, with no assertions about the winning label.
        let local = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        XCTAssertEqual(local.modelIdentity.runtimeKind, PersonalInkLocalAnchoredComparison.pinnedRuntimeKind)
        XCTAssertEqual(local.modelIdentity.pinnedManifestArtifactSHA256,
                       PersonalInkVisualEncoder.anchoredManifestSHA256)
        XCTAssertEqual(local.modelIdentity.pinnedAnchorArtifactSHA256, PersonalInkVisualEncoder.anchorSHA256)
        XCTAssertEqual(local.support.supportExampleCount, 1)
        XCTAssertEqual(local.support.ignoredWholeChordCount, 1)
        XCTAssertEqual(local.support.labelCounts, ["D": 1])
        XCTAssertEqual(try local.support.recomputedSHA256(), local.support.sha256)
        let support = try XCTUnwrap(local.support.lessons.first)
        XCTAssertEqual(support.exampleID, lesson.id)
        XCTAssertEqual(support.label, lesson.label)
        XCTAssertEqual(support.source, lesson.source)
        XCTAssertTrue(support.hasVerifiedSymbolOrigin)
        XCTAssertTrue(support.hasLearningProvenance)
        XCTAssertEqual(support.intakeSessionID, context.sessionID)
        XCTAssertEqual(support.originalInputSHA256, provenance.originalInputSHA256)
        XCTAssertEqual(support.storedInkSHA256,
                       try PersonalInkLearningProvenance.inputSHA256(strokes: lesson.recognitionInput))
        let features = try encoder.encode(lesson.recognitionInput)
        assertVector(support.embedding, equals: features.embedding)
        assertVector(support.baseScores,
                     equals: try PersonalInkResidualHead.normalizedScores(logits: features.genericLogits))

        let reading = try local.readSuppliedOriginalGroups(piece.strokes,
            originalIndexGroups: [[1, 0]], currentProfile: { profile })
        XCTAssertEqual(reading.modelIdentity, local.modelIdentity)
        XCTAssertEqual(reading.sourceStrokeCount, 2)
        XCTAssertEqual(reading.sourceInkSHA256,
                       try PersonalInkLearningProvenance.inputSHA256(strokes: piece.strokes))
        XCTAssertEqual(reading.glyphs.count, 1)
        let glyph = try XCTUnwrap(reading.glyphs.first)
        XCTAssertEqual(glyph.originalStrokeIndexes, [0, 1])
        for ranks in [glyph.sharedRanks, glyph.controlRanks, glyph.localRanks] {
            XCTAssertEqual(ranks.count, local.vocabulary.count)
            XCTAssertEqual(Set(ranks.map(\.label)), Set(local.vocabulary))
            XCTAssertTrue(ranks.allSatisfy { $0.score.isFinite })
        }
        XCTAssertEqual(reading.glyphs.map(\.sharedRanks), baselineLocal.glyphs.map(\.sharedRanks))

        let learned = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        XCTAssertEqual(learned.glyphLessonCount, 1)
        XCTAssertTrue(learned.anchoredAvailable)
        let appReading = try learned.readSuppliedOriginalGroups(piece.strokes,
            originalIndexGroups: [[1, 0]], currentProfile: profile)
        XCTAssertEqual(appReading.glyphs.map(\.generic), baselineApp.glyphs.map(\.generic))
        XCTAssertEqual(appReading.glyphs.map(\.originalStrokeIndexes), [[0, 1]])
        let anchored = try XCTUnwrap(appReading.anchoredGlyphRanks)
        XCTAssertEqual(anchored.count, 1)
        for ranks in appReading.glyphs.flatMap({ [$0.generic, $0.personal] }) + anchored {
            XCTAssertEqual(ranks.count, 3)
            XCTAssertEqual(Set(ranks.map(\.label)).count, 3)
            XCTAssertTrue(ranks.allSatisfy { $0.score.isFinite && encoder.vocabulary.contains($0.label) })
        }
        XCTAssertEqual(learned.profile, profile)
        XCTAssertEqual(local.profile, profile)
        print("SYMBOL_SELECTION_PINNED_RUNTIME syntheticLessons=1 sharedUnchanged=true accuracyMeasured=false transferMeasured=false")
    }

    private func assertVector(_ actual: [Double], equals expected: [Double],
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a, b) in zip(actual, expected) { XCTAssertEqual(a, b, accuracy: 1e-12, file: file, line: line) }
    }

    private func resourceFiles(_ directory: URL) throws -> [String: Data] {
        let root = directory.standardizedFileURL
        let iterator = try XCTUnwrap(FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]))
        var files: [String: Data] = [:]
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true, url.path.hasPrefix(root.path + "/") else {
                throw PersonalInkLearnedComparison.Failure.invalidEncoder
            }
            if values.isRegularFile == true {
                guard (values.fileSize ?? Int.max) < 4_000_000 else {
                    throw PersonalInkLearnedComparison.Failure.invalidEncoder
                }
                files[String(url.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: url)
            }
        }
        return files
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
