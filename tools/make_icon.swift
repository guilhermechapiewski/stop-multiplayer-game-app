// Renders the app icon with CoreGraphics: a tilted cream comic speech bubble shouting a chunky red "STOP!"
// on a red-orange sunburst, with confetti bursting around it (the moment someone shouts "STOP!").
//
// Writes three 1024×1024 opaque PNGs (corners are not baked in; iOS applies the mask):
//   AppIcon.png         — the App Store and home-screen icon
//   AppIcon-Dark.png    — the dark appearance: the same bubble on a deep, near-black red sunburst
//   AppIcon-Tinted.png  — the tinted appearance: grayscale, a light bubble on black, so iOS tinting reads well
//
// Run from the repository root (regenerates the asset catalog in place):
//   swift tools/make_icon.swift
// or into another folder, e.g. for a preview:
//   swift tools/make_icon.swift build/icons
//
// The in-app logo (`StopSign` in Stop/Features/Shared/StopLogo.swift) draws the same bubble in SwiftUI; keep
// the two in step when the design changes.
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Stop/Assets.xcassets/AppIcon.appiconset"
let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let full = CGRect(x: 0, y: 0, width: size, height: size)
var ctx: CGContext!

// MARK: Palette

let red: UInt32 = 0xD63A12
let redDeep: UInt32 = 0xB52D0B
let redLight: UInt32 = 0xF0532A
let ink: UInt32 = 0x3A1A12        // the hand-drawn outline colour
let cream: UInt32 = 0xFFF6E2
let yellow: UInt32 = 0xFFC93C
let teal: UInt32 = 0x1FB5A8

/// Everything that changes between the light, dark and tinted appearances.
struct Look {
    var background: [UInt32]          // top → bottom
    var glow: [UInt32]?               // soft-light glow behind the bubble, centre → edge
    var rays: CGColor                 // sunburst wedges
    var ink: UInt32                   // outlines and letter extrusion
    var shadow: CGColor               // the bubble's hard offset shadow
    var bubble: [UInt32]              // the bubble's fill, top → middle → bottom
    var highlight: CGColor            // the bubble's highlight swoosh
    var letters: [UInt32]             // the letters' face, top → bottom
    var gloss: CGColor
    /// Confetti colours, by role.
    var yellow: UInt32, teal: UInt32, cream: UInt32
}

let light = Look(
    background: [0xEE5A24, red, 0xA82808], glow: [0xFFE2A8, 0xD63A12], rays: c(0xFFFFFF, 0.07), ink: ink,
    shadow: c(0x5A1404, 0.45), bubble: [0xFFFFFF, cream, 0xF6DDB4], highlight: c(0xFFFFFF),
    letters: [redLight, red, redDeep], gloss: c(0xFFFFFF, 0.22), yellow: yellow, teal: teal, cream: cream)

let dark = Look(
    background: [0x3A0E06, 0x220704, 0x120302], glow: [0x7A2410, 0x1A0503], rays: c(0xFF6A3A, 0.07), ink: 0x240B06,
    shadow: c(0x000000, 0.55), bubble: [0xFFF8EA, 0xF8EAD0, 0xE6C99C], highlight: c(0xFFFFFF, 0.85),
    letters: [redLight, red, redDeep], gloss: c(0xFFFFFF, 0.18), yellow: 0xE8B030, teal: 0x1A9C91, cream: 0xE9DCC4)

let tinted = Look(
    background: [0x1C1C1C, 0x0A0A0A, 0x000000], glow: nil, rays: c(0xFFFFFF, 0.05), ink: 0x000000,
    shadow: c(0x000000, 0), bubble: [0xFFFFFF, 0xF2F2F2, 0xD6D6D6], highlight: c(0xFFFFFF),
    letters: [0x5A5A5A, 0x464646, 0x343434], gloss: c(0xFFFFFF, 0.14), yellow: 0x8C8C8C, teal: 0x5E5E5E,
    cream: 0xB4B4B4)

