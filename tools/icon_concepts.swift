// Renders three playful draft icon concepts (1024×1024, opaque, corners not baked in) plus a contact sheet.
//   A — a hand-drawn "STOP!" speech bubble bursting with confetti
//   B — S·T·O·P letter tiles tumbling like game pieces
//   C — "Stoppy", a round stop-sign creature raising a hand
// Run: swift tools/icon_concepts.swift design/icon-concepts
// Drafts only: the shipped icon is still rendered by tools/make_icon.swift.
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design/icon-concepts"
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
let tealDeep: UInt32 = 0x12857C

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
/// Sticker-style outline: strokes every path wide in ink first, then fills them, so overlapping shapes
/// read as one outlined silhouette.
func outlined(_ paths: [CGPath], width: CGFloat, color: UInt32 = ink, fillWith: () -> Void) {
    for p in paths { stroke(p, c(color), width * 2) }
    fillWith()
}
func shadow(_ blur: CGFloat, x: CGFloat = 0, y: CGFloat, _ color: CGColor, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: x, height: y), blur: blur, color: color)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    draw()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
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
func rawText(_ s: String, _ font: NSFont, kern: CGFloat = 0) -> (CGPath, CGRect) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .kern: kern]))
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
/// `s` centred on `p`, fitted to at most `maxWidth`.
func textPath(_ s: String, _ font: NSFont, at p: CGPoint, maxWidth: CGFloat = .infinity, kern: CGFloat = 0) -> CGPath {
    let (path, bounds) = rawText(s, font, kern: kern)
    let scale = min(1, maxWidth / bounds.width)
    var t = CGAffineTransform(translationX: p.x, y: p.y).scaledBy(x: scale, y: scale)
        .translatedBy(x: -bounds.midX, y: -bounds.midY)
    return path.copy(using: &t)!
}
/// A rounded octagon with flat top and bottom.
func octagon(_ center: CGPoint, apothem: CGFloat, corner: CGFloat) -> CGPath {
    let radius = apothem / cos(.pi / 8)
    let pts = (0..<8).map { i -> CGPoint in
        let a = Double.pi / 8 + Double(i) * .pi / 4
        return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    }
    let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    let path = CGMutablePath()
    path.move(to: mid(pts[7], pts[0]))
    for i in 0..<8 { path.addArc(tangent1End: pts[i], tangent2End: mid(pts[i], pts[(i + 1) % 8]), radius: corner) }
    path.closeSubpath()
    return path
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

// MARK: A — speech bubble

func conceptA() {
    // Warm red-orange with a soft glow and a sunburst behind the bubble.
    linear(CGPath(rect: full, transform: nil), [0xEE5A24, red, 0xA82808], top: size, bottom: 0)
    let burst = CGPoint(x: 520, y: 560)
    ctx.saveGState(); ctx.setBlendMode(.softLight)
    radial([0xFFE2A8, 0xD63A12], at: burst, radius: 620)
    ctx.restoreGState()
    rays(from: burst, count: 16, color: c(0xFFFFFF, 0.07), offset: 0.1)

    // Confetti behind the bubble.
    let confetti: [(CGFloat, CGFloat, CGFloat, UInt32, Int)] = [
        // x, y, rotation, colour, kind (0 strip, 1 dot, 2 sparkle, 3 squiggle)
        (150, 870, 30, yellow, 0), (330, 960, -20, teal, 1), (650, 975, 0, yellow, 1), (480, 940, 70, teal, 0),
        (70, 560, 10, cream, 1), (900, 330, 20, teal, 0), (110, 300, -40, yellow, 2), (930, 140, 0, cream, 2),
        (560, 110, 0, yellow, 3), (800, 230, 0, cream, 1), (60, 720, 80, teal, 0), (280, 110, -25, cream, 0),
    ]
    for (x, y, r, col, kind) in confetti {
        transformed(x, y, rotate: r) {
            switch kind {
            case 0:
                let p = rrect(CGRect(x: -34, y: -14, width: 68, height: 28), 10)
                outlined([p], width: 7) { fill(p, c(col)) }
            case 1:
                let p = ellipse(0, 0, 22, 22)
                outlined([p], width: 7) { fill(p, c(col)) }
            case 2:
                let p = sparkle(0, 0, 46)
                outlined([p], width: 7) { fill(p, c(col)) }
            default:
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -48, y: 0))
                p.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -36, y: 34), control2: CGPoint(x: -12, y: 34))
                p.addCurve(to: CGPoint(x: 48, y: 0), control1: CGPoint(x: 12, y: -34), control2: CGPoint(x: 36, y: -34))
                stroke(p, c(ink), 30); stroke(p, c(col), 16)
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
            fill(body, c(0x5A1404, 0.45)); fill(tail, c(0x5A1404, 0.45))
            stroke(body, c(0x5A1404, 0.45), 52); stroke(tail, c(0x5A1404, 0.45), 52)
        }
        outlined([body, tail], width: 26) {
            fill(body, c(cream)); fill(tail, c(cream))
        }
        // Soft inner shade along the bottom for volume.
        ctx.saveGState(); ctx.addPath(body); ctx.addPath(tail); ctx.clip()
        ctx.drawLinearGradient(gradient([0xFFFFFF, cream, 0xF6DDB4], [0, 0.5, 1]), start: CGPoint(x: 0, y: ry),
                               end: CGPoint(x: 0, y: -ry), options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        // A highlight swoosh, top-left.
        let swoosh = CGMutablePath()
        swoosh.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: 0, clockwise: false)
        let hl = CGMutablePath()
        hl.move(to: CGPoint(x: -330, y: 120))
        hl.addQuadCurve(to: CGPoint(x: -150, y: 245), control: CGPoint(x: -300, y: 225))
        stroke(hl, c(0xFFFFFF), 26)

        // Bouncy per-letter "STOP!".
        let font = rounded(232)
        let chars: [(String, CGFloat, CGFloat)] = [("S", -8, 6), ("T", 5, 22), ("O", -4, -4), ("P", 7, 18), ("!", 12, 4)]
        var parts: [(CGPath, CGRect)] = chars.map { rawText($0.0, font) }
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
        parts.removeAll()
        // Chunky 3D letters: a dark extrusion, then ink outline, then the red face.
        for p in placed { transformed(6, -14) { stroke(p, c(ink), 30); fill(p, c(ink)) } }
        outlined(placed, width: 13) {
            for p in placed { linear(p, [redLight, red, redDeep], top: 130, bottom: -110) }
        }
        // Tiny gloss on each letter.
        for p in placed {
            ctx.saveGState(); ctx.addPath(p); ctx.clip()
            fill(CGPath(rect: CGRect(x: -500, y: 40, width: 1000, height: 30), transform: nil), c(0xFFFFFF, 0.22))
            ctx.restoreGState()
        }
    }
    // Action marks bursting off the bubble's top-right.
    for (a, b) in [(CGPoint(x: 895, y: 815), CGPoint(x: 960, y: 880)), (CGPoint(x: 935, y: 730), CGPoint(x: 1010, y: 750)),
                   (CGPoint(x: 820, y: 875), CGPoint(x: 845, y: 960))] {
        stroke(line(a, b), c(ink), 34); stroke(line(a, b), c(yellow), 18)
    }
}

