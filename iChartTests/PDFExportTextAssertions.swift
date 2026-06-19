#if canImport(PDFKit)
import XCTest

func XCTAssertPDFExtractedTextContains(
    _ documentText: String,
    visibleChordText expectedText: String,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if documentText.contains(expectedText) {
        return
    }

    let normalizedDocumentText = normalizedPDFExtractedChordText(documentText)
    let normalizedExpectedText = normalizedPDFExtractedChordText(expectedText)
    if normalizedDocumentText.contains(normalizedExpectedText) {
        return
    }

    let failureMessage = message()
    XCTFail(
        failureMessage.isEmpty
            ? "Expected PDF text to contain visible chord text \(expectedText). PDF text: \(documentText)"
            : failureMessage,
        file: file,
        line: line
    )
}

func XCTAssertPDFExtractedTextContains(
    _ documentText: String,
    visibleNotationText expectedText: String,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if documentText.contains(expectedText) {
        return
    }

    let normalizedDocumentText = normalizedPDFExtractedNotationText(documentText)
    let normalizedExpectedText = normalizedPDFExtractedNotationText(expectedText)
    if normalizedDocumentText.contains(normalizedExpectedText) {
        return
    }

    let failureMessage = message()
    XCTFail(
        failureMessage.isEmpty
            ? "Expected PDF text to contain visible notation text \(expectedText). PDF text: \(documentText)"
            : failureMessage,
        file: file,
        line: line
    )
}

private func normalizedPDFExtractedChordText(_ text: String) -> String {
    text
        .replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(of: "△", with: "")
}

private func normalizedPDFExtractedNotationText(_ text: String) -> String {
    text
        .lowercased()
        .replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(of: "\u{E047}", with: "")
        .replacingOccurrences(of: "\u{E048}", with: "")
}
#endif
