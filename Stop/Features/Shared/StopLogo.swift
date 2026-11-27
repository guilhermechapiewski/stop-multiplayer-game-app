import CoreText
import SwiftUI
import UIKit

/// The app's mark, drawn like the app icon: a tilted cream comic speech bubble shouting a chunky red "STOP!",
/// with a sparkle and action marks. Vector, so it is crisp at any size, and it softens a little in dark mode
/// to match the icon's dark appearance. Decorative, so hidden from VoiceOver.
///
/// The geometry mirrors `tools/make_icon.swift` (same design units: the bubble's centre at the origin, y up);
/// keep the two in step when the design changes.
struct StopSign: View {
    var size: CGFloat = 120

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let look = colorScheme == .dark ? Look.dark : Look.light
        Canvas { context, canvasSize in
            Self.draw(in: &context, size: canvasSize, look: look)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Look

    private struct Look {
        var ink: Color
        var shadow: Color
        var bubble: [Color]       // top → bottom
        var highlight: Color
        var letters: [Color]      // top → bottom
        var gloss: Color
        var spark: Color

        static let light = Look(
            ink: Color(hex: 0x3A1A12), shadow: Color(hex: 0x5A1404).opacity(0.30),
            bubble: [Color(hex: 0xFFFFFF), Color(hex: 0xFFF6E2), Color(hex: 0xF6DDB4)], highlight: .white,
            letters: [Color(hex: 0xF0532A), Color(hex: 0xD63A12), Color(hex: 0xB52D0B)],
            gloss: .white.opacity(0.22), spark: Color(hex: 0xFFC93C))

        static let dark = Look(
            ink: Color(hex: 0x240B06), shadow: .black.opacity(0.55),
            bubble: [Color(hex: 0xFFF8EA), Color(hex: 0xF8EAD0), Color(hex: 0xE6C99C)], highlight: .white.opacity(0.85),
            letters: [Color(hex: 0xF0532A), Color(hex: 0xD63A12), Color(hex: 0xB52D0B)],
            gloss: .white.opacity(0.18), spark: Color(hex: 0xE8B030))
    }

    // MARK: Drawing

    /// The drawing's bounds in design units (bubble, tail, outline, sparkle and action marks).
    private static let bounds = CGRect(x: -470, y: -405, width: 970, height: 745)

    private static func draw(in context: inout GraphicsContext, size: CGSize, look: Look) {
        let scale = min(size.width, size.height) / bounds.width
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.scaleBy(x: scale, y: -scale)  // Design units, y up.
        context.translateBy(x: -bounds.midX, y: -bounds.midY)

        let rounded = { (width: CGFloat) in StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round) }
        let shapes = Shapes.shared

        // A sparkle by the tail and action marks off the top-right, behind the bubble.
        context.stroke(shapes.sparkle, with: .color(look.ink), style: rounded(14))
        context.fill(shapes.sparkle, with: .color(look.spark))
        for mark in shapes.marks {
            context.stroke(mark, with: .color(look.ink), style: rounded(34))
            context.stroke(mark, with: .color(look.spark), style: rounded(18))
        }

        var bubble = context
        bubble.rotate(by: .degrees(-9))
        // Hard offset shadow, sticker style.
        var shadow = bubble
        shadow.translateBy(x: 18, y: -26)
        for part in [shapes.body, shapes.tail] {
            shadow.fill(part, with: .color(look.shadow))
            shadow.stroke(part, with: .color(look.shadow), style: rounded(52))
        }
        // The bubble, outlined, shaded towards the bottom, with a highlight swoosh.
        for part in [shapes.body, shapes.tail] { bubble.stroke(part, with: .color(look.ink), style: rounded(52)) }
        let shade = GraphicsContext.Shading.linearGradient(
            Gradient(colors: look.bubble), startPoint: CGPoint(x: 0, y: 290), endPoint: CGPoint(x: 0, y: -290))
        bubble.fill(shapes.body, with: shade)
        bubble.fill(shapes.tail, with: shade)
        bubble.stroke(shapes.highlight, with: .color(look.highlight), style: rounded(26))

        // Chunky 3D letters: a dark extrusion, the outline with solid counters, then the face and a gloss band.
        var extrusion = bubble
        extrusion.translateBy(x: 6, y: -14)
        for letter in shapes.letters {
            extrusion.stroke(letter, with: .color(look.ink), style: rounded(30))
            extrusion.fill(letter, with: .color(look.ink))
        }
        for letter in shapes.letters { bubble.stroke(letter, with: .color(look.ink), style: rounded(30)) }
        for counter in shapes.contours { bubble.fill(counter, with: .color(look.ink)) }
        let face = GraphicsContext.Shading.linearGradient(
            Gradient(colors: look.letters), startPoint: CGPoint(x: 0, y: 130), endPoint: CGPoint(x: 0, y: -110))
        for letter in shapes.letters {
            bubble.fill(letter, with: face)
            var gloss = bubble
            gloss.clip(to: letter)
            gloss.fill(Path(CGRect(x: -500, y: 40, width: 1000, height: 30)), with: .color(look.gloss))
        }
    }

