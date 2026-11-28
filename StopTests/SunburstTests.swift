import SwiftUI
import Testing
import UIKit
@testable import Stop

@MainActor
struct SunburstTests {
    /// A turning sunburst is one drawing under a running rotation: its body and its canvas are evaluated once
    /// (or a couple of times while it settles), not once a frame like a `TimelineView(.animation)`.
    @Test func turningDoesNotRedrawEveryFrame() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        window.rootViewController = UIHostingController(
            rootView: Sunburst(isAnimated: true, rays: 18, period: 2)
                .environment(\.scenePhase, .active)
                .frame(width: 300, height: 300))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await Task.sleep(for: .milliseconds(300))
        let before = SunburstDiagnostics.snapshot
        let first = Self.snapshot(of: window)
        // 0.35 s at 2 s a turn is 63°: not a whole ray-and-gap pair (40°), so the picture changes.
        try await Task.sleep(for: .milliseconds(350))
        let second = Self.snapshot(of: window)
        try await Task.sleep(for: .milliseconds(650))
        let after = SunburstDiagnostics.snapshot

        #expect(first != second, "the sunburst didn't turn")

        #expect(after.bodies - before.bodies <= 2, "body re-evaluated \(after.bodies - before.bodies) times in 1 s")
        #expect(after.draws - before.draws <= 2, "canvas drawn \(after.draws - before.draws) times in 1 s")
    }

    /// The window as it is on screen (mid-animation), as PNG data.
    private static func snapshot(of window: UIWindow) -> Data? {
        UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }.pngData()
    }

    @Test(arguments: [
        // isAnimated, isActive, isLowPower, expected
        (true, true, false, true),
        (false, true, false, false),
        (true, false, false, false),
        (true, true, true, false),
    ])
    func turnsOnlyWhenAnimatedActiveAndNotInLowPower(isAnimated: Bool, isActive: Bool, isLowPower: Bool,
                                                     expected: Bool) {
        #expect(SunburstMotion.shouldTurn(isAnimated: isAnimated, isActive: isActive, isLowPower: isLowPower)
                == expected)
    }

    @Test func turningForeverAimsAFullTurnAheadAndPausesWhereItIs() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var motion = SunburstMotion()
        #expect(motion.start(at: start, period: 40, limit: nil) != nil)
        #expect(motion.angle == 360)
        // A second start while turning does nothing.
        #expect(motion.start(at: start, period: 40, limit: nil) == nil)

        motion.pause(at: start.addingTimeInterval(50), period: 40)  // 1¼ turns in.
        #expect(abs(motion.angle - 90) < 0.0001)
        #expect(motion.generation == 1)

        // Resumes from there.
        #expect(motion.start(at: start.addingTimeInterval(60), period: 40, limit: nil) != nil)
        #expect(abs(motion.angle - 450) < 0.0001)
    }

    @Test func aLimitedTurnStopsAfterItsTimeEvenAcrossPauses() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var motion = SunburstMotion()
        // 10 s at 40 s a turn: a quarter turn.
        #expect(motion.start(at: start, period: 40, limit: 10) != nil)
        #expect(abs(motion.angle - 90) < 0.0001)

        motion.pause(at: start.addingTimeInterval(4), period: 40)
        #expect(abs(motion.angle - 36) < 0.0001)

        // 6 s left.
        #expect(motion.start(at: start.addingTimeInterval(100), period: 40, limit: 10) != nil)
        #expect(abs(motion.angle - 90) < 0.0001)
        motion.pause(at: start.addingTimeInterval(200), period: 40)
        #expect(abs(motion.angle - 90) < 0.0001)

        // Nothing left to turn.
        #expect(motion.start(at: start.addingTimeInterval(300), period: 40, limit: 10) == nil)
        #expect(abs(motion.angle - 90) < 0.0001)
    }
}
