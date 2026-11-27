// Renders the app icon (1024×1024 PNG) with CoreGraphics.
//   a        — a bold "STOP" stop sign on a warm cream background (the shipped icon)
//   a-dark   — the same sign on a dark background (the icon's dark appearance)
//   a-tinted — a grayscale sign on black (the icon's tinted appearance)
//   b        — a big letter tile with a pencil (alternative)
//   c        — a hand-stamped "STOP!" (alternative)
// Run: swift tools/make_icon.swift a App/Stop/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreGraphics

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "a"
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "AppIcon.png"
let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let center = CGPoint(x: size / 2, y: size / 2)
let full = CGRect(x: 0, y: 0, width: size, height: size)

// MARK: Helpers

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                         CGFloat(hex & 0xFF) / 255, a])!
}
func gradient(_ colors: [UInt32], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors.map { c($0) } as CFArray, locations: locations)!
}
func fill(_ path: CGPath, _ color: CGColor) {
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
}
/// Fills `path` with a vertical gradient, `colors` listed top → bottom.
func linear(_ path: CGPath, _ colors: [UInt32], top: CGFloat, bottom: CGFloat) {
    let locations = (0..<colors.count).map { CGFloat($0) / CGFloat(max(1, colors.count - 1)) }
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(gradient(colors, locations), start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func radial(_ colors: [UInt32], at point: CGPoint, radius: CGFloat) {
    let locations = (0..<colors.count).map { CGFloat($0) / CGFloat(max(1, colors.count - 1)) }
    ctx.drawRadialGradient(gradient(colors, locations), startCenter: point, startRadius: 0, endCenter: point,
                           endRadius: radius, options: [.drawsAfterEndLocation])
}
func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size) ?? base
}
/// `s` as a path, centred on `p`, squeezed to `maxWidth`. Kerning tightens bold capitals.
func textPath(_ s: String, _ font: NSFont, at p: CGPoint, maxWidth: CGFloat, kern: CGFloat = 0) -> CGPath {
    let attributed = NSAttributedString(string: s, attributes: [.font: font, .kern: kern])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let attributes = CTRunGetAttributes(run) as! [CFString: Any]
        let runFont = attributes[kCTFontAttributeName] as! CTFont
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for index in 0..<count {
            if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) {
                path.addPath(glyph, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
            }
        }
    }
    let scale = min(1, maxWidth / bounds.width)
    var transform = CGAffineTransform(translationX: p.x, y: p.y)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -bounds.midX, y: -bounds.midY)
    return path.copy(using: &transform)!
}
/// A regular octagon with flat top and bottom, `apothem` from the centre to each side.
func octagon(_ center: CGPoint, apothem: CGFloat, corner: CGFloat = 0) -> CGPath {
    let radius = apothem / cos(.pi / 8)
    let points = (0..<8).map { index -> CGPoint in
        let angle = Double.pi / 8 + Double(index) * .pi / 4
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
    let path = CGMutablePath()
    guard corner > 0 else { path.addLines(between: points); path.closeSubpath(); return path }
    // Softly rounded corners: arcs through each vertex between the midpoints of its sides.
    let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    path.move(to: mid(points[7], points[0]))
    for index in 0..<8 {
        path.addArc(tangent1End: points[index], tangent2End: mid(points[index], points[(index + 1) % 8]), radius: corner)
    }
    path.closeSubpath()
    return path
}
func shadow(_ blur: CGFloat, y: CGFloat, _ color: CGColor, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: y), blur: blur, color: color)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    draw()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// MARK: The stop sign

struct SignLook {
    var background: [UInt32]   // top → bottom
    var glow: UInt32?          // a soft light behind the sign
    var face: [UInt32]         // the sign's face, top → bottom
    var rim: UInt32            // the white band
    var bevel: UInt32          // the band's shaded bottom edge
    var letters: UInt32
    var shadow: CGColor
}