// MARK: B — tumbling letter tiles

func tile(_ letter: String, at p: CGPoint, rotate: CGFloat, face: [UInt32], side: UInt32, letterColor: UInt32,
          letterShade: UInt32, side3D: CGFloat = 30) {
    transformed(p.x, p.y, rotate: rotate) {
        let s: CGFloat = 330
        let r = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
        let facePath = rrect(r, 72)
        let sidePath = rrect(r.offsetBy(dx: 0, dy: -side3D), 72)
        shadow(40, y: -34, c(0x053A35, 0.45)) {
            outlined([facePath, sidePath], width: 14) { fill(sidePath, c(side)); fill(facePath, c(face[0])) }
        }
        // Re-stroke for crisp outline above the shadow layer's antialiasing.
        linear(facePath, face, top: s / 2, bottom: -s / 2)
        // Inner bevel highlight.
        stroke(rrect(r.insetBy(dx: 22, dy: 22), 54), c(0xFFFFFF, 0.5), 8)
        let glyph = textPath(letter, rounded(250), at: CGPoint(x: 0, y: 6), maxWidth: 230)
        transformed(0, -10) { fill(glyph, c(letterShade)) }
        fill(glyph, c(letterColor))
    }
}

func conceptB() {
    linear(CGPath(rect: full, transform: nil), [0x34C9B8, teal, tealDeep], top: size, bottom: 0)
    ctx.saveGState(); ctx.setBlendMode(.softLight)
    radial([0xFFFFFF, tealDeep], at: CGPoint(x: 460, y: 640), radius: 700)
    ctx.restoreGState()
    // Faint dotted pattern like a game board.
    for row in 0..<12 {
        for col in 0..<12 {
            let x = CGFloat(col) * 92 + (row % 2 == 0 ? 0 : 46) + 20, y = CGFloat(row) * 92 + 20
            fill(ellipse(x, y, 7, 7), c(0xFFFFFF, 0.10))
        }
    }

    let creamFace: [UInt32] = [0xFFFBF0, cream, 0xFBE8C4]
    let redFace: [UInt32] = [redLight, red, redDeep]
    let yellowFace: [UInt32] = [0xFFDB6E, yellow, 0xF2B027]
    // S, T, O sit in a wonky stack; P is flying in with speed lines.
    tile("O", at: CGPoint(x: 330, y: 330), rotate: 6, face: yellowFace, side: 0xC98A10, letterColor: red,
         letterShade: 0xA8500A)
    tile("S", at: CGPoint(x: 315, y: 690), rotate: -9, face: redFace, side: 0x8A2208, letterColor: cream,
         letterShade: 0x7A1C05)
    tile("T", at: CGPoint(x: 670, y: 655), rotate: 7, face: creamFace, side: 0xD9B98A, letterColor: red,
         letterShade: 0xD8A98A)
    // Speed lines behind P.
    for (y, len) in [(CGFloat(420), CGFloat(170)), (300, 230), (185, 150)] {
        let a = CGPoint(x: 1010, y: y + 40), b = CGPoint(x: 1010 - len, y: y + 40 - len * 0.18)
        stroke(line(a, b), c(ink), 30); stroke(line(a, b), c(0xFFFFFF), 14)
    }
    tile("P", at: CGPoint(x: 700, y: 300), rotate: -16, face: redFace, side: 0x8A2208, letterColor: cream,
         letterShade: 0x7A1C05)
    // Pops of fun.
    for (x, y, r, col) in [(CGFloat(880), CGFloat(900), CGFloat(48), yellow), (120, 120, 36, cream), (930, 560, 30, cream),
                           (480, 930, 34, yellow)] {
        let p = sparkle(x, y, r)
        outlined([p], width: 7) { fill(p, c(col)) }
    }
}

