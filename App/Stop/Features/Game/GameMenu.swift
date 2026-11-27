import StopCore
import StopSession
import SwiftUI

/// The in-game toolbar menu. Everyone can leave; the host can also end the game, force-end a round that's
/// being written, and remove players. In practice the player can force-end a round or end the practice (to the
/// final standings mid-game, else to Home). Every action asks for confirmation.
struct GameMenu: View {
    let client: any GameClient
    let state: GameState?
    let onLeave: () -> Void

    @Environment(\.isPracticeGame) private var isPractice

    private enum Confirmation: Identifiable {
        case leave, endGame, forceEndRound, remove(PlayerID), endPractice

        var id: String {
            switch self {
            case .leave: "leave"
            case .endGame: "endGame"
            case .endPractice: "endPractice"
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
    private var endingPracticeShowsStandings: Bool { Self.endingPracticeShowsStandings(phase: state?.phase) }
    /// The host leaving before game over ends the game on every phone.
    private var endsGameForEveryone: Bool { client.isHost && !isOver }
    /// Players the host may remove: everyone else still in the game.
    private var removable: [Player] {
        guard let state else { return [] }
        return state.players.filter { $0.id != state.hostID && $0.presence.isActive }
    }

    var body: some View {
        Menu {
            if isPractice {
                practiceItems
            } else {
                gameItems
            }
        } label: {
            Label("Game menu", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("gameMenu")
        .alert(alertTitle, isPresented: isConfirming, presenting: confirmation) { pending in
            Button(confirmButtonTitle(pending), role: .destructive) { perform(pending) }
                .accessibilityIdentifier("confirmMenuActionButton")
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(message(pending))
        }
        .sheet(isPresented: $showsRemoveSheet, onDismiss: {
            if let id = pickedForRemoval { confirmation = .remove(id) }
            pickedForRemoval = nil
        }) {
            RemovePlayerSheet(players: removable, names: names, me: client.localPlayerID) { id in
                pickedForRemoval = id
                showsRemoveSheet = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private var gameItems: some View {
        if client.isHost && !isOver {
            Section {
                if isWriting { forceEndRoundItem }
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
    }

    @ViewBuilder private var practiceItems: some View {
        if isWriting { forceEndRoundItem }
        Button("End practice", systemImage: "flag.checkered", role: .destructive) { confirmation = .endPractice }
            .accessibilityIdentifier("endPracticeMenuItem")
    }

    private var forceEndRoundItem: some View {
        Button("Force end round", systemImage: "forward.end.fill") { confirmation = .forceEndRound }
            .accessibilityIdentifier("forceEndRoundMenuItem")
    }

    // MARK: Confirmations

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var alertTitle: Text {
        switch confirmation {
        case .leave: endsGameForEveryone ? Text("End the game for everyone?") : Text("Leave the game?")
        case .endGame: Text("End the game?")
        case .endPractice: Text("End the practice?")
        case .forceEndRound: Text("End this round now?")
        case .remove(let id): Text("Remove \(names[id] ?? "")?")
        case nil: Text(verbatim: "")
        }
    }

    private func message(_ pending: Confirmation) -> LocalizedStringKey {
        switch pending {
        case .leave:
            if endsGameForEveryone {
                "You’re the host, so leaving ends the game on every phone."
            } else if isOver {
                "You’ll go back to the start screen."
            } else {
                "Your points so far stay in the standings."
            }
        case .endGame:
            "Everyone goes to the final standings."
        case .endPractice:
            endingPracticeShowsStandings ? "You’ll see the final standings." : "You’ll go back to the start screen."
        case .forceEndRound:
            "Everyone’s answers are locked as they are, even for players who haven’t stopped."
        case .remove(let id):
            "\(names[id] ?? "") leaves the game. Their points so far stay in the standings."
        }
    }

    private func confirmButtonTitle(_ pending: Confirmation) -> LocalizedStringKey {
        switch pending {
        case .leave: endsGameForEveryone ? "End game" : "Leave"
        case .endGame: "End game"
        case .endPractice: "End practice"
        case .forceEndRound: "End round"
        case .remove: "Remove"
        }
    }

    private func perform(_ pending: Confirmation) {
        switch pending {
        case .leave: onLeave()
        case .endGame: client.send(.endGame)
        case .endPractice: Self.endPractice(client: client, onLeave: onLeave)
        case .forceEndRound: client.send(.forceEndRound)
        case .remove(let id): client.send(.removePlayer(id))
        }
    }

    // MARK: Practice

    /// Ending a practice once rounds are under way shows its final standings; in the lobby, at game over or
    /// before any state it just closes.
    static func endingPracticeShowsStandings(phase: Phase?) -> Bool {
        guard let phase else { return false }
        return phase != .lobby && phase != .gameOver
    }

    /// "End practice": the host's end game (to the final standings), or straight Home when there are none.
    static func endPractice(client: any GameClient, onLeave: () -> Void) {
        if endingPracticeShowsStandings(phase: client.state?.phase) {
            client.send(.endGame)
        } else {
            onLeave()
        }
    }
}

/// Host-only: pick a player to remove.
private struct RemovePlayerSheet: View {
    let players: [Player]
    let names: [PlayerID: String]
    let me: PlayerID
    let onPick: (PlayerID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(players, id: \.id) { player in
                let name = names[player.id] ?? player.name
                Button { onPick(player.id) } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        PlayerInitial(name: name, dimmed: player.presence == .away, isYou: player.id == me)
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

#Preview("Game menu – practice") {
    let client = PreviewData.client(isHost: true, phase: .writing)
    NavigationStack {
        Color.clear
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    GameMenu(client: client, state: client.state, onLeave: {})
                }
            }
    }
    .environment(\.isPracticeGame, true)
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
