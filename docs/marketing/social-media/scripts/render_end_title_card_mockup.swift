import AppKit
import CoreGraphics
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let logoURL = repoRoot.appendingPathComponent("docs/branding/ichart/exports/ichart-b48a-h1-canon-logo.png")
let outputDir = repoRoot.appendingPathComponent("docs/marketing/social-media/title-card-mockups")

let brandStage = NSColor(calibratedRed: 15.0 / 255.0, green: 21.0 / 255.0, blue: 27.0 / 255.0, alpha: 1)
let logoBlue = NSColor(calibratedRed: 143.0 / 255.0, green: 211.0 / 255.0, blue: 230.0 / 255.0, alpha: 1)
let paper = NSColor(calibratedRed: 247.0 / 255.0, green: 243.0 / 255.0, blue: 234.0 / 255.0, alpha: 1)

struct TitleCardLayout {
    let size: CGSize
    let outputName: String
    let logoRect: CGRect
    let accentRect: CGRect
    let handleRect: CGRect
    let socialRect: CGRect
    let websiteRect: CGRect
    let appStoreRect: CGRect
    let handleSize: CGFloat
    let socialSize: CGFloat
    let websiteSize: CGFloat
    let appStoreSize: CGFloat
}

func cgImage(from imageURL: URL) -> CGImage {
    guard let image = NSImage(contentsOf: imageURL) else {
        fatalError("Could not load image at \(imageURL.path)")
    }
    var proposed = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
        fatalError("Could not create CGImage for \(imageURL.path)")
    }
    return cgImage
}

func keyedLogoImage(from source: CGImage) -> CGImage {
    let width = source.width
    let height = source.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Could not create logo keying context")
    }
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    let bgR = Int(pixels[0])
    let bgG = Int(pixels[1])
    let bgB = Int(pixels[2])

    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Int(pixels[index])
        let g = Int(pixels[index + 1])
        let b = Int(pixels[index + 2])
        let distance = max(abs(r - bgR), abs(g - bgG), abs(b - bgB))

        let alpha: Int
        if distance <= 12 {
            alpha = 0
        } else if distance >= 46 {
            alpha = 255
        } else {
            alpha = Int(round(Double(distance - 12) / 34.0 * 255.0))
        }

        pixels[index] = UInt8((r * alpha) / 255)
        pixels[index + 1] = UInt8((g * alpha) / 255)
        pixels[index + 2] = UInt8((b * alpha) / 255)
        pixels[index + 3] = UInt8(alpha)
    }

    guard
        let provider = CGDataProvider(data: Data(pixels) as CFData),
        let keyed = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    else {
        fatalError("Could not create keyed logo image")
    }
    return keyed
}

