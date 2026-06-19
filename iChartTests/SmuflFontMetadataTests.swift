import XCTest
@testable import iChart

final class SmuflFontMetadataTests: XCTestCase {
    func testDecodesBoundingBoxesAdvanceWidthsAndAnchors() throws {
        let fixture = """
        {
          "fontName": "Fixture Jazz",
          "fontVersion": "1.0",
          "engravingDefaults": {
            "staffLineThickness": 0.13,
            "stemThickness": 0.12,
            "beamThickness": 0.5,
            "thinBarlineThickness": 0.16,
            "thickBarlineThickness": 0.5,
            "barlineSeparation": 0.4,
            "tieEndpointThickness": 0.1,
            "tieMidpointThickness": 0.22
          },
          "glyphBBoxes": {
            "gClef": {
              "bBoxSW": [-0.1, -2.0],
              "bBoxNE": [2.5, 4.0]
            },
            "noteheadBlack": {
              "bBoxSW": [0.0, -0.5],
              "bBoxNE": [1.2, 0.5]
            }
          },
          "glyphAdvanceWidths": {
            "gClef": 2.75
          },
          "glyphsWithAnchors": {
            "noteheadBlack": {
              "stemUpSE": [1.2, 0.28],
              "stemDownNW": [0.0, -0.22]
            }
          }
        }
        """

        let metadata = try XCTUnwrap(SmuflFontMetadataStore.decodeMetadata(from: Data(fixture.utf8)))
        let clef = try XCTUnwrap(metadata.metrics(forGlyphNamed: "gClef"))
        let notehead = try XCTUnwrap(metadata.metrics(forGlyphNamed: "noteheadBlack"))
        let clefBoundingBox = try XCTUnwrap(clef.boundingBox)
        let stemUpAnchor = try XCTUnwrap(notehead.anchor(named: "stemUpSE"))
        let stemDownAnchor = try XCTUnwrap(notehead.anchor(named: "stemDownNW"))

        XCTAssertEqual(metadata.fontName, "Fixture Jazz")
        XCTAssertEqual(metadata.engravingDefaults?.staffLineThickness, 0.13)
        XCTAssertEqual(clefBoundingBox.width, 2.6, accuracy: 0.0001)
        XCTAssertEqual(clefBoundingBox.height, 6.0, accuracy: 0.0001)
        XCTAssertEqual(clef.advanceWidth, 2.75)
        XCTAssertEqual(stemUpAnchor.x, 1.2)
        XCTAssertEqual(stemDownAnchor.y, -0.22)
    }

    func testSemanticCatalogMapsSymbolsToOfficialSmuflGlyphNames() {
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .trebleClef), "gClef")
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .bassClef), "fClef")
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .slashNotehead), "noteheadSlashVerticalEnds")
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .slashWholeNotehead), "noteheadSlashWhiteWhole")
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .quarterRest), "restQuarter")
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .eighthRest), "rest8th")
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .accidentalFlat), "accidentalFlat")
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .accidentalSharp), "accidentalSharp")
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .coda), "coda")
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .segno), "segno")
        XCTAssertEqual(NotationGlyphCatalog.smuflGlyphName(for: .timeSignatureDigit(4)), "timeSig4")
        XCTAssertNil(NotationGlyphCatalog.smuflGlyphName(for: .timeSignatureDigit(12)))
    }

    func testLoadsFullBundledSmuflMetadataForEachNotationPreset() throws {
        let baseURL = smuflMetadataBaseURL

        for preset in NotationFontPreset.allCases {
            let metadata = try XCTUnwrap(
                SmuflFontMetadataStore.loadMetadata(for: preset, fromResourceBaseURL: baseURL),
                "Expected metadata for \(preset.displayText)"
            )
            let trebleClef = try XCTUnwrap(
                metadata.metrics(forGlyphNamed: "gClef"),
                "Expected gClef metrics for \(preset.displayText)"
            )

            XCTAssertEqual(metadata.fontName, preset.smuflMetadataDirectoryName)
            XCTAssertGreaterThan(trebleClef.boundingBox?.height ?? 0, 4.0)
            XCTAssertNotNil(metadata.metrics(forGlyphNamed: "coda"))
            XCTAssertNotNil(metadata.metrics(forGlyphNamed: "segno"))
            XCTAssertGreaterThan(metadata.glyphBoundingBoxes.count, 100)
        }
    }

    func testLoadedMetadataExposesPerFontAnchorsAndFallbackMissingAdvanceWidths() throws {
        let baseURL = smuflMetadataBaseURL
        let bravura = try XCTUnwrap(SmuflFontMetadataStore.loadMetadata(for: .bravura, fromResourceBaseURL: baseURL))
        let finaleJazz = try XCTUnwrap(SmuflFontMetadataStore.loadMetadata(for: .finaleJazz, fromResourceBaseURL: baseURL))
        let bravuraNotehead = try XCTUnwrap(bravura.metrics(forGlyphNamed: "noteheadBlack"))
        let finaleRest = try XCTUnwrap(finaleJazz.metrics(forGlyphNamed: "rest8th"))
        let stemUpAnchor = try XCTUnwrap(bravuraNotehead.anchor(named: "stemUpSE"))

        XCTAssertEqual(stemUpAnchor.x, 1.18, accuracy: 0.001)
        XCTAssertNotNil(bravura.metrics(forGlyphNamed: "gClef")?.advanceWidth)
        XCTAssertNil(finaleJazz.metrics(forGlyphNamed: "gClef")?.advanceWidth)
        XCTAssertGreaterThan(finaleRest.boundingBox?.height ?? 0, 1.0)
    }

    #if os(iOS)
    func testRuntimeBundleLoadsBundledSmuflMetadata() throws {
        let metadata = try XCTUnwrap(SmuflFontMetadataStore.metadata(for: .bravura))
        let clef = try XCTUnwrap(SmuflFontMetadataStore.metrics(for: .trebleClef, in: .bravura))

        XCTAssertEqual(metadata.fontName, "Bravura")
        XCTAssertGreaterThan(clef.boundingBox?.height ?? 0, 6.0)
    }
    #endif

    private var repositoryRootURL: URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        let startURLs = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            fileURL.deletingLastPathComponent()
        ]

        for startURL in startURLs {
            var candidate = startURL
            for _ in 0..<12 {
                let smuflDirectory = candidate
                    .appendingPathComponent("ThirdParty")
                    .appendingPathComponent("NotationFonts")
                    .appendingPathComponent("SMuFL")
                if FileManager.default.fileExists(atPath: smuflDirectory.path) {
                    return candidate
                }

                let parent = candidate.deletingLastPathComponent()
                guard parent.path != candidate.path else {
                    break
                }
                candidate = parent
            }
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private var smuflMetadataBaseURL: URL {
        repositoryRootURL
                .appendingPathComponent("ThirdParty")
                .appendingPathComponent("NotationFonts")
                .appendingPathComponent("SMuFL")
    }
}
