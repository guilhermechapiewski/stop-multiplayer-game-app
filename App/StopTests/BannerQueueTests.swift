import Foundation
import StopCore
import StopTestSupport
import Testing
@testable import Stop

@MainActor
struct BannerQueueTests {
    let ana = UUID()
    let bia = UUID()
    let clock = TestClock()

    var names: [PlayerID: String] { [ana: "Ana", bia: "Bia"] }

    func makeQueue() -> (BannerQueue, AsyncStream<PresenceChange>.Continuation) {
        let queue = BannerQueue(clock: clock)
        let (stream, continuation) = AsyncStream.makeStream(of: PresenceChange.self)
        let names = names
        queue.consume(stream, names: { names })
        return (queue, continuation)
    }

    @Test func bannerTextForEachKind() {
        let cases: [(PresenceChange.Kind, String, Banner.Style)] = [
            (.wentAway, "Ana left the app", .away),
            (.returned, "Ana is back", .back),
            (.left, "Ana left the game", .left),
            (.removed, "Ana was removed", .removed),
        ]
        for (kind, text, style) in cases {
            let banner = Banner(change: PresenceChange(playerID: ana, kind: kind), name: "Ana")
            #expect(banner.text == text)
            #expect(banner.style == style)
        }
    }

    @Test func bannersCollapsePerPlayer() async throws {
        let (queue, events) = makeQueue()
        events.yield(PresenceChange(playerID: bia, kind: .wentAway))
        try await waitUntil { queue.current?.text == "Bia left the app" }

        // Ana's two changes arrive while Bia's banner shows: only the latest is kept.
        events.yield(PresenceChange(playerID: ana, kind: .wentAway))
        events.yield(PresenceChange(playerID: ana, kind: .returned))
        try await waitUntil { queue.pendingCount == 1 }

        await clock.advance(by: BannerQueue.displayDuration)
        try await waitUntil { queue.current?.text == "Ana is back" }
        #expect(queue.pendingCount == 0)
    }

    @Test func newsAboutTheShowingPlayerReplacesTheBanner() async throws {
        let (queue, events) = makeQueue()
        events.yield(PresenceChange(playerID: ana, kind: .wentAway))
        try await waitUntil { queue.current?.text == "Ana left the app" }
        events.yield(PresenceChange(playerID: ana, kind: .returned))
        try await waitUntil { queue.current?.text == "Ana is back" }
        #expect(queue.pendingCount == 0)
    }

    @Test func bannerExpiresAfterThreeSeconds() async throws {
        let (queue, events) = makeQueue()
        events.yield(PresenceChange(playerID: ana, kind: .left))
        try await waitUntil { queue.current != nil && clock.sleeperCount == 1 }

        await clock.advance(by: .milliseconds(2900))
        #expect(queue.current?.text == "Ana left the game")
        await clock.advance(by: .milliseconds(100))
        try await waitUntil { queue.current == nil }
    }

    @Test func playersWithoutANameAreSkipped() async throws {
        let (queue, events) = makeQueue()
        events.yield(PresenceChange(playerID: UUID(), kind: .wentAway))
        events.yield(PresenceChange(playerID: bia, kind: .removed))
        try await waitUntil { queue.current != nil }
        #expect(queue.current?.text == "Bia was removed")
    }

    @Test func stopClearsTheBanner() async throws {
        let (queue, events) = makeQueue()
        events.yield(PresenceChange(playerID: ana, kind: .wentAway))
        try await waitUntil { queue.current != nil }
        queue.stop()
        #expect(queue.current == nil)
    }
}
