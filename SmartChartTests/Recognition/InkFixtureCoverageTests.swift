import XCTest
@testable import SmartChart

final class InkFixtureCoverageTests: XCTestCase {
    func testFixtureCorpusDoesNotContainExactDuplicateInkSamples() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        var seenFixturesByFingerprint: [InkFixture: String] = [:]

        for fixture in fixtures {
            let fingerprint = fixture.withoutName
            if let existingName = seenFixturesByFingerprint[fingerprint] {
                XCTFail("Exact duplicate fixture payload: \(existingName) and \(fixture.name)")
            } else {
                seenFixturesByFingerprint[fingerprint] = fixture.name
            }
        }
    }

    func testCapturedFixtureCoverageProtectsRootFoundation() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)
        let fixtureCounts = Dictionary(grouping: capturedFixtures, by: \.expectedDisplayText)
            .mapValues(\.count)

        for root in ["A", "B", "C", "D", "E", "F", "G"] {
            XCTAssertGreaterThanOrEqual(
                fixtureCounts[root, default: 0],
                4,
                "Expected at least four captured real-writing fixtures for \(root)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsCommonAccidentals() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)
        let fixtureCounts = Dictionary(grouping: capturedFixtures, by: \.expectedDisplayText)
            .mapValues(\.count)

        for accidentalChord in ["A#", "Ab", "Bb", "C#", "D#", "Db", "Eb", "F#", "G#", "Gb"] {
            XCTAssertGreaterThanOrEqual(
                fixtureCounts[accidentalChord, default: 0],
                3,
                "Expected at least three captured real-writing fixtures for \(accidentalChord)"
            )
        }
    }

    func testPlanSuccessCriteriaStayRepresentedByFixtures() throws {
        let displayTexts = Set(try InkFixtureLoader.loadAll(file: #filePath).map(\.expectedDisplayText))

        XCTAssertTrue(displayTexts.isSuperset(of: ["C", "Bb", "F#", "C-", "C-7", "Db7(b9)", "G/B"]))
    }

    func testCapturedFixtureCoverageProtectsFlatMinorForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "Bb-|Bb-": 3,
            "Bb-|Bbm": 3,
            "Bb-7|Bb-7": 3,
            "Bb-7|Bbm7": 3,
            "Cb-|Cb-": 3,
            "Cb-|Cbm": 3,
            "Cb-7|Cb-7": 3,
            "Cb-7|Cbm7": 3,
            "Gb-|Gb-": 3,
            "Gb-|Gbm": 3,
            "Gb-7|Gb-7": 3,
            "Gb-7|Gbm7": 3
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsSharpMinorForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "A#-|A#-": 3,
            "A#-|A#m": 3,
            "A#-7|A#-7": 3,
            "A#-7|A#m7": 3,
            "B#-|B#-": 3,
            "B#-|B#m": 3,
            "B#-7|B#-7": 3,
            "B#-7|B#m7": 3,
            "F#-|F#-": 3,
            "F#-|F#m": 3,
            "F#-7|F#-7": 3,
            "F#-7|F#m7": 3,
            "C#-|C#-": 3,
            "C#-|C#m": 3,
            "C#-7|C#-7": 3,
            "C#-7|C#m7": 3,
            "D#-|D#-": 3,
            "D#-|D#m": 3,
            "D#-7|D#-7": 3,
            "D#-7|D#m7": 3,
            "E#-|E#-": 3,
            "E#-|E#m": 3,
            "E#-7|E#-7": 3,
            "E#-7|E#m7": 3,
            "G#-|G#-": 3,
            "G#-|G#m": 4,
            "G#-7|G#-7": 3,
            "G#-7|G#m7": 4
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDFlatMinorForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "Db-|Db-": 3,
            "Db-|Dbm": 3,
            "Db-7|Db-7": 3,
            "Db-7|Dbm7": 3
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsEFlatMinorForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "Eb-|Eb-": 3,
            "Eb-|Ebm": 3,
            "Eb-7|Eb-7": 3,
            "Eb-7|Ebm7": 3
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsAFlatMinorForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "Ab-|Ab-": 3,
            "Ab-|Abm": 3,
            "Ab-7|Ab-7": 3,
            "Ab-7|Abm7": 3
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDominantSeventhForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C7|C7": 3,
            "Bb7|Bb7": 3,
            "F#7|F#7": 3,
            "Db7|Db7": 3,
            "G#7|G#7": 3,
            "B#7|B#7": 3
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDominantFlatNineForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C7(b9)|C7b9": 3,
            "Bb7(b9)|Bb7b9": 3,
            "F#7(b9)|F#7b9": 3,
            "Db7(b9)|Db7b9": 3,
            "G#7(b9)|G#7b9": 3,
            "B#7(b9)|B#7b9": 3
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDominantFlatFiveForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C7(b5)|C7b5": 1,
            "Bb7(b5)|Bb7b5": 1,
            "F#7(b5)|F#7b5": 1,
            "Db7(b5)|Db7b5": 1,
            "G#7(b5)|G#7b5": 2,
            "B#7(b5)|B#7b5": 1
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDominantSharpFiveForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C7(#5)|C7#5": 1,
            "Bb7(#5)|Bb7#5": 1,
            "F#7(#5)|F#7#5": 1,
            "Db7(#5)|Db7#5": 1,
            "G#7(#5)|G#7#5": 1,
            "B#7(#5)|B#7#5": 1
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDominantFlatThirteenForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C7(b13)|C7b13": 1,
            "Bb7(b13)|Bb7b13": 1,
            "F#7(b13)|F#7b13": 1,
            "Db7(b13)|Db7b13": 1,
            "G#7(b13)|G#7b13": 1,
            "B#7(b13)|B#7b13": 1
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDominantSharpElevenForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C7(#11)|C7#11": 1,
            "Bb7(#11)|Bb7#11": 1,
            "F#7(#11)|F#7#11": 1,
            "Db7(#11)|Db7#11": 1,
            "G#7(#11)|G#7#11": 1,
            "B#7(#11)|B#7#11": 1
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsSixthForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C6|C6": 3,
            "Bb6|Bb6": 3,
            "F#6|F#6": 3,
            "Db6|Db6": 3,
            "G#6|G#6": 3,
            "B#6|B#6": 3
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsAugmentedForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C+|C+": 2,
            "Bb+|Bb+": 2,
            "F#+|F#+": 2,
            "Db+|Db+": 2,
            "G#+|G#+": 2,
            "B#+|B#+": 2
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDiminishedForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C°|C°": 2,
            "Bb°|Bb°": 1,
            "F#°|F#°": 2,
            "Db°|Db°": 2,
            "G#°|G#°": 2,
            "B#°|B#°": 2,
            "C°7|C°7": 2,
            "Bb°7|Bb°7": 2,
            "F#°7|F#°7": 2,
            "Db°7|Db°7": 2,
            "G#°7|G#°7": 2,
            "B#°7|B#°7": 2,
            "Cø7|Cø7": 2,
            "Bbø7|Bbø7": 2,
            "F#ø7|F#ø7": 2,
            "Dbø7|Dbø7": 2,
            "G#ø7|G#ø7": 2,
            "B#ø7|B#ø7": 2
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsMajorSeventhTriangleForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C△7|C△7": 2,
            "Bb△7|Bb△7": 2,
            "F#△7|F#△7": 2,
            "Db△7|Db△7": 2,
            "G#△7|G#△7": 2,
            "B#△7|B#△7": 2
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testFixtureCoverageProtectsMinorMajorSeventhTriangleForms() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        let fixtureCounts = Dictionary(grouping: fixtures, by: \.expectedDisplayText)
            .mapValues(\.count)

        for minorMajorSeventhChord in ["C-△7", "Bb-△7", "F#-△7", "Db-△7", "G#-△7", "B#-△7"] {
            XCTAssertGreaterThanOrEqual(
                fixtureCounts[minorMajorSeventhChord, default: 0],
                1,
                "Expected at least one real-writing fixture for \(minorMajorSeventhChord)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsMajorNinthTriangleForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C△9|C△9": 1,
            "Bb△9|Bb△9": 1,
            "F#△9|F#△9": 1,
            "Db△9|Db△9": 1,
            "G#△9|G#△9": 1,
            "B#△9|B#△9": 1
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsMajorThirteenthTriangleForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C△13|C△13": 2,
            "Bb△13|Bb△13": 2,
            "F#△13|F#△13": 2,
            "Db△13|Db△13": 2,
            "G#△13|G#△13": 2,
            "B#△13|B#△13": 2
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsMinorNinthAndThirteenthForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C-9|C-9": 1,
            "Bb-9|Bb-9": 1,
            "F#-9|F#-9": 1,
            "Db-9|Db-9": 1,
            "G#-9|G#-9": 1,
            "B#-9|B#-9": 1,
            "C-13|C-13": 1,
            "Bb-13|Bb-13": 1,
            "F#-13|F#-13": 1,
            "Db-13|Db-13": 1,
            "G#-13|G#-13": 1,
            "B#-13|B#-13": 1
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testFixtureCoverageProtectsMinorSixthForms() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        let fixtureCounts = Dictionary(grouping: fixtures, by: \.expectedDisplayText)
            .mapValues(\.count)

        let minimums = [
            "Cm6": 2,
            "Bbm6": 2,
            "F#m6": 2,
            "Dbm6": 1,
            "G#m6": 2,
            "B#m6": 2
        ]

        for (minorSixthChord, minimumCount) in minimums {
            XCTAssertGreaterThanOrEqual(
                fixtureCounts[minorSixthChord, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) distinct real-writing fixtures for \(minorSixthChord)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsMinorEleventhForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C-11|C-11": 1,
            "Bb-11|Bb-11": 1,
            "F#-11|F#-11": 1,
            "Db-11|Db-11": 1,
            "G#-11|G#-11": 1,
            "B#-11|B#-11": 1
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDominantNinthForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C9|C9": 3,
            "Bb9|Bb9": 3,
            "F#9|F#9": 3,
            "Db9|Db9": 3,
            "G#9|G#9": 3,
            "B#9|B#9": 3
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDominantEleventhForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C11|C11": 3,
            "Bb11|Bb11": 3,
            "F#11|F#11": 3,
            "Db11|Db11": 3,
            "G#11|G#11": 3,
            "B#11|B#11": 3
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testCapturedFixtureCoverageProtectsDominantThirteenthForms() throws {
        let capturedFixtures = try InkFixtureLoader
            .loadAll(file: #filePath)
            .filter(\.isCapturedFixture)

        let glyphFamilies = Dictionary(grouping: capturedFixtures) { fixture in
            "\(fixture.expectedDisplayText)|\(fixture.expectedTopGlyphs.joined())"
        }.mapValues(\.count)

        let expectations = [
            "C13|C13": 3,
            "Bb13|Bb13": 3,
            "F#13|F#13": 3,
            "Db13|Db13": 3,
            "G#13|G#13": 3,
            "B#13|B#13": 3
        ]

        for (family, minimumCount) in expectations {
            XCTAssertGreaterThanOrEqual(
                glyphFamilies[family, default: 0],
                minimumCount,
                "Expected at least \(minimumCount) captured fixtures for \(family)"
            )
        }
    }

    func testFixtureCoverageProtectsSlashBassForms() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        let fixtureCounts = Dictionary(grouping: fixtures, by: \.expectedDisplayText)
            .mapValues(\.count)

        for slashBassChord in ["F/A", "C/E", "G/B", "D/F#", "Bb/D", "F#/A#"] {
            XCTAssertGreaterThanOrEqual(
                fixtureCounts[slashBassChord, default: 0],
                3,
                "Expected at least three real-writing fixtures for \(slashBassChord)"
            )
        }
    }

    func testFixtureCoverageProtectsPlainSuspendedForms() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        let fixtureCounts = Dictionary(grouping: fixtures, by: \.expectedDisplayText)
            .mapValues(\.count)

        for suspendedChord in ["Csus", "Gsus", "Bbsus", "F#sus"] {
            XCTAssertGreaterThanOrEqual(
                fixtureCounts[suspendedChord, default: 0],
                2,
                "Expected at least two real-writing fixtures for \(suspendedChord)"
            )
        }
    }

    func testFixtureCoverageProtectsSuspendedFourthForms() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        let fixtureCounts = Dictionary(grouping: fixtures, by: \.expectedDisplayText)
            .mapValues(\.count)

        for suspendedFourthChord in ["Csus4", "Gsus4", "Bbsus4", "F#sus4"] {
            XCTAssertGreaterThanOrEqual(
                fixtureCounts[suspendedFourthChord, default: 0],
                2,
                "Expected at least two real-writing fixtures for \(suspendedFourthChord)"
            )
        }
    }

    func testFixtureCoverageProtectsDominantSuspendedForms() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        let fixtureCounts = Dictionary(grouping: fixtures, by: \.expectedDisplayText)
            .mapValues(\.count)

        for dominantSuspendedChord in ["C7sus", "Bb7sus", "F#7sus", "Db7sus", "G#7sus", "B#7sus"] {
            XCTAssertGreaterThanOrEqual(
                fixtureCounts[dominantSuspendedChord, default: 0],
                2,
                "Expected at least two real-writing fixtures for \(dominantSuspendedChord)"
            )
        }
    }

    func testFixtureCoverageProtectsDominantAlteredForms() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        let fixtureCounts = Dictionary(grouping: fixtures, by: \.expectedDisplayText)
            .mapValues(\.count)

        for dominantAlteredChord in ["C7alt", "Bb7alt", "F#7alt", "Db7alt", "G#7alt", "B#7alt"] {
            XCTAssertGreaterThanOrEqual(
                fixtureCounts[dominantAlteredChord, default: 0],
                2,
                "Expected at least two real-writing fixtures for \(dominantAlteredChord)"
            )
        }
    }
}

private extension InkFixture {
    var isCapturedFixture: Bool {
        name.localizedCaseInsensitiveContains("captured")
    }

    var withoutName: InkFixture {
        var fixture = self
        fixture.name = ""
        return fixture
    }
}
