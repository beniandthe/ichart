import XCTest
@testable import iChart

/// Storage and identity checks only. The arbitrary supported labels exercise
/// lesson persistence; none of these fixtures is recognition-quality evidence.
final class PersonalInkLessonInputIntegrityTests: XCTestCase {
    func testExactRecognitionInputRetainsAllPointsTimingAndBoundsAcrossJSONAndStore() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("profile.json")
        let input = exactDenseInput()
        let canonical = try ChordInkCanonicalTrajectoryPacket(strokes: input).canonicalData()

        var profile = PersonalInkProfile()
        profile.isEnabled = true
        XCTAssertTrue(try profile.learn(strokes: input, label: "C", kind: .chord, source: .setup))
        let lesson = try XCTUnwrap(profile.examples.first)
        XCTAssertEqual(lesson.recognitionStrokes, input)
        XCTAssertEqual(lesson.recognitionInput, input)
        XCTAssertLessThan(lesson.strokes[0].points.count, input[0].points.count)
        XCTAssertEqual(try ChordInkCanonicalTrajectoryPacket(strokes: lesson.recognitionInput).canonicalData(), canonical)

        let decoded = try JSONDecoder().decode(
            PersonalInkProfile.self,
            from: JSONEncoder().encode(profile)
        )
        let decodedLesson = try XCTUnwrap(decoded.examples.first)
        XCTAssertEqual(decodedLesson.recognitionStrokes, input)
        XCTAssertEqual(try ChordInkCanonicalTrajectoryPacket(strokes: decodedLesson.recognitionInput).canonicalData(), canonical)

        let store = PersonalInkProfileStore(url: url)
        try store.update { $0 = decoded }
        let saved = try XCTUnwrap(store.snapshot().profile.examples.first)
        XCTAssertEqual(saved.recognitionStrokes, input)
        XCTAssertEqual(try ChordInkCanonicalTrajectoryPacket(strokes: saved.recognitionInput).canonicalData(), canonical)