// MARK: C — stop-sign creature

func conceptC() {
    linear(CGPath(rect: full, transform: nil), [0xFFE07A, yellow, 0xF5A623], top: size, bottom: 0)
    let body = CGPoint(x: 445, y: 505)
    ctx.saveGState(); ctx.setBlendMode(.softLight)
    radial([0xFFFFFF, 0xF5A623], at: CGPoint(x: body.x, y: body.y + 120), radius: 650)
    ctx.restoreGState()
    rays(from: body, count: 14, color: c(0xFFFFFF, 0.14), offset: 0.15)

    // Little feet.
    for fx in [body.x - 120, body.x + 120] {
        let foot = rrect(CGRect(x: fx - 74, y: 92, width: 148, height: 84), 42)
        let leg = rrect(CGRect(x: fx - 22, y: 140, width: 44, height: 110), 20)
        outlined([leg, foot], width: 14) { fill(leg, c(redDeep)); fill(foot, c(teal)) }
    }

    // Arm up to a raised "stop!" hand on the right.
    let arm = CGMutablePath()
    arm.move(to: CGPoint(x: body.x + 250, y: body.y - 40))
    arm.addQuadCurve(to: CGPoint(x: 830, y: 610), control: CGPoint(x: 880, y: 430))
    stroke(arm, c(ink), 92); stroke(arm, c(redDeep), 64)

    transformed(body.x, body.y, rotate: -7) {
        let outer = octagon(.zero, apothem: 320, corner: 84)
        let face = octagon(.zero, apothem: 289, corner: 64)
        transformed(20, -28) { fill(outer, c(0x8A4A00, 0.35)); stroke(outer, c(0x8A4A00, 0.35), 40) }
        outlined([outer], width: 20) { fill(outer, c(0xFFFFFF)) }
        linear(outer, [0xFFFFFF, 0xFFFFFF, 0xE4D9CF], top: 320, bottom: -320)
        linear(face, [redLight, red, redDeep], top: 289, bottom: -289)
        // Gloss.
        ctx.saveGState(); ctx.addPath(face); ctx.clip()
        fill(ellipse(-60, 330, 420, 200), c(0xFFFFFF, 0.13))
        ctx.restoreGState()

        // Eyes: big, glossy, looking at you.
        for ex in [CGFloat(-118), 118] {
            let eye = ellipse(ex, 70, 74, 92)
            outlined([eye], width: 12) { fill(eye, c(0xFFFFFF)) }
            fill(ellipse(ex + 10, 58, 44, 54), c(ink))
            fill(ellipse(ex + 26, 80, 16, 18), c(0xFFFFFF))
            fill(ellipse(ex - 2, 36, 7, 7), c(0xFFFFFF))
        }
        // Raised, excited eyebrows.
        for (ex, tilt) in [(CGFloat(-118), CGFloat(1)), (118, -1)] {
            let brow = CGMutablePath()
            brow.move(to: CGPoint(x: ex - 52, y: 190 - tilt * 10))
            brow.addQuadCurve(to: CGPoint(x: ex + 52, y: 190 + tilt * 10), control: CGPoint(x: ex, y: 228))
            stroke(brow, c(ink), 22)
        }
        // Cheeks.
        for ex in [CGFloat(-200), 200] { fill(ellipse(ex, -40, 50, 30), c(0xFF8A7A, 0.75)) }
        // Wide-open shouting mouth.
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: -110, y: -60))
        mouth.addQuadCurve(to: CGPoint(x: 110, y: -60), control: CGPoint(x: 0, y: -40))
        mouth.addCurve(to: CGPoint(x: -110, y: -60), control1: CGPoint(x: 100, y: -250), control2: CGPoint(x: -100, y: -250))
        mouth.closeSubpath()
        outlined([mouth], width: 12) { fill(mouth, c(0x4A1208)) }
        ctx.saveGState(); ctx.addPath(mouth); ctx.clip()
        fill(ellipse(0, -205, 70, 50), c(0xFF7A8A))
        fill(rrect(CGRect(x: -80, y: -82, width: 160, height: 34), 14), c(0xFFFFFF))
        ctx.restoreGState()
    }

    // The hand: palm facing out, fingers up — the universal "STOP!".
    transformed(835, 735, rotate: 10) {
        let palm = rrect(CGRect(x: -95, y: -110, width: 190, height: 190), 80)
        var fingers: [CGPath] = []
        for (i, h) in [CGFloat(150), 175, 170, 140].enumerated() {
            let x = -95 + CGFloat(i) * 48
            fingers.append(rrect(CGRect(x: x, y: -10, width: 46, height: h), 23))
        }
        let thumb = CGMutablePath()
        thumb.addPath(rrect(CGRect(x: -60, y: -30, width: 46, height: 140), 23),
                      transform: CGAffineTransform(translationX: -40, y: -70).rotated(by: 0.7))
        let cuff = rrect(CGRect(x: -85, y: -165, width: 170, height: 70), 26)
        // Palm, thumb and cuff first; then each finger outlined on its own so the fingers read separately.
        outlined([thumb, palm, cuff], width: 14) {
            fill(thumb, c(0xFFFFFF)); fill(palm, c(0xFFFFFF)); fill(cuff, c(teal))
        }
        for f in fingers {
            outlined([f], width: 11) { fill(f, c(0xFFFFFF)) }
        }
        // Cover the finger outlines where they join the palm.
        fill(rrect(CGRect(x: -88, y: -40, width: 176, height: 70), 30), c(0xFFFFFF))
        // Soft shade on the palm.
        let crease = CGMutablePath()
        crease.move(to: CGPoint(x: -40, y: -70)); crease.addQuadCurve(to: CGPoint(x: 30, y: -20), control: CGPoint(x: 20, y: -70))
        stroke(crease, c(ink, 0.25), 9)
    }
    // "Shout" marks around the hand.
    for (a, b) in [(CGPoint(x: 925, y: 925), CGPoint(x: 970, y: 975)), (CGPoint(x: 965, y: 830), CGPoint(x: 1010, y: 845)),
                   (CGPoint(x: 815, y: 950), CGPoint(x: 810, y: 1000))] {
        stroke(line(a, b), c(ink), 34); stroke(line(a, b), c(0xFFFFFF), 16)
    }
    // Confetti.
    for (x, y, r, col) in [(CGFloat(140), CGFloat(880), CGFloat(50), teal), (90, 560, 30, red), (160, 250, 34, 0xFFFFFF),
                           (930, 300, 40, teal), (600, 950, 28, red)] {
        let p = sparkle(x, y, r)
        outlined([p], width: 7) { fill(p, c(col)) }
    }
}

