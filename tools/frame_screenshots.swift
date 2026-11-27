// Frames raw simulator screenshots for the App Store and the website: each shot sits on an accent-color
// gradient under a large caption, at the exact App Store size of its device.
//
//   swift tools/frame_screenshots.swift <raw dir> <App Store dir> <website dir>
//
// <raw dir>/<device>/<locale>/NN-name.png  ->  <App Store dir>/<device>/<locale>/NN-name.png
//                                              <website dir>/<locale>/NN-name.jpg (600 px wide, from "iphone")
// tools/screenshots.sh runs it after capturing; it can also be run on its own to re-frame.
import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// App Store sizes per device folder (portrait).
let sizes: [String: CGSize] = [
    "iphone": CGSize(width: 1320, height: 2868),        // 6.9" (iPhone 17 Pro Max)
    "iphone-medium": CGSize(width: 1206, height: 2622), // 6.3" (iPhone 17)
]
/// The website copies come from this device's frames.
let websiteDevice = "iphone"
let websiteWidth = 600

/// Captions per locale, by shot.
let captions: [String: [String: String]] = [
    "en-US": [
        "01-lobby": "Pick your categories",
        "02-letter": "A new letter every round",
        "03-writing": "Everyone writes at once",
        "04-stop": "STOP! Pens down.",
        "05-scoring": "Score together, your way",
        "06-results": "See who's winning",
        "07-game-over": "No internet needed",
    ],
    "pt-BR": [
        "01-lobby": "Escolha as categorias",
        "02-letter": "Uma letra nova a cada rodada",
        "03-writing": "Todo mundo escreve junto",
        "04-stop": "STOP! Lápis na mesa.",
        "05-scoring": "Pontuem juntos, do seu jeito",
        "06-results": "Veja quem está ganhando",
        "07-game-over": "Sem internet",
    ],
]

/// The app's accent (`AccentColor`, #C8360F) and a lighter tint of it for the top of the gradient.
let gradientTop = CGColor(srgbRed: 0xF0 / 255, green: 0x5A / 255, blue: 0x2E / 255, alpha: 1)
let gradientBottom = CGColor(srgbRed: 0xB0 / 255, green: 0x2B / 255, blue: 0x0A / 255, alpha: 1)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("can't read \(url.path)") }
    return image
}

func write(_ image: CGImage, to url: URL, type: UTType, quality: Double? = nil) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        fail("can't write \(url.path)")
    }
    var properties: [CFString: Any] = [:]
    if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fail("can't write \(url.path)") }
}

func makeContext(_ size: CGSize, opaque: Bool = true) -> CGContext {
    guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue
                                                     : CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("can't make a bitmap context")
    }
    context.interpolationQuality = .high
    return context
}

/// The caption's font: SF Pro Rounded Heavy, like the app's titles.
func roundedFont(size: CGFloat) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return CTFontCreateWithFontDescriptor(descriptor as CTFontDescriptor, size, nil)
}

func lineWidth(_ text: String, font: CTFont) -> CGFloat {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// One line if it fits, else two lines broken where they come out most even ("STOP! Pens / down." never
/// leaves a lone word); the font shrinks until that fits. Returns the frame setter and the height it needs.
func layoutCaption(_ text: String, width: CGFloat, fontSize: CGFloat) -> (CTFramesetter, CGFloat) {
    let words = text.split(separator: " ").map(String.init)
    var size = fontSize
    while true {
        let font = roundedFont(size: size)
        var lines: [String]? = lineWidth(text, font: font) <= width ? [text] : nil
        if lines == nil, words.count > 1 {
            let splits = (1..<words.count).map { index -> (lines: [String], widest: CGFloat) in
                let parts = [words[..<index].joined(separator: " "), words[index...].joined(separator: " ")]
                return (parts, parts.map { lineWidth($0, font: font) }.max()!)
            }
            if let best = splits.min(by: { $0.widest < $1.widest }), best.widest <= width { lines = best.lines }
        }
        if let lines {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineHeightMultiple = 0.95
            let attributed = NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
                .font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph,
            ])
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(
                setter, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
            return (setter, ceil(fit.height))
        }
        guard size > 40 else { fail("caption doesn't fit: \(text)") }
        size -= 4
    }
}

