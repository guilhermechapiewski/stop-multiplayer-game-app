import SwiftUI

/// The app icon's red-orange sunburst: rays fanning out from the centre, fading towards the edge. Turns slowly
/// when `isAnimated` (callers pass `!reduceMotion`); still otherwise. Decorative.
///
/// The rays are drawn once, into a canvas big enough to cover the frame at any angle, and turned by a
/// `rotationEffect` animation: the body and the canvas aren't evaluated again while it turns (unlike a
/// `TimelineView(.animation)`, which redraws every frame). It rests while the app isn't active, in Low Power
/// Mode, and off screen.
struct Sunburst: View {
    var isAnimated = false
    /// An even number: rays alternate with gaps.
    var rays = 18
    /// Seconds per full turn.
    var period: Double = 40
    /// Fades towards the edge (on the page); off when the burst fills a clipped disc.
    var fades = true
    /// Seconds of turning before it comes to rest; nil turns for as long as it's on screen.
    var turnsFor: Double?

    @Environment(\.scenePhase) private var scenePhase
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var motion = SunburstMotion()
    @State private var isOnScreen = false

    private var shouldTurn: Bool {
        isOnScreen && SunburstMotion.shouldTurn(isAnimated: isAnimated, isActive: scenePhase == .active,
                                                isLowPower: isLowPower)
    }

    var body: some View {
        #if DEBUG
        let _ = SunburstDiagnostics.bodies += 1
        #endif
        GeometryReader { proxy in
            let side = hypot(proxy.size.width, proxy.size.height)
            rayCanvas
                .frame(width: side, height: side)
                .rotationEffect(.degrees(motion.angle))
                // A new identity drops the running animation when it pauses.
                .id(motion.generation)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
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
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onChange(of: shouldTurn, initial: true) { _, turns in
            turns ? start() : pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func start() {
        var next = motion
        guard let animation = next.start(at: .now, period: period, limit: turnsFor) else { return }
        withAnimation(animation) { motion = next }
    }

    private func pause() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { motion.pause(at: .now, period: period) }
    }

    /// The rays, drawn once (a square: it covers the frame at every angle).
    private var rayCanvas: some View {
        let rays = self.rays
        return Canvas { context, size in
            #if DEBUG
            MainActor.assumeIsolated { SunburstDiagnostics.draws += 1 }
            #endif
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = hypot(size.width, size.height) / 2
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.sunburstGap))
            let step = 2 * Double.pi / Double(rays)
            for index in stride(from: 0, to: rays, by: 2) {
                let a0 = Double(index) * step
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

/// How a turning sunburst moves: the view animates `angle` linearly towards a target and, to pause, sets it to
/// where the burst is at that moment (under a new `generation`, so the old animation is dropped).
struct SunburstMotion {
    /// The rotation in degrees: where it rests, or the target of the running animation.
    private(set) var angle = 0.0
    /// Changes whenever the motion pauses.
    private(set) var generation = 0
    private var turningSince: Date?
    private var restingAngle = 0.0
    private var limit: Double?
    /// Seconds turned so far (counts towards `limit`).
    private var turned = 0.0

    static func shouldTurn(isAnimated: Bool, isActive: Bool, isLowPower: Bool) -> Bool {
        isAnimated && isActive && !isLowPower
    }

    /// Starts turning from where it rests: sets `angle` to the target and returns the animation to reach it with,
    /// or nil (and changes nothing) if it's already turning or has used up its `limit`.
    mutating func start(at now: Date, period: Double, limit: Double?) -> Animation? {
        guard turningSince == nil, period > 0 else { return nil }
        self.limit = limit
        if let limit {
            let remaining = limit - turned
            guard remaining > 0 else { return nil }
            turningSince = now
            angle = restingAngle + remaining / period * 360
            return .linear(duration: remaining)
        }
        turningSince = now
        angle = restingAngle + 360
        return .linear(duration: period).repeatForever(autoreverses: false)
    }

    /// Stops where the burst is at `now`.
    mutating func pause(at now: Date, period: Double) {
        guard let since = turningSince else { return }
        var elapsed = max(0, now.timeIntervalSince(since))
        if let limit {
            elapsed = min(elapsed, limit - turned)
            turned += elapsed
        } else {
            elapsed = elapsed.truncatingRemainder(dividingBy: period)
        }
        restingAngle = (restingAngle + elapsed / period * 360).truncatingRemainder(dividingBy: 360)
        angle = restingAngle
        turningSince = nil
        generation += 1
    }
}

#if DEBUG
/// Counts the sunburst's body evaluations and canvas draws, for the test that it doesn't redraw every frame.
@MainActor enum SunburstDiagnostics {
    static var bodies = 0
    static var draws = 0
    static var snapshot: (bodies: Int, draws: Int) { (bodies, draws) }
}
#endif

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