// MARK: Helpers

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                         CGFloat(hex & 0xFF) / 255, a])!
}
func gradient(_ colors: [UInt32], _ locations: [CGFloat]? = nil) -> CGGradient {
    let locs = locations ?? (0..<colors.count).map { CGFloat($0) / CGFloat(max(1, colors.count - 1)) }
    return CGGradient(colorsSpace: cs, colors: colors.map { c($0) } as CFArray, locations: locs)!
}
func fill(_ path: CGPath, _ color: CGColor) {
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
}
func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) {
    ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(width)
    ctx.setLineJoin(.round); ctx.setLineCap(.round); ctx.strokePath()
}
/// Fills `path` with a linear gradient from `top` (y) to `bottom` (y), colours listed top → bottom.
func linear(_ path: CGPath, _ colors: [UInt32], top: CGFloat, bottom: CGFloat) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(gradient(colors), start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func radial(_ colors: [UInt32], at p: CGPoint, radius: CGFloat) {
    ctx.drawRadialGradient(gradient(colors), startCenter: p, startRadius: 0, endCenter: p, endRadius: radius,
                           options: [.drawsAfterEndLocation])
}
/// Sticker-style outline: strokes every path wide first, then fills them, so overlapping shapes read as one
/// outlined silhouette.
func outlined(_ paths: [CGPath], width: CGFloat, color: UInt32, fillWith: () -> Void) {
    for p in paths { stroke(p, c(color), width * 2) }
    fillWith()
}
func transformed(_ dx: CGFloat, _ dy: CGFloat, rotate degrees: CGFloat = 0, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: dx, y: dy)
    ctx.rotate(by: degrees * .pi / 180)
    draw()
    ctx.restoreGState()
}
func rounded(_ size: CGFloat, _ weight: NSFont.Weight = .black) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size) ?? base
}
/// The glyph outline of `s` and its glyph bounds (unpositioned, baseline at y = 0).
func rawText(_ s: String, _ font: NSFont) -> (CGPath, CGRect) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let attributes = CTRunGetAttributes(run) as! [CFString: Any]
        let runFont = attributes[kCTFontAttributeName] as! CTFont
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for i in 0..<count {
            if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                path.addPath(g, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
            }
        }
    }
    return (path, path.boundingBoxOfPath)
}
/// Each closed contour of `path` as its own path.
func contours(_ path: CGPath) -> [CGPath] {
    var result: [CGPath] = []
    var current = CGMutablePath()
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint:
            if !current.isEmpty { result.append(current) }
            current = CGMutablePath(); current.move(to: e.points[0])
        case .addLineToPoint: current.addLine(to: e.points[0])
        case .addQuadCurveToPoint: current.addQuadCurve(to: e.points[1], control: e.points[0])
        case .addCurveToPoint: current.addCurve(to: e.points[2], control1: e.points[0], control2: e.points[1])
        case .closeSubpath: current.closeSubpath()
        @unknown default: break
        }
    }
    if !current.isEmpty { result.append(current) }
    return result
}
func rrect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry), transform: nil)
}
func line(_ a: CGPoint, _ b: CGPoint) -> CGPath {
    let p = CGMutablePath(); p.move(to: a); p.addLine(to: b); return p
}
/// A 4-point sparkle star.
func sparkle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k = r * 0.22
    p.move(to: CGPoint(x: cx, y: cy + r))
    p.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + k, y: cy + k))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx + k, y: cy - k))
    p.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx - k, y: cy - k))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx - k, y: cy + k))
    p.closeSubpath()
    return p
}
/// Sunburst wedges radiating from `p`.
func rays(from p: CGPoint, count: Int, color: CGColor, offset: CGFloat = 0) {
    let path = CGMutablePath()
    for i in 0..<count {
        let a0 = offset + CGFloat(i) * 2 * .pi / CGFloat(count)
        let a1 = a0 + .pi / CGFloat(count)
        path.move(to: p)
        path.addLine(to: CGPoint(x: p.x + 2000 * cos(a0), y: p.y + 2000 * sin(a0)))
        path.addLine(to: CGPoint(x: p.x + 2000 * cos(a1), y: p.y + 2000 * sin(a1)))
        path.closeSubpath()
    }
    fill(path, color)
}

// MARK: The icon

