import Foundation

public enum FrameError: Error, Equatable, Sendable {
    /// The frame header announced a payload of this many bytes, above the decoder's limit.
    case tooLarge(Int)
}

/// Frames are a 4-byte big-endian payload length followed by the payload.
public struct FrameEncoder {
    public static func encode(_ payload: Data) -> Data {
        var frame = Data(capacity: 4 + payload.count)
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }
}

/// Reassembles frames from arbitrarily split or coalesced chunks of a byte stream.
public struct FrameDecoder {
    private let maxFrameSize: Int
    private var buffer = Data()

    public init(maxFrameSize: Int = 1_048_576) {
        self.maxFrameSize = maxFrameSize
    }

    /// Returns every frame completed by `data`, in order. Throws `FrameError.tooLarge` as soon as a header
    /// announces an oversized payload; the stream is then unusable and the connection should be closed.
    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        // Consume frames by advancing a read offset, then drop the consumed prefix once, so a chunk carrying
        // many frames costs one compaction instead of one per frame.
        var offset = buffer.startIndex
        defer { buffer.removeSubrange(buffer.startIndex..<offset) }
        while buffer.endIndex - offset >= 4 {
            let length = buffer[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            guard length <= maxFrameSize else { throw FrameError.tooLarge(length) }
            guard buffer.endIndex - offset >= 4 + length else { break }
            frames.append(Data(buffer[offset + 4..<offset + 4 + length]))
            offset += 4 + length
        }
        return frames
    }
}
