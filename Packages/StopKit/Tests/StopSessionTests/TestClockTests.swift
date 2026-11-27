import StopTestSupport
import Synchronization
import Testing

struct TestClockTests {
    @Test func testClockResumesSleepersInOrder() async {
        let clock = TestClock()
        let order = Mutex<[Int]>([])
        let t3 = Task { try? await clock.sleep(for: .seconds(3)); order.withLock { $0.append(3) } }
        let t1 = Task { try? await clock.sleep(for: .seconds(1)); order.withLock { $0.append(1) } }
        let t2 = Task { try? await clock.sleep(for: .seconds(2)); order.withLock { $0.append(2) } }
        while !(await sleeperCount(clock, expecting: 3)) { await Task.yield() }
        await clock.advance(by: .milliseconds(500))
        #expect(order.withLock { $0 }.isEmpty)
        await clock.advance(by: .seconds(5))
        #expect(order.withLock { $0 } == [1, 2, 3])
        _ = (await t1.value, await t2.value, await t3.value)
    }

    @Test func cancellationThrowsAndRemovesSleeper() async {
        let clock = TestClock()
        let t = Task { do { try await clock.sleep(for: .seconds(10)); return false } catch { return error is CancellationError } }
        while !(await sleeperCount(clock, expecting: 1)) { await Task.yield() }
        t.cancel()
        #expect(await t.value)
        #expect(await sleeperCount(clock, expecting: 0))
    }

    private func sleeperCount(_ clock: TestClock, expecting n: Int) async -> Bool { clock.sleeperCount == n }
}