    // MARK: Shapes

    /// The logo's paths in design units, built once.
    private struct Shapes: Sendable {
        var body: Path
        var tail: Path
        var highlight: Path
        var letters: [Path]
        /// Every contour of every letter on its own, so filling them makes the counters (O, P) solid.
        var contours: [Path]
        var sparkle: Path
        var marks: [Path]

        static let shared = Shapes()

        private init() {
            // A slightly lumpy oval with a tail pointing down-left.
            var body = Path()
            let rx: CGFloat = 420, ry: CGFloat = 290, n = 220
            for i in 0...n {
                let t = CGFloat(i) / CGFloat(n) * 2 * .pi
                let wobble = 1 + 0.018 * sin(3 * t + 0.6) + 0.012 * sin(5 * t)
                let point = CGPoint(x: rx * wobble * cos(t), y: ry * wobble * sin(t))
                if i == 0 { body.move(to: point) } else { body.addLine(to: point) }
            }
            body.closeSubpath()
            self.body = body

            var tail = Path()
            tail.move(to: CGPoint(x: -240, y: -200))
            tail.addQuadCurve(to: CGPoint(x: -330, y: -400), control: CGPoint(x: -250, y: -330))
            tail.addQuadCurve(to: CGPoint(x: -70, y: -270), control: CGPoint(x: -170, y: -320))
            tail.closeSubpath()
            self.tail = tail

            var highlight = Path()
            highlight.move(to: CGPoint(x: -330, y: 120))
            highlight.addQuadCurve(to: CGPoint(x: -150, y: 245), control: CGPoint(x: -300, y: 225))
            self.highlight = highlight

            letters = Self.bouncyLetters()
            contours = letters.flatMap(Self.contours)

            // A 4-point sparkle near the tail, in the bubble's unrotated frame.
            let (cx, cy, r): (CGFloat, CGFloat, CGFloat) = (-415, -230, 44)
            let k = r * 0.22
            var sparkle = Path()
            sparkle.move(to: CGPoint(x: cx, y: cy + r))
            sparkle.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + k, y: cy + k))
            sparkle.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx + k, y: cy - k))
            sparkle.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx - k, y: cy - k))
            sparkle.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx - k, y: cy + k))
            sparkle.closeSubpath()
            self.sparkle = sparkle

            marks = [((370, 250), (430, 312)), ((410, 168), (478, 186)), ((298, 306), (320, 384))].map { a, b in
                var mark = Path()
                mark.move(to: CGPoint(x: a.0, y: a.1))
                mark.addLine(to: CGPoint(x: b.0, y: b.1))
                return mark
            }
        }

        /// "STOP!" letter by letter, each tilted and nudged up or down so the word bounces.
        private static func bouncyLetters() -> [Path] {
            let base = UIFont.systemFont(ofSize: 232, weight: .black)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 232) } ?? base
            let chars: [(String, CGFloat, CGFloat)] = [("S", -8, 6), ("T", 5, 22), ("O", -4, -4), ("P", 7, 18), ("!", 12, 4)]
            let glyphs = chars.map { glyphPath($0.0, font: font) }
            let gap: CGFloat = 4
            let total = glyphs.reduce(0) { $0 + $1.boundingRect.width } + gap * CGFloat(glyphs.count - 1)
            var x = -total / 2
            var placed: [Path] = []
            for (glyph, (_, rotation, dy)) in zip(glyphs, chars) {
                let bounds = glyph.boundingRect
                let transform = CGAffineTransform(translationX: x + bounds.width / 2, y: dy - 6)
                    .rotated(by: rotation * .pi / 180)
                    .translatedBy(x: -bounds.midX, y: -bounds.midY)
                placed.append(glyph.applying(transform))
                x += bounds.width + gap
            }
            return placed
        }

        /// The outline of `text` in `font`, baseline at y = 0, y up.
        private static func glyphPath(_ text: String, font: UIFont) -> Path {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            let path = CGMutablePath()
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                for index in 0..<count {
                    if let glyph = CTFontCreatePathForGlyph(font as CTFont, glyphs[index], nil) {
                        path.addPath(glyph, transform: CGAffineTransform(translationX: positions[index].x,
                                                                          y: positions[index].y))
                    }
                }
            }
            return Path(path)
        }

        /// Each closed contour of `path` as its own path.
        private static func contours(_ path: Path) -> [Path] {
            var result: [Path] = []
            var current = Path()
            path.forEach { element in
                switch element {
                case .move(let to):
                    if !current.isEmpty { result.append(current) }
                    current = Path()
                    current.move(to: to)
                case .line(let to): current.addLine(to: to)
                case .quadCurve(let to, let control): current.addQuadCurve(to: to, control: control)
                case .curve(let to, let control1, let control2):
                    current.addCurve(to: to, control1: control1, control2: control2)
                case .closeSubpath: current.closeSubpath()
                }
            }
            if !current.isEmpty { result.append(current) }
            return result
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

#Preview {
    HStack(spacing: 24) {
        StopSign(size: 64)
        StopSign(size: 132)
    }
    .padding()
}
