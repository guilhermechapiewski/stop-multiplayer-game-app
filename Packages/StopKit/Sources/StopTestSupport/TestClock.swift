import Synchronization

/// A manually advanced clock. `sleep(until:)` suspends until `advance(by:)` passes the deadline.
public final class TestClock: Clock, @unchecked Sendable {
    public typealias Duration = Swift.Duration

    public struct Instant: InstantProtocol, Sendable {
        public var offset: Swift.Duration
        public init(offset: Swift.Duration = .zero) { self.offset = offset }
        public func advanced(by duration: Swift.Duration) -> Instant { Instant(offset: offset + duration) }
        public func duration(to other: Instant) -> Swift.Duration { other.offset - offset }
        public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant()
        var nextID = 0
        var sleepers: [Sleeper] = []
        var cancelled: Set<Int> = []
    }

    /// Heuristic yield counts so woken tasks get to run; not a guarantee for deep async chains.
    private static let yieldsPerSleeper = 10
    private static let yieldsAfterAdvance = 3

    private let state = Mutex(State())

    public init() {}

    public var now: Instant { state.withLock { $0.now } }
    public var sleeperCount: Int { state.withLock { $0.sleepers.count } }
    public var minimumResolution: Swift.Duration { .zero }

    public func sleep(until deadline: Instant, tolerance: Swift.Duration? = nil) async throws {
        let id = state.withLock { s -> Int in s.nextID += 1; return s.nextID }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                enum Outcome { case wait, resume, cancel }
                let outcome = state.withLock { s -> Outcome in
                    if s.cancelled.remove(id) != nil { return .cancel }
                    if deadline <= s.now { return .resume }
                    s.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: c))
                    return .wait
                }
                switch outcome {
                case .wait: break
                case .resume: c.resume()
                case .cancel: c.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let sleeper = state.withLock { s -> Sleeper? in
                if let i = s.sleepers.firstIndex(where: { $0.id == id }) { return s.sleepers.remove(at: i) }
                s.cancelled.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward, resuming due sleepers in deadline order and yielding after each so woken tasks run.
    public func advance(by duration: Swift.Duration) async {
        let target = state.withLock { $0.now.advanced(by: duration) }
        while true {
            let next = state.withLock { s -> Sleeper? in
                let due = s.sleepers.enumerated().filter { $0.element.deadline <= target }
                    .min { ($0.element.deadline, $0.element.id) < ($1.element.deadline, $1.element.id) }
                guard let due else { return nil }
                s.sleepers.remove(at: due.offset)
                if due.element.deadline > s.now { s.now = due.element.deadline }
                return due.element
            }
            guard let next else { break }
            next.continuation.resume()
            for _ in 0..<Self.yieldsPerSleeper { await Task.yield() }
        }
        state.withLock { if target > $0.now { $0.now = target } }
        for _ in 0..<Self.yieldsAfterAdvance { await Task.yield() }
    }
}
