public struct SessionTiming: Sendable {
    public var heartbeat: Duration = .seconds(1)
    public var awayAfter: Duration = .seconds(3)
    public var tick: Duration = .seconds(1)
    public var hostGoneAfter: Duration = .seconds(120)
    /// A client drops a connection that has been silent (or not welcomed) this long and reconnects.
    public var reconnectAfterSilence: Duration = .seconds(6)
    public var reconnectBackoff: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2)]
    public var draftDebounce: Duration = .milliseconds(300)
    /// A host whose listener failed in the foreground restarts it after these delays (the last one repeats).
    public var listenerRestartBackoff: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(10)]
    public init() {}
    public static let standard = SessionTiming()
}
