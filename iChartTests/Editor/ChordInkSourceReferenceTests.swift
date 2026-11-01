#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkSourceReferenceTests: XCTestCase {
    func testLocationUsesCurrentRowAndDoesNotInventMaterializedMeasureForDraftLane() {
        let location = ChordInkReviewSourceLocation(measureNumber: 1, rowNumber: 3,
            fraction: 0.8, includesMeasureNumber: false)
        XCTAssertEqual(location.label, "Row 3")
        XCTAssertEqual(location.positionLabel, "Right side")
        XCTAssertEqual(ChordInkReviewSourceLocation(measureNumber: 4).label, "Measure 4")
        XCTAssertEqual(ChordInkReviewSourceLocation(measureNumber: 4, rowNumber: 2).label,
            "Row 2 · Measure 4")
        XCTAssertNil(ChordInkReviewSourceLocation(measureNumber: 4, fraction: .nan).positionLabel)
    }

    func testSourceThumbnailCropsOffsetInkAndRetainsRaisedAndSlashPartsWithoutChangingArchive() throws {
        let drawing = PKDrawing(strokes: [
            stroke([CGPoint(x: 420, y: 640), CGPoint(x: 420, y: 680), CGPoint(x: 445, y: 680)], seed: 1),
            stroke([CGPoint(x: 460, y: 610), CGPoint(x: 475, y: 610), CGPoint(x: 465, y: 630)], seed: 2),
            stroke([CGPoint(x: 490, y: 690), CGPoint(x: 510, y: 640)], seed: 3),
            stroke([CGPoint(x: 520, y: 650), CGPoint(x: 535, y: 650), CGPoint(x: 535, y: 680)], seed: 4)
        ])
        let archive = drawing.dataRepresentation()
        let frozen = archive
        let image = try XCTUnwrap(ChordInkSourcePreviewRenderer.image(for: archive))
        XCTAssertEqual(archive, frozen)
        XCTAssertEqual(try PKDrawing(data: archive).strokes.count, 4)
        XCTAssertLessThanOrEqual(max(image.size.width * image.scale, image.size.height * image.scale), 282)

        let bitmap = try XCTUnwrap(image.cgImage)
        var rgba = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: CGFloat(bitmap.width), height: CGFloat(bitmap.height)))
        }
        let visiblePixels = (0..<bitmap.height).flatMap { y in
            (0..<bitmap.width).compactMap { x -> CGPoint? in
                rgba[(y * bitmap.width + x) * 4 + 3] > 20 ? CGPoint(x: CGFloat(x), y: CGFloat(y)) : nil
            }
        }
        XCTAssertTrue(visiblePixels.contains { $0.x < CGFloat(bitmap.width) / 4 }, "The root must remain visible")
        XCTAssertTrue(visiblePixels.contains { $0.x > CGFloat(bitmap.width) * 3 / 4 }, "The slash bass must remain visible")
        XCTAssertTrue(visiblePixels.contains { $0.y < CGFloat(bitmap.height) / 4 })
        XCTAssertTrue(visiblePixels.contains { $0.y > CGFloat(bitmap.height) * 3 / 4 },
            "Cropping must include the full raised and lowered source extent")
    }

    func testMissingOrInvalidSourceDoesNotProduceInventedHandwriting() {
        XCTAssertNil(ChordInkSourcePreviewRenderer.image(for: nil))
        XCTAssertNil(ChordInkSourcePreviewRenderer.image(for: Data([1, 2, 3])))
        XCTAssertNil(ChordInkSourcePreviewRenderer.image(for: PKDrawing().dataRepresentation()))
    }

    func testRenderedCorrectionKeepsExactEventAndSourceReference() {
        let eventID = UUID(), measureID = UUID()
        let source = Data([7, 8, 9])
        let correction = PendingChordCorrection(chordEventID: eventID, measureID: measureID,
            measureIndex: 3, currentText: "G7", rawInput: "G7", candidateTexts: ["G7", "G"],
            enharmonicChoiceTexts: [], sourceInkData: source, sourceRowNumber: 2, sourcePositionFraction: 0.2)
        XCTAssertEqual(correction.chordEventID, eventID)
        XCTAssertEqual(correction.measureID, measureID)
        XCTAssertEqual(correction.sourceInkData, source)
        XCTAssertEqual(correction.sourceLocation.label, "Row 2 · Measure 4")
        XCTAssertEqual(correction.sourceLocation.positionLabel, "Left side")
    }

    func testNativeReviewAndCorrectionExposeTheirSourceInWholeSheetAttachments() async throws {
        let source = PKDrawing(strokes: [
            stroke([CGPoint(x: 420, y: 680), CGPoint(x: 420, y: 630), CGPoint(x: 455, y: 630)], seed: 8),
            stroke([CGPoint(x: 420, y: 652), CGPoint(x: 446, y: 652)], seed: 9)
        ]).dataRepresentation()
        let result = ChordInkRecognitionResult(rawCandidates: ["F", "E"], glyphCandidates: [],
            match: ChordRecognitionCompendium.match("F"), confidence: 1)
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let confirmation = PendingChordInkConfirmation(measureID: UUID(), measureIndex: 0,
            result: result, drawingData: source, targetFraction: 0.2,
            primaryDecision: decision, decision: decision, sourceRowNumber: 1, sourcePositionFraction: 0.2)
        let correction = PendingChordCorrection(chordEventID: UUID(), measureID: confirmation.measureID,
            measureIndex: 0, currentText: "F", rawInput: "F", candidateTexts: ["F", "E"],
            enharmonicChoiceTexts: [], sourceInkData: source, sourceRowNumber: 1, sourcePositionFraction: 0.2)
        var accepted = false
        let views: [(String, AnyView)] = [
            ("Manual review - exact handwriting and row reference", AnyView(
                ChordInkBatchConfirmationSheetView(batch: .init(confirmations: [confirmation]),
                    onAcceptAll: { _ in accepted = true }, onClearAndRewrite: {}, onBackToInk: {},
                    onRewriteChord: { _ in }))),
            ("Rendered chord edit - original source and current location", AnyView(
                ChordCorrectionSheetView(correction: correction,
                    onAcceptCandidate: { _, _ in accepted = true }, onCancel: {})))
        ]
        for (name, content) in views {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
            let previousWindow = scene.windows.first(where: \.isKeyWindow)
            let host = UIHostingController(rootView: content.preferredColorScheme(.light))
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousWindow?.makeKey()
            }
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
            host.view.layoutIfNeeded()
            XCTAssertTrue(host.view.window === window)
            XCTAssertEqual(window.bounds.size, scene.coordinateSpace.bounds.size)
            var didDraw = false
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            XCTAssertTrue(didDraw, "The attached scene must produce an actual native hierarchy raster")
            try assertContainsVisibleContent(image)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let geometry = XCTAttachment(string: "Attached active scene; orientation=\(scene.effectiveGeometry.interfaceOrientation.rawValue), scene=\(scene.coordinateSpace.bounds), window=\(window.bounds), key=\(window.isKeyWindow), drawHierarchy=\(didDraw)")
            geometry.name = name + " - actual scene geometry"
            geometry.lifetime = .keepAlways
            add(geometry)
        }
        XCTAssertFalse(accepted, "Displaying the exact source must not accept a label or alter the music")
        XCTAssertEqual(correction.sourceInkData, source)
        XCTAssertEqual(confirmation.drawingData, source)
    }

    private func assertContainsVisibleContent(_ image: UIImage) throws {
        let bitmap = try XCTUnwrap(image.cgImage)
        var rgba = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: CGFloat(bitmap.width), height: CGFloat(bitmap.height)))
        }
        var lightPixels = 0, darkPixels = 0, sampledPixels = 0
        for y in stride(from: 0, to: bitmap.height, by: 4) {
            for x in stride(from: 0, to: bitmap.width, by: 4) {
                let offset = (y * bitmap.width + x) * 4
                let brightness = (Int(rgba[offset]) + Int(rgba[offset + 1]) + Int(rgba[offset + 2])) / 3
                sampledPixels += 1
                if brightness > 220 { lightPixels += 1 }
                if brightness < 96 { darkPixels += 1 }
            }
        }
        XCTAssertGreaterThan(lightPixels, sampledPixels / 10,
            "An all-black or unattached-window image is not visual evidence")
        XCTAssertGreaterThan(darkPixels, sampledPixels / 1_000,
            "A blank light surface must not pass without visible handwriting or interface text")
    }

    private func stroke(_ points: [CGPoint], seed: UInt32) -> PKStroke {
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: controls, creationDate: Date(timeIntervalSinceReferenceDate: 100)),
            transform: .identity, mask: nil, randomSeed: seed)
    }
}
#endif
