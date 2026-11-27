import Foundation
import StopCore
import Testing
@testable import StopSession

struct WireMessageTests {
    static let state = GameState(
        gameID: UUID(), hostID: UUID(), version: 3, language: .en,
        settings: GameSettings(categories: ["Name", "Animal"], stopsRequired: 1, allowGiveUp: true),
        players: [Player(id: UUID(), name: "Ana", presence: .present)], phase: .writing, rounds: [], usedLetters: ["A"])

    @Test func wireMessagesRoundTrip() throws {
        let bodies: [WireMessage.Body] = [
            .hello(playerID: UUID(), name: "Ana", gameID: UUID(), lastVersion: 4, explicitRejoin: true),
            .hello(playerID: UUID(), name: "Bo", gameID: nil, lastVersion: nil, explicitRejoin: false),
            .welcome(Self.state), .rejected(.versionMismatch), .rejected(.gameClosed), .rejected(.wrongGame),
            .intent(id: UUID(), .stop(answers: ["a", "b"])), .ack(id: UUID(), error: .wrongPhase),
            .ack(id: UUID(), error: nil), .snapshot(Self.state), .heartbeat, .goingAway, .bye,
        ]
        for body in bodies {
            let msg = WireMessage(body: body)
            #expect(msg.protocolVersion == currentProtocolVersion)
            #expect(try WireMessage.decode(msg.encoded()) == msg)
        }
    }

    @Test func decodeRejectsGarbage() {
        #expect(throws: (any Error).self) { try WireMessage.decode(Data("nope".utf8)) }
        #expect(throws: (any Error).self) { try WireMessage.decode(Data("{\"protocolVersion\":1}".utf8)) }
    }

    /// A hello from a build before `explicitRejoin` existed still decodes (as false), so the host can answer
    /// with a version check instead of dropping it.
    @Test func helloWithoutExplicitRejoinDecodesAsFalse() throws {
        let id = UUID()
        let json = #"{"protocolVersion":0,"body":{"hello":{"playerID":"\#(id.uuidString)","name":"Ana","#
            + #""lastVersion":3}}}"#
        let message = try WireMessage.decode(Data(json.utf8))
        #expect(message.protocolVersion == 0)
        #expect(message.body == .hello(playerID: id, name: "Ana", gameID: nil, lastVersion: 3, explicitRejoin: false))
    }
}