// MARK: Render

func render(_ draw: () -> Void) -> CGImage {
    ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw()
    return ctx.makeImage()!
}
func save(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}
/// Downsamples in steps for a clean small preview.
func scaled(_ image: CGImage, to px: Int) -> CGImage {
    var current = image
    var w = image.width
    while w > px {
        let next = max(px, w / 2)
        let small = CGContext(data: nil, width: next, height: next, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        small.interpolationQuality = .high
        small.draw(current, in: CGRect(x: 0, y: 0, width: next, height: next))
        current = small.makeImage()!
        w = next
    }
    return current
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let concepts: [(String, CGImage)] = [("A", render(conceptA)), ("B", render(conceptB)), ("C", render(conceptC))]
for (label, image) in concepts { save(image, "concept-\(label.lowercased()).png") }

// Contact sheet: one row per concept — the full 1024 render, then 180 and 60 px previews masked like the
// home screen, on a light and a dark wallpaper.
let margin: CGFloat = 60, labelW: CGFloat = 150, panelW: CGFloat = 400
let sheetW = margin + labelW + size + margin + panelW + margin
let rowH = size + margin
let sheetH = margin + CGFloat(concepts.count) * rowH
let sheet = CGContext(data: nil, width: Int(sheetW), height: Int(sheetH), bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx = sheet
NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
fill(CGPath(rect: CGRect(x: 0, y: 0, width: sheetW, height: sheetH), transform: nil), c(0xF7F4EF))
func masked(_ image: CGImage, _ rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(rrect(rect, rect.width * 0.2237)); ctx.clip()
    ctx.interpolationQuality = .none
    ctx.draw(image, in: rect)
    ctx.restoreGState()
}
for (i, (label, image)) in concepts.enumerated() {
    let y0 = sheetH - margin - CGFloat(i + 1) * rowH + margin
    fill(textPath(label, rounded(140, .heavy), at: CGPoint(x: margin + labelW / 2 - 10, y: y0 + size - 90)), c(0x2A2420))
    ctx.draw(image, in: CGRect(x: margin + labelW, y: y0, width: size, height: size))
    let px = margin + labelW + size + margin
    let half = size / 2
    for (j, bg) in [(0, 0xE9EEF5 as UInt32), (1, 0x15171F)] {
        let py = y0 + size - CGFloat(j + 1) * half
        let panel = CGRect(x: px, y: py + 8, width: panelW, height: half - 16)
        fill(rrect(panel, 36), c(bg))
        if j == 0 {
            ctx.saveGState(); ctx.addPath(rrect(panel, 36)); ctx.clip()
            ctx.drawLinearGradient(gradient([0xF6E7D8, 0xDCE8F2]), start: CGPoint(x: panel.minX, y: panel.maxY),
                                   end: CGPoint(x: panel.maxX, y: panel.minY), options: [])
            ctx.restoreGState()
        } else {
            ctx.saveGState(); ctx.addPath(rrect(panel, 36)); ctx.clip()
            ctx.drawLinearGradient(gradient([0x23263A, 0x0E0F14]), start: CGPoint(x: panel.minX, y: panel.maxY),
                                   end: CGPoint(x: panel.maxX, y: panel.minY), options: [])
            ctx.restoreGState()
        }
        let cy = panel.midY + 20
        masked(scaled(image, to: 180), CGRect(x: panel.minX + 50, y: cy - 90, width: 180, height: 180))
        masked(scaled(image, to: 60), CGRect(x: panel.minX + 290, y: cy - 30, width: 60, height: 60))
        let tc = c(j == 0 ? 0x5A524A : 0xB8B4C8)
        fill(textPath("180 px", rounded(26, .semibold), at: CGPoint(x: panel.minX + 140, y: panel.minY + 52)), tc)
        fill(textPath("60 px", rounded(26, .semibold), at: CGPoint(x: panel.minX + 320, y: panel.minY + 52)), tc)
    }
}
save(sheet.makeImage()!, "contact-sheet.png")
