import StopSession
import StopTestSupport
import Testing
@testable import Stop

@MainActor
struct HostAwayGateTests {
    let clock = TestClock()

    @Test func showsOnlyAfterTheGrace() async throws {
        let gate = HostAwayGate(clock: clock)
        gate.update(.away)
        try await waitUntil { clock.sleeperCount == 1 }

        await clock.advance(by: .milliseconds(1400))
        for _ in 0..<20 { await Task.yield() }
        #expect(!gate.isShowing)

        await clock.advance(by: .milliseconds(100))
        try await waitUntil { gate.isShowing }
    }

    @Test func aQuickReturnNeverShows() async throws {
        // This phone coming back from the background: the host looks away for a moment, then it's connected.
        let gate = HostAwayGate(clock: clock)
        gate.update(.away)
        try await waitUntil { clock.sleeperCount == 1 }
        await clock.advance(by: .milliseconds(500))
        gate.update(.connected)

        await clock.advance(by: .seconds(2))
        for _ in 0..<20 { await Task.yield() }
        #expect(!gate.isShowing)
    }

    @Test func mayBeGoneShowsAtOnceAndConnectedHides() {
        let gate = HostAwayGate(clock: clock)
        gate.update(.mayBeGone)
        #expect(gate.isShowing)
        gate.update(.away)
        #expect(gate.isShowing)
        gate.update(.connected)
        #expect(!gate.isShowing)
    }
}
