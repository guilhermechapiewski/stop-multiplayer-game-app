import StopTestSupport
import Synchronization
import Testing

@MainActor
struct TestClockTests {
    /// Spins (yielding) until the clock has `n` sleepers; fails the test instead of hanging.
    private func waitForSleepers(_ clock: TestClock, _ n: Int) async {
        for _ in 0..<10_000 {
            if clock.sleeperCount == n { return }
            await Task.yield()
        }
        Issue.record("expected \(n) sleepers, have \(clock.sleeperCount)")
    }

    @Test func testClockResumesSleepersInOrder() async {
        let clock = TestClock()
        var order: [Int] = []
        let t3 = Task { @MainActor in try? await clock.sleep(for: .seconds(3)); order.append(3) }
        let t1 = Task { @MainActor in try? await clock.sleep(for: .seconds(1)); order.append(1) }
        let t2 = Task { @MainActor in try? await clock.sleep(for: .seconds(2)); order.append(2) }
        await waitForSleepers(clock, 3)
        await clock.advance(by: .milliseconds(500))
        #expect(order.isEmpty)
        await clock.advance(by: .seconds(5))
        #expect(order == [1, 2, 3])
        _ = (await t1.value, await t2.value, await t3.value)
    }

    /// Lets a test wait for specific sleepers rather than any `n`, which other timers could make up.
    @Test func countsSleepersByDeadline() async {
        let clock = TestClock()
        let tasks = [Task { try? await clock.sleep(for: .seconds(5)) }, Task { try? await clock.sleep(for: .seconds(1)) },
                     Task { try? await clock.sleep(for: .seconds(5)) }]
        await waitForSleepers(clock, 3)
        #expect(clock.sleeperCount(dueAt: clock.now.advanced(by: .seconds(5))) == 2)
        #expect(clock.sleeperCount(dueAt: clock.now.advanced(by: .seconds(1))) == 1)
        #expect(clock.sleeperCount(dueAt: clock.now.advanced(by: .seconds(2))) == 0)
        await clock.advance(by: .seconds(5))
        for task in tasks { await task.value }
    }

    @Test func cancellationThrowsAndRemovesSleeper() async {
        let clock = TestClock()
        let t = Task { do { try await clock.sleep(for: .seconds(10)); return false } catch { return error is CancellationError } }
        await waitForSleepers(clock, 1)
        t.cancel()
        #expect(await t.value)
        #expect(clock.sleeperCount == 0)
    }

    @Test func pastDeadlineReturnsImmediately() async throws {
        let clock = TestClock()
        await clock.advance(by: .seconds(5))
        try await clock.sleep(until: TestClock.Instant(offset: .seconds(1)))
        try await clock.sleep(for: .zero)
        #expect(clock.sleeperCount == 0)
    }

    @Test func cancelledBeforeSleepThrows() async {
        let clock = TestClock()
        let t = Task { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            do { try await clock.sleep(for: .seconds(10)); return false } catch { return error is CancellationError }
        }
        t.cancel()
        #expect(await t.value)
        #expect(clock.sleeperCount == 0)
    }
}
