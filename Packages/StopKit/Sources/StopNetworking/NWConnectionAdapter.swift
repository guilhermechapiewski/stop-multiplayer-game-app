import Foundation
import Network
import Synchronization

/// A `Connection` over an `NWConnection` carrying length-prefixed frames (`FrameEncoder`/`FrameDecoder`) on TCP.
///
/// Mirrors `InMemoryNetwork`'s connection semantics: `.ready` once the TCP connection is up, then messages in
/// order, then `.closed` exactly once (on `close()`, peer EOF, failure, cancellation, an undecodable stream or a
/// connect that cannot proceed), after which the stream finishes and `send` is a no-op. Sends before `start()` are
/// dropped. `close()` is graceful: frames already sent reach the peer before its `.closed`.
///
/// All state lives in one `Mutex`, and every event is yielded while holding it, so `.closed` can never be
/// followed by a message. Network.framework callbacks run on a private serial queue.
final class NWConnectionAdapter: Connection {
    let id = UUID()
    let events: AsyncStream<ConnectionEvent>
    private let continuation: AsyncStream<ConnectionEvent>.Continuation
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "stop.net.connection")
    private let state = Mutex(State())

    private struct State {
        var started = false
        var ready = false
        /// `.closed` has been emitted.
        var closed = false
        var decoder = FrameDecoder()
    }

    /// How long a graceful close waits for queued frames to be handed to the stack before cancelling anyway.
    private static let closeFlushTimeout: DispatchTimeInterval = .seconds(2)

    init(_ connection: NWConnection) {
        self.connection = connection
        (events, continuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
    }

    deinit {
        abort()
    }

    func start() {
        let shouldStart = state.withLock { state in
            guard !state.started, !state.closed else { return false }
            state.started = true
            return true
        }
        guard shouldStart else { return }
        // Weak captures: the adapter owns the connection; if the adapter goes away, deinit cancels it.
        connection.stateUpdateHandler = { [weak self] in self?.handle($0) }
        connection.start(queue: queue)
    }

    func send(_ data: Data) {
        state.withLock { state in
            guard state.started, !state.closed else { return }
            // Fire-and-forget (the session acks what matters). Enqueued under the lock so concurrent sends and
            // `close()`'s final FIN are ordered.
            connection.send(content: FrameEncoder.encode(data), completion: .contentProcessed { [weak self] error in
                if error != nil { self?.abort() }
            })
        }
    }

    func close() {
        state.withLock { state in
            guard markClosed(&state) else { return }
            guard state.ready else {
                connection.cancel()
                return
            }
            // FIN after everything already queued, then cancel; the timeout bounds a stalled flush.
            let connection = connection
            connection.send(
                content: nil, contentContext: .finalMessage, isComplete: true,
                completion: .contentProcessed { _ in connection.cancel() })
            queue.asyncAfter(deadline: .now() + Self.closeFlushTimeout) { connection.cancel() }
        }
    }

    // MARK: Private

    private func handle(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            let becameReady = state.withLock { state in
                guard !state.closed, !state.ready else { return false }
                state.ready = true
                continuation.yield(.ready)
                return true
            }
            if becameReady { receiveNext() }
        case .waiting, .failed, .cancelled:
            // `.waiting` means the connect cannot proceed now (refused, no route): report it as closed promptly
            // and let the session's reconnect backoff retry, rather than leaving the attempt hanging.
            abort()
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty, !deliver(data) {
                abort()
            } else if isComplete || error != nil {
                abort()  // EOF from the peer, or a failed read
            } else {
                receiveNext()
            }
        }
    }

    /// Feeds bytes to the decoder and yields completed frames. False if the stream is corrupt (oversized frame).
    private func deliver(_ data: Data) -> Bool {
        state.withLock { state in
            guard !state.closed else { return true }
            do {
                for frame in try state.decoder.append(data) {
                    continuation.yield(.message(frame))
                }
                return true
            } catch {
                return false
            }
        }
    }

    /// Emits `.closed` (once) and cancels the connection immediately.
    private func abort() {
        state.withLock { state in
            _ = markClosed(&state)
        }
        connection.cancel()
    }

    /// Emits `.closed` and finishes the stream unless already done. Call with the lock held.
    private func markClosed(_ state: inout State) -> Bool {
        guard !state.closed else { return false }
        state.closed = true
        continuation.yield(.closed)
        continuation.finish()
        return true
    }
}

extension NWConnectionAdapter {
    /// TCP over infrastructure Wi-Fi and peer-to-peer Wi-Fi. Keepalive is off (the session heartbeats) and
    /// Nagle is off so small game messages go out at once. A fresh instance per use: `NWParameters` is mutable.
    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = false
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}