func frame(shot: CGImage, caption: String, size: CGSize) -> CGImage {
    let context = makeContext(size)
    let width = size.width, height = size.height

    // Background gradient (CoreGraphics' origin is bottom-left).
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [gradientTop, gradientBottom] as CFArray,
                              locations: [0, 1])!
    // Vertical, so every row is one color: smaller PNGs than a diagonal.
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

    // Caption band: the top 19% of the canvas.
    let margin = width * 0.08
    let bandTop = height * 0.045
    let bandHeight = height * 0.15
    let (setter, textHeight) = layoutCaption(caption, width: width - 2 * margin, fontSize: width * 0.088)
    let textRect = CGRect(x: margin, y: height - bandTop - (bandHeight + textHeight) / 2,
                          width: width - 2 * margin, height: textHeight)
    let textFrame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: textRect, transform: nil), nil)
    CTFrameDraw(textFrame, context)

    // The screenshot below, scaled to the remaining height, with the device's rounded corners and a shadow.
    let shotTop = bandTop + bandHeight + height * 0.01
    let available = height - shotTop - height * 0.04
    let scale = available / CGFloat(shot.height)
    let shotSize = CGSize(width: CGFloat(shot.width) * scale, height: CGFloat(shot.height) * scale)
    let shotRect = CGRect(x: (width - shotSize.width) / 2, y: height * 0.04, width: shotSize.width, height: shotSize.height)
    let corner = shotSize.width * 0.12
    let bezel = shotSize.width * 0.022
    let bezelRect = shotRect.insetBy(dx: -bezel, dy: -bezel)
    let bezelPath = CGPath(roundedRect: bezelRect, cornerWidth: corner + bezel, cornerHeight: corner + bezel, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -height * 0.006), blur: height * 0.02,
                      color: CGColor(gray: 0, alpha: 0.35))
    context.setFillColor(CGColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1))
    context.addPath(bezelPath)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(CGPath(roundedRect: shotRect, cornerWidth: corner, cornerHeight: corner, transform: nil))
    context.clip()
    context.draw(shot, in: shotRect)
    context.restoreGState()

    guard let image = context.makeImage() else { fail("can't render a frame") }
    return image
}

func resized(_ image: CGImage, width: Int) -> CGImage {
    let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
    let context = makeContext(CGSize(width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let small = context.makeImage() else { fail("can't resize") }
    return small
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fail("usage: swift tools/frame_screenshots.swift <raw dir> <App Store dir> <website dir>")
}
let rawRoot = URL(fileURLWithPath: arguments[1])
let storeRoot = URL(fileURLWithPath: arguments[2])
let webRoot = URL(fileURLWithPath: arguments[3])
let files = FileManager.default

var framedCount = 0
for device in sizes.keys.sorted() {
    let size = sizes[device]!
    for locale in captions.keys.sorted() {
        let rawDir = rawRoot.appending(path: device).appending(path: locale)
        guard let names = try? files.contentsOfDirectory(atPath: rawDir.path).filter({ $0.hasSuffix(".png") }).sorted(),
              !names.isEmpty else {
            fail("no screenshots in \(rawDir.path)")
        }
        for name in names {
            let key = String(name.dropLast(4))
            guard let caption = captions[locale]?[key] else { fail("no caption for \(locale)/\(key)") }
            let framed = frame(shot: loadImage(rawDir.appending(path: name)), caption: caption, size: size)
            write(framed, to: storeRoot.appending(path: device).appending(path: locale).appending(path: name), type: .png)
            if device == websiteDevice {
                write(resized(framed, width: websiteWidth),
                      to: webRoot.appending(path: locale).appending(path: key + ".jpg"), type: .jpeg, quality: 0.82)
            }
            framedCount += 1
            print("\(device)/\(locale)/\(name)")
        }
    }
}
print("Framed \(framedCount) screenshots.")
