import XCTest

final class ChordRecognitionProviderBoundaryTests: XCTestCase {
    func testLiveChordRecognitionPathDoesNotUseOCRScribbleOrAppleStrokeRecognizer() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURLs = try chordRecognitionSourceURLs(sourceRoot: sourceRoot)
        let forbiddenTokens = [
            "VNRecognize",
            "Vision",
            "PKStrokeRecognizer",
            "OCR",
            "UIScribbleInteraction",
            "Scribble"
        ]

        var violations = [String]()
        for sourceURL in sourceURLs {
            var source = try String(contentsOf: sourceURL, encoding: .utf8)
            if sourceURL.lastPathComponent == "EditorView.swift" {
                // These two text-cue instructions describe native text entry.
                // Leave every other occurrence subject to the provider guard.
                source = source
                    .replacingOccurrences(of: #""Open Tools > Text, choose a measure, then Above or Below. Tap the field to type or use its Pencil icon for Scribble. Tap Add.""#, with: "")
                    .replacingOccurrences(of: #""Tap to type. Use Start Scribble to write with Apple Pencil.""#, with: "")
            }
            for forbiddenToken in forbiddenTokens where source.contains(forbiddenToken) {
                violations.append("\(sourceURL.path): \(forbiddenToken)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Live chord recognition path must stay deterministic and must not add OCR, Scribble, or PKStrokeRecognizer providers: \(violations)"
        )
    }

    private func chordRecognitionSourceURLs(sourceRoot: URL) throws -> [URL] {
        var urls = try swiftFiles(in: sourceRoot.appendingPathComponent("iChart/Recognition"))
        urls.append(contentsOf: [
            sourceRoot.appendingPathComponent("iChart/Features/Editor/Components/LeadSheetChordInkRecognitionTargeting.swift"),
            sourceRoot.appendingPathComponent("iChart/Features/Editor/Components/LeadSheetCanvasHostView.swift"),
            sourceRoot.appendingPathComponent("iChart/Features/Editor/Components/ChordInkDraftPreview.swift"),
            sourceRoot.appendingPathComponent("iChart/Features/Editor/EditorView.swift")
        ])
        return urls
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.pathExtension == "swift" else {
                return nil
            }

            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }
}
