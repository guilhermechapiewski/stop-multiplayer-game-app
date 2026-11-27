import Foundation
import Testing
@testable import StopNetworking

@Test func frameRoundTrip() throws {
    let payload = Data("hello, stop".utf8)
    let frame = FrameEncoder.encode(payload)
    #expect(frame.count == 4 + payload.count)
    #expect(Array(frame.prefix(4)) == [0, 0, 0, UInt8(payload.count)])
    var decoder = FrameDecoder()
    #expect(try decoder.append(frame) == [payload])
}

@Test func emptyPayloadRoundTrips() throws {
    var decoder = FrameDecoder()
    #expect(try decoder.append(FrameEncoder.encode(Data())) == [Data()])
}

@Test func decoderHandlesSplitAndCoalescedChunks() throws {
    let payloads = [Data("one".utf8), Data(), Data(repeating: 0xAB, count: 300)]
    let stream = payloads.map(FrameEncoder.encode).reduce(Data(), +)

    var byteByByte = FrameDecoder()
    var collected: [Data] = []
    for byte in stream {
        collected += try byteByByte.append(Data([byte]))
    }
    #expect(collected == payloads)

    var allAtOnce = FrameDecoder()
    #expect(try allAtOnce.append(stream) == payloads)
}

@Test func decoderRejectsOversizedFrame() {
    var decoder = FrameDecoder(maxFrameSize: 8)
    let frame = FrameEncoder.encode(Data(repeating: 1, count: 9))
    // The header alone is enough to reject: no need to buffer the payload.
    #expect(throws: FrameError.tooLarge(9)) {
        _ = try decoder.append(frame.prefix(4))
    }
}

@Test func decoderAcceptsFrameAtMaxSize() throws {
    var decoder = FrameDecoder(maxFrameSize: 8)
    let payload = Data(repeating: 1, count: 8)
    #expect(try decoder.append(FrameEncoder.encode(payload)) == [payload])
}
