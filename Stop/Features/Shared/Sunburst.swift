import SwiftUI

/// The app icon's red-orange sunburst: rays fanning out from the centre, fading towards the edge. Turns slowly
/// when `isAnimated` (callers pass `!reduceMotion`); still otherwise. Decorative.
struct Sunburst: View {
    var isAnimated = false
    /// An even number: rays alternate with gaps.
    var rays = 18
    /// Seconds per full turn.
    var period: Double = 40
    /// Fades towards the edge (on the page); off when the burst fills a clipped disc.
    var fades = true

    @State private var start = Date.now

    var body: some View {
        Group {
            if isAnimated {
                TimelineView(.animation) { context in
                    canvas(angle: context.date.timeIntervalSince(start) / period * 360)
                }
            } else {
                canvas(angle: 0)
            }
        }
        .mask {
            GeometryReader { proxy in
                let radius = min(proxy.size.width, proxy.size.height) / 2
                RadialGradient(colors: fades ? [.black, .black.opacity(0.9), .clear] : [.black], center: .center,
                               startRadius: radius * 0.15, endRadius: radius)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func canvas(angle: Double) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = hypot(size.width, size.height) / 2
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.sunburstGap))
            let step = 2 * Double.pi / Double(rays)
            for index in stride(from: 0, to: rays, by: 2) {
                let a0 = Double(index) * step + angle * .pi / 180
                var ray = Path()
                ray.move(to: center)
                ray.addArc(center: center, radius: radius, startAngle: .radians(a0), endAngle: .radians(a0 + step),
                           clockwise: false)
                ray.closeSubpath()
                context.fill(ray, with: .color(Theme.sunburstRay))
            }
        }
    }
}

/// A comic "burst": a spiky star, for the STOP! stamp and the category-complete badge.
struct Starburst: InsettableShape {
    var points = 14
    /// The inner radius as a fraction of the outer one.
    var innerRatio: CGFloat = 0.78
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerX = rect.width / 2, outerY = rect.height / 2
        var path = Path()
        let count = points * 2
        for index in 0..<count {
            let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
            // A little irregular, like a hand-drawn burst.
            let jitter: CGFloat = index.isMultiple(of: 2) ? (index % 4 == 0 ? 1 : 0.92) : innerRatio
            let point = CGPoint(x: center.x + cos(angle) * outerX * jitter, y: center.y + sin(angle) * outerY * jitter)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> Starburst {
        var copy = self
        copy.inset += amount
        return copy
    }
}

#Preview("Sunburst") {
    VStack {
        Sunburst().frame(width: 300, height: 300)
        Starburst()
            .fill(Theme.yellow)
            .overlay { Starburst().strokeBorder(Theme.ink, lineWidth: 3) }
            .frame(width: 160, height: 160)
    }
    .padding()
    .background(Theme.background)
}