        let reloaded = try XCTUnwrap(PersonalInkProfileStore(url: url).snapshot().profile.examples.first)
        XCTAssertEqual(reloaded.recognitionStrokes, input)
        XCTAssertEqual(try ChordInkCanonicalTrajectoryPacket(strokes: reloaded.recognitionInput).canonicalData(), canonical)
    }

    func testDensePreviewCollisionDoesNotDeduplicateOrDeleteDifferentFullInk() throws {
        let first = densePreviewCollisionInput(droppedPointY: 0.25)
        let second = densePreviewCollisionInput(droppedPointY: 4.75)
        let firstShape = try XCTUnwrap(PersonalInkShape(strokes: first))
        let secondShape = try XCTUnwrap(PersonalInkShape(strokes: second))
        XCTAssertEqual(firstShape.normalizedStrokes, secondShape.normalizedStrokes,
                       "The fixture must collide under the bounded preview")
        XCTAssertNotEqual(firstShape.normalizedRecognitionStrokes, secondShape.normalizedRecognitionStrokes)

        var profile = PersonalInkProfile()
        XCTAssertTrue(try profile.learn(strokes: first, label: "C", kind: .chord, source: .setup))
        let firstID = try XCTUnwrap(profile.examples.first?.id)
        XCTAssertTrue(try profile.learn(strokes: second, label: "C", kind: .chord, source: .confirmedReview))
        let secondID = try XCTUnwrap(profile.examples.last?.id)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(profile.examples.count, 2)

        XCTAssertTrue(try profile.learn(strokes: second, label: "D", kind: .chord, source: .explicitCorrection))
        XCTAssertEqual(profile.examples.count, 2)
        XCTAssertEqual(profile.examples.first(where: { $0.id == firstID })?.label, "C")
        XCTAssertNil(profile.examples.first(where: { $0.id == secondID }))
        XCTAssertEqual(profile.examples.first(where: { $0.label == "D" })?.recognitionStrokes, second)
    }

    func testTranslatedAndScaledFullInputIsOneIdentityWithoutReplacingSavedSource() throws {
        let input = exactDenseInput()
        let equivalent = transformed(input, scale: 2, dx: 256, dy: -128)
        var profile = PersonalInkProfile()
        XCTAssertTrue(try profile.learn(strokes: input, label: "C", kind: .chord, source: .setup))
        let original = try XCTUnwrap(profile.examples.first)
        let revision = profile.revision

        XCTAssertTrue(profile.containsExactLesson(strokes: equivalent, label: "C", kind: .chord))
        XCTAssertFalse(try profile.learn(strokes: equivalent, label: "C", kind: .chord, source: .confirmedReview))
        XCTAssertEqual(profile.examples, [original])
        XCTAssertEqual(profile.examples.first?.recognitionStrokes, input,
                       "A duplicate must not replace the acquisition retained by the lesson")
        XCTAssertEqual(profile.revision, revision)
    }

    func testSparseLegacyDuplicateStaysLegacyWithoutBackfill() throws {
        let input = sparseInput()
        let normalized = try XCTUnwrap(PersonalInkShape(strokes: input)).normalizedStrokes
        let legacyID = UUID()
        let legacy = PersonalInkExample(
            id: legacyID,
            kind: .chord,
            label: "C",
            strokes: normalized,
            source: .setup
        )
        var profile = PersonalInkProfile()
        profile.examples = [legacy]
        let oldBytes = try JSONEncoder().encode(profile)
        XCTAssertFalse(String(decoding: oldBytes, as: UTF8.self).contains("recognitionStrokes"))
        profile = try JSONDecoder().decode(PersonalInkProfile.self, from: oldBytes)

        XCTAssertFalse(try profile.learn(
            strokes: transformed(input, scale: 2, dx: 40, dy: -20),
            label: "C",
            kind: .chord,
            source: .confirmedReview
        ))
        XCTAssertEqual(profile.examples.count, 1)
        XCTAssertEqual(profile.examples.first?.id, legacyID)
        XCTAssertNil(profile.examples.first?.recognitionStrokes,
                     "A duplicate review is not evidence that recovers discarded legacy points")
    }

    func testDenseLegacyPreviewIsPreservedWhenExactLessonAndCorrectionAreAdded() throws {
        let input = densePreviewCollisionInput(droppedPointY: 3.25)
        let preview = try XCTUnwrap(PersonalInkShape(strokes: input)).normalizedStrokes
        let legacyID = UUID()
        var profile = PersonalInkProfile()
        profile.examples = [PersonalInkExample(
            id: legacyID,
            kind: .chord,
            label: "C",
            strokes: preview,
            source: .setup
        )]

        XCTAssertTrue(try profile.learn(strokes: input, label: "C", kind: .chord, source: .confirmedReview))
        XCTAssertEqual(profile.examples.count, 2)
        XCTAssertNil(profile.examples.first(where: { $0.id == legacyID })?.recognitionStrokes)
        XCTAssertEqual(profile.examples.first(where: { $0.id != legacyID })?.recognitionStrokes, input)

        XCTAssertTrue(try profile.learn(strokes: input, label: "D", kind: .chord, source: .explicitCorrection))
        XCTAssertEqual(profile.examples.count, 2)
        XCTAssertEqual(profile.examples.first(where: { $0.id == legacyID })?.label, "C")
        XCTAssertNil(profile.examples.first(where: { $0.id == legacyID })?.recognitionStrokes)
        XCTAssertEqual(profile.examples.first(where: { $0.label == "D" })?.recognitionStrokes, input)
    }

    func testMalformedNewRawInputsAndMismatchedThumbnailAreRejectedWithoutMutation() throws {
        let valid = sparseInput()
        let malformed: [[InkStroke]] = [
            [InkStroke(points: [])],
            [InkStroke(points: [
                InkPoint(x: 0, y: 0, timeOffset: .nan),
                InkPoint(x: 20, y: 20, timeOffset: 0.2)
            ])],
            [InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 20, y: 20)],
                       creationTimeOffset: .infinity)],
            [InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 20, y: 20)],
                       bounds: InkBounds(minX: 20, minY: 0, maxX: 0, maxY: 20))],
            [InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 20, y: 20)],
                       bounds: InkBounds(minX: 0, minY: 0, maxX: .infinity, maxY: 20))]
        ]
        for input in malformed {
            XCTAssertFalse(PersonalInkExample.canStoreRecognitionInput(input))
            var profile = PersonalInkProfile()
            assertInvalidInk(try profile.learn(
                strokes: input,
                label: "C",
                kind: .chord,
                source: .setup
            ))
            XCTAssertTrue(profile.examples.isEmpty)
        }

        let wrongPreview = try XCTUnwrap(PersonalInkShape(strokes: horizontalInput())).normalizedStrokes
        let mismatch = PersonalInkExample(
            kind: .chord,
            label: "C",
            strokes: wrongPreview,
            source: .setup,
            recognitionStrokes: valid
        )
        XCTAssertFalse(mismatch.hasValidRecognitionInput)

        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: url)
        try store.update { profile in
            _ = try profile.learn(strokes: valid, label: "C", kind: .chord, source: .setup)
        }
        let before = store.snapshot().profile
        let bytes = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.update { $0.examples.append(mismatch) }) { error in
            guard let personalError = error as? PersonalInkError,
                  case .incompatibleProfile = personalError else {
                return XCTFail("Expected incompatibleProfile, got \(error)")
            }
        }
        XCTAssertEqual(store.snapshot().profile, before)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testRecognitionInputComplexityLimitsAreInclusiveAndNeverTruncate() throws {
        let maximumStrokeInput = (0..<64).map { strokeIndex in
            InkStroke(points: [
                InkPoint(x: Double(strokeIndex) * 3, y: 0),
                InkPoint(x: Double(strokeIndex) * 3 + 1, y: 4)
            ])
        }
        XCTAssertTrue(PersonalInkExample.canStoreRecognitionInput(maximumStrokeInput))
        XCTAssertFalse(PersonalInkExample.canStoreRecognitionInput(
            maximumStrokeInput + [InkStroke(points: [InkPoint(x: 200, y: 0), InkPoint(x: 201, y: 4)])]
        ))

        let maximumPoints = [InkStroke(points: (0..<32_768).map { index in
            InkPoint(x: Double(index % 512), y: Double(index / 512), timeOffset: Double(index) / 240)
        })]
        XCTAssertTrue(PersonalInkExample.canStoreRecognitionInput(maximumPoints))
        var tooManyPoints = maximumPoints
        tooManyPoints[0].points.append(InkPoint(x: 512, y: 64, timeOffset: 140))
        tooManyPoints[0].bounds = InkBounds.enclosing(tooManyPoints[0].points)
        XCTAssertFalse(PersonalInkExample.canStoreRecognitionInput(tooManyPoints))

        var profile = PersonalInkProfile()
        XCTAssertTrue(try profile.learn(strokes: maximumPoints, label: "C", kind: .chord, source: .setup))
        XCTAssertEqual(profile.examples.first?.recognitionStrokes?.first?.points.count, 32_768)
    }

    func testV2ProvenanceCannotDowngradeToMissingRawWhileValidLegacyV1StillLoads() throws {
        let input = sparseInput()
        let context = PersonalInkCaptureContext(
            sessionID: UUID(),
            capturedAt: Date(timeIntervalSinceReferenceDate: 123_456),
            origin: .setup
        )
        var current = PersonalInkProfile()
        XCTAssertTrue(try current.learn(
            strokes: input,
            label: "C",
            kind: .chord,
            source: .setup,
            captureContext: context
        ))
        XCTAssertEqual(current.examples.first?.learningProvenance?.version,
                       PersonalInkLearningProvenance.currentVersion)

        let encoded = try JSONEncoder().encode(current)
        let decodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        for replacement in [nil, NSNull()] as [Any?] {
            var object = decodedObject
            var examples = try XCTUnwrap(object["examples"] as? [[String: Any]])
            if let replacement {
                examples[0]["recognitionStrokes"] = replacement
            } else {
                examples[0].removeValue(forKey: "recognitionStrokes")
            }
            object["examples"] = examples
            let damaged = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let folder = temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("profile.json")
            try damaged.write(to: url)

            let store = PersonalInkProfileStore(url: url)
            XCTAssertNotNil(store.loadError)
            XCTAssertFalse(store.snapshot().profile.isEnabled)
            XCTAssertTrue(store.snapshot().profile.examples.isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), damaged,
                           "Rejecting a damaged profile must not rewrite its evidence")
        }

        let preview = try XCTUnwrap(PersonalInkShape(strokes: input)).normalizedStrokes
        let legacyProvenance = try PersonalInkLearningProvenance.make(
            context: context,
            originalInput: input,
            storedInput: preview
        )
        var legacy = PersonalInkProfile()
        legacy.isEnabled = true
        legacy.examples = [PersonalInkExample(
            kind: .chord,
            label: "C",
            strokes: preview,
            source: .setup,
            learningProvenance: legacyProvenance
        )]
        let legacyFolder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: legacyFolder) }
        try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        let legacyURL = legacyFolder.appendingPathComponent("profile.json")
        try JSONEncoder().encode(legacy).write(to: legacyURL)
        let loadedLegacy = PersonalInkProfileStore(url: legacyURL)
        XCTAssertNil(loadedLegacy.loadError)
        XCTAssertTrue(loadedLegacy.snapshot().profile.isEnabled)
        XCTAssertEqual(loadedLegacy.snapshot().profile.examples.count, 1)
        XCTAssertNil(loadedLegacy.snapshot().profile.examples.first?.recognitionStrokes)
        XCTAssertEqual(loadedLegacy.snapshot().profile.examples.first?.learningProvenance?.version,
                       PersonalInkLearningProvenance.legacyVersion)
    }

    func testOversizedProfileSavePreservesCurrentSnapshotAndFileBytes() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: url)
        try store.update { profile in
            profile.isEnabled = true
            _ = try profile.learn(strokes: sparseInput(), label: "C", kind: .chord, source: .setup)
        }
        let before = store.snapshot().profile
        let savedBytes = try Data(contentsOf: url)

        var oversized = before
        let largeInput = largeValidInput()
        let bounded = try XCTUnwrap(PersonalInkShape(strokes: largeInput)).normalizedStrokes
        for label in ["A", "B", "D", "E", "F", "G", "A7", "B7"] {
            oversized.examples.append(PersonalInkExample(
                kind: .chord,
                label: label,
                strokes: bounded,
                source: .setup,
                recognitionStrokes: largeInput
            ))
            if try JSONEncoder().encode(oversized).count > PersonalInkProfileStore.maximumStoredBytes {
                break
            }
        }
        XCTAssertGreaterThan(
            try JSONEncoder().encode(oversized).count,
            PersonalInkProfileStore.maximumStoredBytes,
            "The fixture must cross the same bound enforced by the store"
        )

        XCTAssertThrowsError(try store.update { $0 = oversized }) { error in
            guard let personalError = error as? PersonalInkError,
                  case .profileSizeLimit = personalError else {
                return XCTFail("Expected profileSizeLimit, got \(error)")
            }
        }
        XCTAssertEqual(store.snapshot().profile, before)
        XCTAssertEqual(try Data(contentsOf: url), savedBytes)
        XCTAssertEqual(PersonalInkProfileStore(url: url).snapshot().profile, before)
    }

    private func exactDenseInput() -> [InkStroke] {
        let dense = (0..<257).map { (index: Int) -> InkPoint in
            let x: Double = index == 0 ? -0.0 : 10.125 + Double(index) * 0.375
            let y: Double = index == 1 ? 47.625 : -12.875 + Double(index % 11) * 1.0625
            let timeOffset: Double = index == 0 ? -0.0 : -0.25 + Double(index) * 0.0078125
            return InkPoint(x: x, y: y, timeOffset: timeOffset)
        }
        return [
            InkStroke(
                points: dense,
                bounds: InkBounds(minX: -4.125, minY: -20.5, maxX: 112.75, maxY: 52.25),
                creationTimeOffset: -1.5
            ),
            InkStroke(
                points: [
                    InkPoint(x: 120.25, y: -8.5, timeOffset: 0.125),
                    InkPoint(x: 123.75, y: 16.25, timeOffset: 0.375),
                    InkPoint(x: 128.5, y: 9.125, timeOffset: nil)
                ],
                bounds: InkBounds(minX: 119.75, minY: -9, maxX: 129, maxY: 16.75),
                creationTimeOffset: 3.25
            )
        ]
    }

    private func densePreviewCollisionInput(droppedPointY: Double) -> [InkStroke] {
        let bounds = InkBounds(minX: 0, minY: -10, maxX: 128, maxY: 10)
        let points = (0..<129).map { index -> InkPoint in
            let y: Double
            switch index {
            case 0: y = -10
            case 1: y = droppedPointY
            case 128: y = 10
            default: y = 0
            }
            return InkPoint(x: Double(index), y: y, timeOffset: Double(index) / 120)
        }
        return [InkStroke(points: points, bounds: bounds, creationTimeOffset: 0.5)]
    }

    private func sparseInput() -> [InkStroke] {
        [
            InkStroke(points: [
                InkPoint(x: 0, y: 24, timeOffset: -0.1),
                InkPoint(x: 10, y: 0, timeOffset: 0),
                InkPoint(x: 20, y: 24, timeOffset: 0.2)
            ], creationTimeOffset: -0.5),
            InkStroke(points: [
                InkPoint(x: 4, y: 15, timeOffset: nil),
                InkPoint(x: 16, y: 15, timeOffset: 0.1)
            ], creationTimeOffset: 1)
        ]
    }

    private func horizontalInput() -> [InkStroke] {
        [InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 40, y: 0)])]
    }

    private func transformed(_ strokes: [InkStroke], scale: Double, dx: Double, dy: Double) -> [InkStroke] {
        strokes.map { stroke in
            InkStroke(
                points: stroke.points.map {
                    InkPoint(x: $0.x * scale + dx, y: $0.y * scale + dy, timeOffset: $0.timeOffset)
                },
                bounds: InkBounds(
                    minX: stroke.bounds.minX * scale + dx,
                    minY: stroke.bounds.minY * scale + dy,
                    maxX: stroke.bounds.maxX * scale + dx,
                    maxY: stroke.bounds.maxY * scale + dy
                ),
                creationTimeOffset: stroke.creationTimeOffset
            )
        }
    }

    private func largeValidInput() -> [InkStroke] {
        [InkStroke(points: (0..<32_768).map { index in
            InkPoint(
                x: 12_345_678.1234567 + Double(index % 512) * 0.001953125,
                y: -23_456_789.2345678 + Double(index / 512) * 0.001953125,
                timeOffset: -123_456.7890123 + Double(index) * 0.000244140625
            )
        }, creationTimeOffset: -9_876.5432109)]
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalInkLessonInputIntegrity-\(UUID().uuidString)")
    }

    private func assertInvalidInk<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard let personalError = error as? PersonalInkError,
                  case .invalidInk = personalError else {
                return XCTFail("Expected invalidInk, got \(error)", file: file, line: line)
            }
        }
    }
}
