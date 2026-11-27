public struct SessionTiming: Sendable {
    public var heartbeat: Duration = .seconds(1)
    public var awayAfter: Duration = .seconds(3)
    public var tick: Duration = .seconds(1)
    public var hostGoneAfter: Duration = .seconds(120)
    public var reconnectBackoff: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2)]
    public var draftDebounce: Duration = .milliseconds(300)
    public init() {}
    public static let standard = SessionTiming()
}
