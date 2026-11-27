/// Elapsed time on an injected clock since the stopwatch was started.
struct Stopwatch: Sendable {
    private let read: @Sendable () -> Duration

    init(_ clock: any Clock<Duration>) {
        read = Self.reader(clock)
    }

    var elapsed: Duration { read() }

    private static func reader<C: Clock>(_ clock: C) -> @Sendable () -> Duration where C.Duration == Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }
}