func drawCenteredText(
    _ text: String,
    in rect: CGRect,
    fontSize: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    lineSpacing: CGFloat = 4
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = lineSpacing

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let measured = attributed.boundingRect(
        with: CGSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let drawRect = CGRect(
        x: rect.minX,
        y: rect.minY + max(0, (rect.height - measured.height) / 2),
        width: rect.width,
        height: min(rect.height, ceil(measured.height) + 4)
    )
    attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

func bottomRect(fromTopLeft rect: CGRect, canvasHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: canvasHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
}

func drawTopLeftCGImage(_ image: CGImage, in rect: CGRect, canvasHeight: CGFloat) {
    let nsImage = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    nsImage.draw(
        in: bottomRect(fromTopLeft: rect, canvasHeight: canvasHeight),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
}

func render(_ layout: TitleCardLayout, logo: CGImage) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(layout.size.width),
        pixelsHigh: Int(layout.size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap for \(layout.outputName)")
    }
    guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create graphics context for \(layout.outputName)")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    graphics.shouldAntialias = true
    defer { NSGraphicsContext.restoreGraphicsState() }

    brandStage.setFill()
    CGRect(origin: .zero, size: layout.size).fill()

    let hairlineColor = logoBlue.withAlphaComponent(0.16)
    hairlineColor.setFill()
    if layout.size.height > layout.size.width {
        bottomRect(fromTopLeft: CGRect(x: 92, y: 230, width: layout.size.width - 184, height: 1), canvasHeight: layout.size.height).fill()
        bottomRect(fromTopLeft: CGRect(x: 92, y: layout.size.height - 270, width: layout.size.width - 184, height: 1), canvasHeight: layout.size.height).fill()
    } else {
        bottomRect(fromTopLeft: CGRect(x: 190, y: 118, width: layout.size.width - 380, height: 1), canvasHeight: layout.size.height).fill()
        bottomRect(fromTopLeft: CGRect(x: 190, y: layout.size.height - 138, width: layout.size.width - 380, height: 1), canvasHeight: layout.size.height).fill()
    }

    drawTopLeftCGImage(logo, in: layout.logoRect, canvasHeight: layout.size.height)

    logoBlue.withAlphaComponent(0.68).setFill()
    bottomRect(fromTopLeft: layout.accentRect, canvasHeight: layout.size.height).fill()

    drawCenteredText(
        "Follow @useichart",
        in: bottomRect(fromTopLeft: layout.handleRect, canvasHeight: layout.size.height),
        fontSize: layout.handleSize,
        weight: .bold,
        color: logoBlue
    )

    drawCenteredText(
        "TikTok + Instagram",
        in: bottomRect(fromTopLeft: layout.socialRect, canvasHeight: layout.size.height),
        fontSize: layout.socialSize,
        weight: .medium,
        color: paper.withAlphaComponent(0.76)
    )

    drawCenteredText(
        "useichart.com",
        in: bottomRect(fromTopLeft: layout.websiteRect, canvasHeight: layout.size.height),
        fontSize: layout.websiteSize,
        weight: .semibold,
        color: paper.withAlphaComponent(0.94)
    )

    drawCenteredText(
        "Available on the App Store",
        in: bottomRect(fromTopLeft: layout.appStoreRect, canvasHeight: layout.size.height),
        fontSize: layout.appStoreSize,
        weight: .semibold,
        color: paper.withAlphaComponent(0.72)
    )

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG for \(layout.outputName)")
    }
    try png.write(to: outputDir.appendingPathComponent(layout.outputName))
}

let fullLogo = cgImage(from: logoURL)
guard let logoCrop = fullLogo.cropping(to: CGRect(x: 1120, y: 690, width: 2560, height: 1020)) else {
    fatalError("Could not crop canonical wordmark")
}
let transparentLogo = keyedLogoImage(from: logoCrop)

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let vertical = TitleCardLayout(
    size: CGSize(width: 1080, height: 1920),
    outputName: "ichart-end-title-card-v1-vertical.png",
    logoRect: CGRect(x: 116, y: 430, width: 848, height: 338),
    accentRect: CGRect(x: 308, y: 854, width: 464, height: 2),
    handleRect: CGRect(x: 126, y: 930, width: 828, height: 82),
    socialRect: CGRect(x: 170, y: 1016, width: 740, height: 52),
    websiteRect: CGRect(x: 150, y: 1124, width: 780, height: 72),
    appStoreRect: CGRect(x: 160, y: 1230, width: 760, height: 54),
    handleSize: 56,
    socialSize: 32,
    websiteSize: 44,
    appStoreSize: 34
)

let horizontal = TitleCardLayout(
    size: CGSize(width: 1920, height: 1080),
    outputName: "ichart-end-title-card-v1-horizontal.png",
    logoRect: CGRect(x: 498, y: 198, width: 924, height: 368),
    accentRect: CGRect(x: 700, y: 622, width: 520, height: 2),
    handleRect: CGRect(x: 510, y: 666, width: 900, height: 74),
    socialRect: CGRect(x: 580, y: 744, width: 760, height: 44),
    websiteRect: CGRect(x: 570, y: 812, width: 780, height: 58),
    appStoreRect: CGRect(x: 580, y: 884, width: 760, height: 46),
    handleSize: 54,
    socialSize: 30,
    websiteSize: 38,
    appStoreSize: 30
)

try render(vertical, logo: transparentLogo)
try render(horizontal, logo: transparentLogo)

print(outputDir.appendingPathComponent(vertical.outputName).path)
print(outputDir.appendingPathComponent(horizontal.outputName).path)