func icon(_ look: Look) {
    // Background, a soft glow and a sunburst behind the bubble.
    linear(CGPath(rect: full, transform: nil), look.background, top: size, bottom: 0)
    let burst = CGPoint(x: 520, y: 560)
    if let glow = look.glow {
        ctx.saveGState(); ctx.setBlendMode(.softLight)
        radial(glow, at: burst, radius: 620)
        ctx.restoreGState()
    }
    rays(from: burst, count: 16, color: look.rays, offset: 0.1)

    // Confetti behind the bubble.
    enum Kind { case strip, dot, sparkle, squiggle }
    let confetti: [(CGFloat, CGFloat, CGFloat, UInt32, Kind)] = [
        (150, 870, 30, look.yellow, .strip), (330, 960, -20, look.teal, .dot), (650, 975, 0, look.yellow, .dot),
        (480, 940, 70, look.teal, .strip), (70, 560, 10, look.cream, .dot), (900, 330, 20, look.teal, .strip),
        (110, 300, -40, look.yellow, .sparkle), (930, 140, 0, look.cream, .sparkle), (560, 110, 0, look.yellow, .squiggle),
        (800, 230, 0, look.cream, .dot), (60, 720, 80, look.teal, .strip), (280, 110, -25, look.cream, .strip),
    ]
    for (x, y, r, col, kind) in confetti {
        transformed(x, y, rotate: r) {
            switch kind {
            case .strip:
                let p = rrect(CGRect(x: -34, y: -14, width: 68, height: 28), 10)
                outlined([p], width: 7, color: look.ink) { fill(p, c(col)) }
            case .dot:
                let p = ellipse(0, 0, 22, 22)
                outlined([p], width: 7, color: look.ink) { fill(p, c(col)) }
            case .sparkle:
                let p = sparkle(0, 0, 46)
                outlined([p], width: 7, color: look.ink) { fill(p, c(col)) }
            case .squiggle:
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -48, y: 0))
                p.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -36, y: 34), control2: CGPoint(x: -12, y: 34))
                p.addCurve(to: CGPoint(x: 48, y: 0), control1: CGPoint(x: 12, y: -34), control2: CGPoint(x: 36, y: -34))
                stroke(p, c(look.ink), 30); stroke(p, c(col), 16)
            }
        }
    }

    transformed(burst.x, burst.y, rotate: -9) {
        // The bubble: a slightly lumpy oval with a tail pointing down-left.
        let body = CGMutablePath()
        let rx: CGFloat = 420, ry: CGFloat = 290
        let n = 220
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n) * 2 * .pi
            let wobble = 1 + 0.018 * sin(3 * t + 0.6) + 0.012 * sin(5 * t)
            let pt = CGPoint(x: rx * wobble * cos(t), y: ry * wobble * sin(t))
            if i == 0 { body.move(to: pt) } else { body.addLine(to: pt) }
        }
        body.closeSubpath()
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: -240, y: -200))
        tail.addQuadCurve(to: CGPoint(x: -330, y: -400), control: CGPoint(x: -250, y: -330))
        tail.addQuadCurve(to: CGPoint(x: -70, y: -270), control: CGPoint(x: -170, y: -320))
        tail.closeSubpath()
        // Hard offset shadow, sticker style.
        transformed(18, -26) {
            fill(body, look.shadow); fill(tail, look.shadow)
            stroke(body, look.shadow, 52); stroke(tail, look.shadow, 52)
        }
        outlined([body, tail], width: 26, color: look.ink) {
            fill(body, c(look.bubble[1])); fill(tail, c(look.bubble[1]))
        }
        // Soft inner shade along the bottom for volume.
        ctx.saveGState(); ctx.addPath(body); ctx.addPath(tail); ctx.clip()
        ctx.drawLinearGradient(gradient(look.bubble, [0, 0.5, 1]), start: CGPoint(x: 0, y: ry),
                               end: CGPoint(x: 0, y: -ry), options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        // A highlight swoosh, top-left.
        let hl = CGMutablePath()
        hl.move(to: CGPoint(x: -330, y: 120))
        hl.addQuadCurve(to: CGPoint(x: -150, y: 245), control: CGPoint(x: -300, y: 225))
        stroke(hl, look.highlight, 26)

        // Bouncy per-letter "STOP!": (letter, rotation in degrees, vertical offset).
        let font = rounded(232)
        let chars: [(String, CGFloat, CGFloat)] = [("S", -8, 6), ("T", 5, 22), ("O", -4, -4), ("P", 7, 18), ("!", 12, 4)]
        let parts: [(CGPath, CGRect)] = chars.map { rawText($0.0, font) }
        let gap: CGFloat = 4
        let total = parts.reduce(0) { $0 + $1.1.width } + gap * CGFloat(parts.count - 1)
        var x = -total / 2
        var placed: [CGPath] = []
        for (i, (path, b)) in parts.enumerated() {
            let (_, rot, dy) = chars[i]
            var t = CGAffineTransform(translationX: x + b.width / 2, y: dy - 6)
                .rotated(by: rot * .pi / 180)
                .translatedBy(x: -b.midX, y: -b.midY)
            placed.append(path.copy(using: &t)!)
            x += b.width + gap
        }
        // Chunky 3D letters: a dark extrusion, then the outline, then the face.
        for p in placed { transformed(6, -14) { stroke(p, c(look.ink), 30); fill(p, c(look.ink)) } }
        outlined(placed, width: 15, color: look.ink) {
            // Fill each contour on its own first so the counters (in O, P) are solid ink, with no specks.
            for p in placed { for contour in contours(p) { fill(contour, c(look.ink)) } }
            for p in placed { linear(p, look.letters, top: 130, bottom: -110) }
        }
        // A thin gloss band across each letter.
        for p in placed {
            ctx.saveGState(); ctx.addPath(p); ctx.clip()
            fill(CGPath(rect: CGRect(x: -500, y: 40, width: 1000, height: 30), transform: nil), look.gloss)
            ctx.restoreGState()
        }
    }
    // Action marks bursting off the bubble's top-right.
    for (a, b) in [(CGPoint(x: 895, y: 815), CGPoint(x: 960, y: 880)), (CGPoint(x: 935, y: 730), CGPoint(x: 1010, y: 750)),
                   (CGPoint(x: 820, y: 875), CGPoint(x: 845, y: 960))] {
        stroke(line(a, b), c(look.ink), 34); stroke(line(a, b), c(look.yellow), 18)
    }
}

// MARK: Render

func render(_ look: Look, _ name: String) {
    ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    icon(look)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
render(light, "AppIcon.png")
render(dark, "AppIcon-Dark.png")
render(tinted, "AppIcon-Tinted.png")
