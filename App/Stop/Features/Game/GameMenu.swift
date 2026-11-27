import StopCore
import StopSession
import SwiftUI

/// The in-game toolbar menu. Everyone can leave; the host can also end the game, force-end a round that's
/// being written, and remove players. Every action asks for confirmation.
struct GameMenu: View {
    let client: any GameClient
    let state: GameState?
    let onLeave: () -> Void

    private enum Confirmation: Identifiable {
        case leave, endGame, forceEndRound, remove(PlayerID)

        var id: String {
            switch self {
            case .leave: "leave"
            case .endGame: "endGame"
            case .forceEndRound: "forceEndRound"
            case .remove(let id): "remove-\(id)"
            }
        }
    }

    @State private var confirmation: Confirmation?
    @State private var showsRemoveSheet = false
    /// Picked in the sheet; confirmed once the sheet has gone (an alert can't show over a closing sheet).
    @State private var pickedForRemoval: PlayerID?

    private var names: [PlayerID: String] { state?.displayNames ?? [:] }
    private var isWriting: Bool { state?.phase == .writing }
    private var isOver: Bool { state?.phase == .gameOver }
    /// Players the host may remove: everyone else still in the game.
    private var removable: [Player] {
        guard let state else { return [] }
        return state.players.filter { $0.id != state.hostID && $0.presence.isActive }
    }

    var body: some View {
        Menu {
            if client.isHost && !isOver {
                Section {
                    if isWriting {
                        Button("Force end round", systemImage: "forward.end.fill") { confirmation = .forceEndRound }
                            .accessibilityIdentifier("forceEndRoundMenuItem")
                    }
                    Button("Remove player…", systemImage: "person.badge.minus") { showsRemoveSheet = true }
                        .disabled(removable.isEmpty)
                        .accessibilityIdentifier("removePlayerMenuItem")
                    Button("End game", systemImage: "flag.checkered") { confirmation = .endGame }
                        .accessibilityIdentifier("endGameMenuItem")
                }
            }
            Button("Leave game", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                confirmation = .leave
            }
            .accessibilityIdentifier("leaveGameMenuItem")
        } label: {
            Label("Game menu", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("gameMenu")
        .alert(alertTitle, isPresented: isConfirming, presenting: confirmation) { pending in
            Button(confirmButtonTitle(pending), role: .destructive) { perform(pending) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(message(pending))
        }
        .sheet(isPresented: $showsRemoveSheet, onDismiss: {
            if let id = pickedForRemoval { confirmation = .remove(id) }
            pickedForRemoval = nil
        }) {
            RemovePlayerSheet(players: removable, names: names) { id in
                pickedForRemoval = id
                showsRemoveSheet = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Confirmations

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var alertTitle: Text {
        switch confirmation {
        case .leave: client.isHost ? Text("End the game for everyone?") : Text("Leave the game?")
        case .endGame: Text("End the game?")
        case .forceEndRound: Text("End this round now?")
        case .remove(let id): Text("Remove \(names[id] ?? "")?")
        case nil: Text(verbatim: "")
        }
    }

    private func message(_ pending: Confirmation) -> LocalizedStringKey {
        switch pending {
        case .leave:
            client.isHost
                ? "You’re the host, so leaving ends the game on every phone."
                : "Your points so far stay in the standings. You can rejoin while the game is on."
        case .endGame:
            "Everyone goes to the final standings."
        case .forceEndRound:
            "Everyone’s answers are locked as they are, even for players who haven’t stopped."
        case .remove(let id):
            "\(names[id] ?? "") leaves the game. Their points so far stay in the standings."
        }
    }

    private func confirmButtonTitle(_ pending: Confirmation) -> LocalizedStringKey {
        switch pending {
        case .leave: client.isHost ? "End game" : "Leave"
        case .endGame: "End game"
        case .forceEndRound: "End round"
        case .remove: "Remove"
        }
    }

    private func perform(_ pending: Confirmation) {
        switch pending {
        case .leave: onLeave()
        case .endGame: client.send(.endGame)
        case .forceEndRound: client.send(.forceEndRound)
        case .remove(let id): client.send(.removePlayer(id))
        }
    }
}

/// Host-only: pick a player to remove.
private struct RemovePlayerSheet: View {
    let players: [Player]
    let names: [PlayerID: String]
    let onPick: (PlayerID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(players, id: \.id) { player in
                let name = names[player.id] ?? player.name
                Button { onPick(player.id) } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        PlayerInitial(name: name, dimmed: player.presence == .away)
                        VStack(alignment: .leading) {
                            Text(verbatim: name)
                                .font(Theme.Typography.body.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            if player.presence == .away {
                                Text("reconnecting…")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "person.badge.minus")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityHint("Asks to confirm removing this player.")
            }
            .navigationTitle("Remove a player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fontDesign(.rounded)
    }
}

#Preview("Game menu – host") {
    let client = PreviewData.client(isHost: true)
    NavigationStack {
        Color.clear
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    GameMenu(client: client, state: client.state, onLeave: {})
                }
            }
    }
}
