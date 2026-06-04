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

private func normalizedPDFExtractedChordText(_ text: String) -> String {
    text
        .replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(of: "△", with: "")
}
#endif
