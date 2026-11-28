// Builds a before/after contact sheet from two folders of screenshots with matching names (NN-name.jpg/png):
// each screen is a captioned pair, "before" on the left and "after" on the right, three pairs to a row.
// Usage: swift tools/compare_sheet.swift <before-dir> <after-dir> <out.png> [title]
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: compare_sheet.swift <before-dir> <after-dir> <out.png> [title]\n".data(using: .utf8)!)
    exit(2)
}
let beforeDir = URL(fileURLWithPath: args[1]), afterDir = URL(fileURLWithPath: args[2])
let output = URL(fileURLWithPath: args[3])
let title = args.count > 4 ? args[4] : "Before → after"

func images(in dir: URL) -> [String: URL] {
    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    var result: [String: URL] = [:]
    for file in files where ["jpg", "png"].contains(file.pathExtension.lowercased()) {
        result[file.deletingPathExtension().lastPathComponent] = file
    }
    return result
}

func load(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

let before = images(in: beforeDir), after = images(in: afterDir)
let names = Set(before.keys).union(after.keys).sorted()

let thumb = CGSize(width: 240, height: 522)
let pairGap: CGFloat = 8, columnGap: CGFloat = 36, rowGap: CGFloat = 28, margin: CGFloat = 40
let caption: CGFloat = 30, header: CGFloat = 90
let perRow = 3
let pairWidth = thumb.width * 2 + pairGap
let rows = (names.count + perRow - 1) / perRow
let width = margin * 2 + CGFloat(perRow) * pairWidth + CGFloat(perRow - 1) * columnGap
let height = margin * 2 + header + CGFloat(rows) * (caption + 20 + thumb.height) + CGFloat(max(0, rows - 1)) * rowGap

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
// Flip to a top-left origin.
context.translateBy(x: 0, y: height)
context.scaleBy(x: 1, y: -1)
context.setFillColor(CGColor(red: 1, green: 0.957, blue: 0.886, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

func draw(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: CGColor) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!])
    let line = CTLineCreateWithAttributedString(attributed)
    context.saveGState()
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: point.x, y: point.y + size)
    CTLineDraw(line, context)
    context.restoreGState()
}

let ink = CGColor(red: 0.227, green: 0.102, blue: 0.071, alpha: 1)
let muted = CGColor(red: 0.42, green: 0.306, blue: 0.259, alpha: 1)
draw(title, at: CGPoint(x: margin, y: margin), size: 40, weight: .black, color: ink)
draw("Left: before (build 3) · Right: after", at: CGPoint(x: margin, y: margin + 50), size: 20, weight: .medium,
     color: muted)

func drawImage(_ url: URL?, in rect: CGRect) {
    context.setFillColor(CGColor(gray: 0.85, alpha: 1))
    context.fill(rect)
    if let url, let image = load(url) {
        let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let target = CGRect(x: rect.minX, y: rect.minY, width: size.width, height: size.height)
        context.saveGState()
        // Draw upright in the flipped context.
        context.translateBy(x: target.minX, y: target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: target.size))
        context.restoreGState()
    } else {
        draw("—", at: CGPoint(x: rect.midX - 8, y: rect.midY - 12), size: 24, weight: .bold, color: muted)
    }
    context.setStrokeColor(ink)
    context.setLineWidth(2)
    context.stroke(rect)
}

for (index, name) in names.enumerated() {
    let row = index / perRow, column = index % perRow
    let x = margin + CGFloat(column) * (pairWidth + columnGap)
    let y = margin + header + CGFloat(row) * (caption + 20 + thumb.height + rowGap)
    draw(name, at: CGPoint(x: x, y: y), size: 22, weight: .heavy, color: ink)
    draw("before", at: CGPoint(x: x, y: y + caption - 2), size: 14, weight: .semibold, color: muted)
    draw("after", at: CGPoint(x: x + thumb.width + pairGap, y: y + caption - 2), size: 14, weight: .semibold,
         color: muted)
    let top = y + caption + 20
    drawImage(before[name], in: CGRect(x: x, y: top, width: thumb.width, height: thumb.height))
    drawImage(after[name], in: CGRect(x: x + thumb.width + pairGap, y: top, width: thumb.width, height: thumb.height))
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("\(names.count) screens → \(output.path)")