func stopSign(_ look: SignLook) {
    linear(CGPath(rect: full, transform: nil), look.background, top: size, bottom: 0)
    if let glow = look.glow {
        ctx.saveGState(); ctx.setBlendMode(.softLight)
        radial([glow, look.background.last!], at: CGPoint(x: size / 2, y: size * 0.62), radius: size * 0.62)
        ctx.restoreGState()
    }
    let signCenter = CGPoint(x: center.x, y: center.y + 6)
    let apothem: CGFloat = 368
    let outer = octagon(signCenter, apothem: apothem, corner: 46)
    // Depth: a soft drop shadow and a darker edge underneath the face.
    shadow(70, y: -34, look.shadow) { fill(outer, c(look.face.last!)) }
    fill(outer, c(look.rim))
    // A thin bevel of shade along the bottom of the white band.
    ctx.saveGState(); ctx.addPath(outer); ctx.clip()
    linear(CGPath(rect: full, transform: nil), [look.rim, look.rim, look.bevel], top: signCenter.y + apothem,
           bottom: signCenter.y - apothem)
    ctx.restoreGState()
    let face = octagon(signCenter, apothem: apothem - 34, corner: 30)
    linear(face, look.face, top: signCenter.y + apothem, bottom: signCenter.y - apothem)
    // A glossy highlight across the top half of the face.
    ctx.saveGState(); ctx.addPath(face); ctx.clip()
    let gloss = CGMutablePath()
    gloss.addEllipse(in: CGRect(x: signCenter.x - 520, y: signCenter.y + 60, width: 1040, height: 760))
    ctx.addPath(gloss); ctx.clip()
    let glossGradient = CGGradient(colorsSpace: cs, colors: [c(0xFFFFFF, 0.16), c(0xFFFFFF, 0.0)] as CFArray,
                                   locations: [0, 1])!
    ctx.drawLinearGradient(glossGradient, start: CGPoint(x: 0, y: signCenter.y + apothem),
                           end: CGPoint(x: 0, y: signCenter.y + 60), options: [])
    ctx.restoreGState()
    // The letters, with a slight shadow so they sit on the face.
    let letters = textPath("STOP", rounded(300, .black), at: CGPoint(x: signCenter.x, y: signCenter.y - 4),
                           maxWidth: 2 * (apothem - 34) * 0.86, kern: -6)
    shadow(10, y: -8, c(0x000000, 0.28)) { fill(letters, c(look.letters)) }
}

// MARK: Alternatives

