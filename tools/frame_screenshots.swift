// Frames raw simulator screenshots for the App Store and the website, in the app's look: each shot sits on
// warm cream paper under a chunky red-orange caption, as an outlined "game piece" standing on a hard
// dark-brown edge, with a few yellow and teal confetti bits, at the exact App Store size of its device.
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
        "01-lobby": "Friends nearby, no internet",
        "02-letter": "A new letter every round",
        "03-writing": "Everyone writes at once",
        "04-stop": "STOP! Pens down.",
        "05-scoring": "Read aloud, score together",
        "06-results": "See who's winning",
        "07-game-over": "Crown the winner",
    ],
    "pt-BR": [
        "01-lobby": "Amigos por perto, sem internet",
        "02-letter": "Uma letra nova a cada rodada",
        "03-writing": "Todo mundo escreve junto",
        "04-stop": "STOP! Lápis na mesa.",
        "05-scoring": "Leiam em voz alta e pontuem",
        "06-results": "Veja quem está ganhando",
        "07-game-over": "Coroe o vencedor",
    ],
]

/// The app's palette (`Stop/Features/Shared/Theme.swift`, light appearance).
func rgb(_ value: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}
/// The cream page, a shade warmer at the bottom (a vertical gradient keeps every row one color: small PNGs).
let paperTop = rgb(0xFFF4E2)
let paperBottom = rgb(0xFFE3B8)
/// Caption fill (`Theme.accent`) and the dark-brown ink of outlines, hard edges and the caption's drop.
let accent = rgb(0xC8360F)
let ink = rgb(0x3A1A12)
/// Confetti colors (the icon's yellow and teal, and the tiles' orange).
let yellow = rgb(0xFFC93C)
let teal = rgb(0x3CC2B3)
let orange = rgb(0xFF9A52)

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

/// The caption's font: SF Pro Rounded Black, like the app's display titles.
func roundedFont(size: CGFloat) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: .black)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return CTFontCreateWithFontDescriptor(descriptor as CTFontDescriptor, size, nil)
}

func lineWidth(_ text: String, font: CTFont) -> CGFloat {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// One line if it fits, else two lines broken where they come out most even ("STOP! Pens / down." never
/// leaves a lone word); the font shrinks until that fits. Returns the frame setter and the height it needs.
func layoutCaption(_ text: String, width: CGFloat, fontSize: CGFloat, color: NSColor) -> (CTFramesetter, CGFloat) {
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
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
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

/// A confetti bit: a circle or a rounded square in `color`, outlined in ink.
func confetti(_ context: CGContext, center: CGPoint, size: CGFloat, color: CGColor, square: Bool, angle: CGFloat) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: angle)
    let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
    let path = square ? CGPath(roundedRect: rect, cornerWidth: size * 0.25, cornerHeight: size * 0.25, transform: nil)
                      : CGPath(ellipseIn: rect, transform: nil)
    context.setFillColor(color)
    context.setStrokeColor(ink)
    context.setLineWidth(size * 0.16)
    context.addPath(path)
    context.drawPath(using: .fillStroke)
    context.restoreGState()
}

func frame(shot: CGImage, caption: String, size: CGSize) -> CGImage {
    let context = makeContext(size)
    let width = size.width, height = size.height

    // Cream paper (CoreGraphics' origin is bottom-left).
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [paperTop, paperBottom] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

    // Confetti in the caption band's corners, clear of the text.
    let bit = width * 0.034
    confetti(context, center: CGPoint(x: width * 0.07, y: height * 0.965), size: bit, color: yellow, square: false, angle: 0)
    confetti(context, center: CGPoint(x: width * 0.15, y: height * 0.985), size: bit * 0.7, color: teal, square: true, angle: 0.5)
    confetti(context, center: CGPoint(x: width * 0.93, y: height * 0.975), size: bit * 0.85, color: teal, square: false, angle: 0)
    confetti(context, center: CGPoint(x: width * 0.86, y: height * 0.955), size: bit * 0.6, color: orange, square: true, angle: -0.4)
    confetti(context, center: CGPoint(x: width * 0.045, y: height * 0.83), size: bit * 0.65, color: orange, square: true, angle: 0.3)
    confetti(context, center: CGPoint(x: width * 0.955, y: height * 0.835), size: bit * 0.75, color: yellow, square: true, angle: 0.8)

    // Caption band: the top 19% of the canvas. The caption stands on a hard ink drop, like the app's pieces.
    let margin = width * 0.08
    let bandTop = height * 0.045
    let bandHeight = height * 0.15
    let fontSize = width * 0.088
    let drop = width * 0.008
    let (setter, textHeight) = layoutCaption(caption, width: width - 2 * margin, fontSize: fontSize,
                                             color: NSColor(cgColor: accent)!)
    let (shadowSetter, _) = layoutCaption(caption, width: width - 2 * margin, fontSize: fontSize,
                                          color: NSColor(cgColor: ink)!)
    let textRect = CGRect(x: margin, y: height - bandTop - (bandHeight + textHeight) / 2,
                          width: width - 2 * margin, height: textHeight)
    CTFrameDraw(CTFramesetterCreateFrame(shadowSetter, CFRange(), CGPath(rect: textRect.offsetBy(dx: 0, dy: -drop),
                                                                          transform: nil), nil), context)
    CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: textRect, transform: nil), nil), context)

    // The screenshot below, scaled to the remaining height, with the device's rounded corners: a dark-brown
    // bezel standing on a hard edge (no blur, so the PNG stays small).
    let shotTop = bandTop + bandHeight + height * 0.01
    let depth = width * 0.014
    let bottom = height * 0.04
    let available = height - shotTop - bottom
    let scale = available / CGFloat(shot.height)
    let shotSize = CGSize(width: CGFloat(shot.width) * scale, height: CGFloat(shot.height) * scale)
    let shotRect = CGRect(x: (width - shotSize.width) / 2, y: bottom, width: shotSize.width, height: shotSize.height)
    let corner = shotSize.width * 0.12
    let bezel = shotSize.width * 0.022
    let bezelRect = shotRect.insetBy(dx: -bezel, dy: -bezel)
    func bezelPath(_ rect: CGRect) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: corner + bezel, cornerHeight: corner + bezel, transform: nil)
    }

    context.setFillColor(ink)
    context.addPath(bezelPath(bezelRect.offsetBy(dx: 0, dy: -depth)))
    context.fillPath()
    context.addPath(bezelPath(bezelRect))
    context.fillPath()

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