/// b: the round's letter on a tile, with a pencil leaning on it.
func letterTile() {
    linear(CGPath(rect: full, transform: nil), [0xFFF6EA, 0xFFE2C6], top: size, bottom: 0)
    ctx.saveGState()
    ctx.translateBy(x: center.x - 40, y: center.y + 20)
    ctx.rotate(by: 6 * .pi / 180)
    let tile = CGRect(x: -300, y: -300, width: 600, height: 600)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 150, cornerHeight: 150, transform: nil)
    shadow(60, y: -30, c(0x7A2A0A, 0.35)) { fill(tilePath, c(0xB82E0C)) }
    linear(tilePath, [0xF0522A, 0xD63A12, 0xB82E0C], top: 300, bottom: -300)
    let inner = CGPath(roundedRect: tile.insetBy(dx: 34, dy: 34), cornerWidth: 118, cornerHeight: 118, transform: nil)
    ctx.addPath(inner); ctx.setStrokeColor(c(0xFFFFFF, 0.55)); ctx.setLineWidth(14); ctx.strokePath()
    let letter = textPath("S", rounded(470, .black), at: CGPoint(x: 0, y: 0), maxWidth: 420)
    shadow(10, y: -8, c(0x000000, 0.25)) { fill(letter, c(0xFFFFFF)) }
    ctx.restoreGState()
    // The pencil, lying diagonally across the tile's corner.
    ctx.saveGState()
    ctx.translateBy(x: center.x + 250, y: center.y - 230)
    ctx.rotate(by: 220 * .pi / 180)
    let body = CGRect(x: -60, y: -320, width: 120, height: 500)
    shadow(30, y: -16, c(0x5A2A0A, 0.35)) {
        fill(CGPath(rect: body, transform: nil), c(0xF5B82E))
    }
    linear(CGPath(rect: body.insetBy(dx: 40, dy: 0), transform: nil), [0xFFD66B, 0xFFD66B], top: 0, bottom: 1)
    fill(CGPath(rect: CGRect(x: -60, y: 180, width: 120, height: 40), transform: nil), c(0xC9CFDB))
    fill(CGPath(roundedRect: CGRect(x: -60, y: 210, width: 120, height: 90), cornerWidth: 40, cornerHeight: 40,
                transform: nil), c(0xF28CA0))
    let cone = CGMutablePath()
    cone.move(to: CGPoint(x: -60, y: -320)); cone.addLine(to: CGPoint(x: 60, y: -320))
    cone.addLine(to: CGPoint(x: 0, y: -470)); cone.closeSubpath()
    fill(cone, c(0xF3D6B0))
    let tip = CGMutablePath()
    tip.move(to: CGPoint(x: -22, y: -415)); tip.addLine(to: CGPoint(x: 22, y: -415))
    tip.addLine(to: CGPoint(x: 0, y: -470)); tip.closeSubpath()
    fill(tip, c(0x2A2A30))
    ctx.restoreGState()
}

/// c: a red rubber stamp on paper, slightly worn.
func stamp() {
    linear(CGPath(rect: full, transform: nil), [0xFBF7EF, 0xF1E8D8], top: size, bottom: 0)
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: -12 * .pi / 180)
    let ink = c(0xD63A12, 0.92)
    let frame = CGRect(x: -400, y: -210, width: 800, height: 420)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(CGPath(roundedRect: frame, cornerWidth: 70, cornerHeight: 70, transform: nil))
    ctx.setStrokeColor(ink); ctx.setLineWidth(36); ctx.strokePath()
    ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: 42, dy: 42), cornerWidth: 40, cornerHeight: 40, transform: nil))
    ctx.setLineWidth(12); ctx.strokePath()
    fill(textPath("STOP!", rounded(260, .black), at: .zero, maxWidth: 640, kern: -4), ink)
    // Wear: knock specks out of the ink.
    ctx.setBlendMode(.destinationOut)
    var seed: UInt64 = 0x5EED
    func random() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
    }
    for _ in 0..<900 {
        let x = -440 + random() * 880, y = -250 + random() * 500, r = 1.5 + random() * random() * 9
        ctx.setFillColor(c(0x000000, 0.5 + random() * 0.5))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// MARK: Draw

let face: [UInt32] = [0xF0532A, 0xD63A12, 0xB52D0B]
switch variant {
case "a-dark":
    stopSign(SignLook(background: [0x2B201C, 0x120D0B], glow: 0x6A3A28, face: face, rim: 0xF4EFEA, bevel: 0xCFC6BE,
                      letters: 0xFFFFFF, shadow: c(0x000000, 0.6)))
case "a-tinted":
    stopSign(SignLook(background: [0x000000, 0x000000], glow: nil, face: [0x6A6A6A, 0x505050, 0x3C3C3C], rim: 0xFFFFFF, bevel: 0xCFCFCF,
                      letters: 0xFFFFFF, shadow: c(0x000000, 0.0)))
case "b":
    letterTile()
case "c":
    stamp()
default:
    stopSign(SignLook(background: [0xFFF5E8, 0xFFD9B5], glow: 0xFFFFFF, face: face, rim: 0xFFFFFF, bevel: 0xDCD3CC,
                      letters: 0xFFFFFF, shadow: c(0x7A2A0A, 0.45)))
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
