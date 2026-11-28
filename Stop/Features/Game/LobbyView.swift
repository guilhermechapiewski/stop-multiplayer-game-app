import StopCore
import StopSession
import SwiftUI

/// Before the first round: who's here, the rules and the categories. The host can tune the rules and start.
struct LobbyView: View {
    let client: any GameClient
    let state: GameState
    /// Local network access is off: as the host, nearby phones can't find this game.
    var networkDenied = false

    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.isPracticeGame) private var isPractice

    private var names: [PlayerID: String] { state.displayNames }
    private var hostName: String { names[state.hostID] ?? "" }
    /// Players still in the game, in join order.
    private var players: [Player] { state.activePlayers }
    private var presentCount: Int { state.players.count(where: { $0.presence == .present }) }
    private var canStart: Bool { presentCount >= 2 }
    /// Stops required, capped by the players in the lobby (the engine applies the same cap each round).
    private var stopsRequired: Int { max(1, min(state.settings.stopsRequired, players.count)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                if showsNetworkDenied { networkDeniedCard }
                playersCard
                rulesCard
                categoriesCard
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.l)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: state.players)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            title
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            subtitle
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var title: Text {
        if isPractice {
            Text("Practice")
        } else if client.isHost {
            Text("Your game")
        } else {
            Text("\(hostName)’s game")
        }
    }

    private var subtitle: Text {
        if isPractice {
            canStart ? Text("Your bots are ready. Start when you are.") : Text("Your bots are on their way…")
        } else if client.isHost {
            Text("Friends nearby can join now from “Join a game”.")
        } else {
            Text("You’re in! The game starts when \(hostName) is ready.")
        }
    }

    // MARK: Local network

    private var showsNetworkDenied: Bool { networkDenied && client.isHost && !isPractice }

    /// Nobody can find the game until Local Network access is back on.
    private var networkDeniedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label {
                Text("Allow Local Network access")
            } icon: {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(Theme.accent)
            }
            .font(Theme.Typography.headline)
            .accessibilityAddTraits(.isHeader)
            Text("Local Network access is off, so friends nearby can’t find your game. Turn it on in Settings.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.secondaryText)
            OpenSettingsButton()
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pieceCard()
        .accessibilityIdentifier("lobbyNetworkDenied")
    }

    // MARK: Players

    private var playersCard: some View {
        LobbyCard(title: "Players (\(players.count))", systemImage: "person.2.fill") {
            FlowLayout(spacing: Theme.Spacing.s) {
                ForEach(players, id: \.id) { player in
                    PlayerChip(name: names[player.id] ?? player.name, presence: player.presence,
                               // In practice there is nobody to host for: no crown.
                               isHost: !isPractice && player.id == state.hostID,
                               isYou: player.id == client.localPlayerID,
                               isBot: isPractice && player.id != client.localPlayerID)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Rules

    private var rulesCard: some View {
        LobbyCard(title: "Rules", systemImage: "list.bullet.clipboard.fill") {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if client.isHost {
                    Stepper(value: stopsBinding, in: 1...max(1, players.count)) {
                        LabeledContent("Stops to end a round") {
                            Text(stopsRequired, format: .number)
                                .font(Theme.Typography.headline)
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                        }
                    }
                    .accessibilityIdentifier("lobbyStopsStepper")
                    Divider()
                    Toggle("Allow giving up", isOn: giveUpBinding)
                        .accessibilityIdentifier("lobbyAllowGiveUpToggle")
                    Divider()
                    SilentModeToggle(isOn: silentBinding, identifier: "lobbySilentModeToggle")
                } else {
                    LabeledContent("Stops to end a round") {
                        Text(stopsRequired, format: .number).monospacedDigit()
                    }
                    Divider()
                    LabeledContent("Giving up") {
                        Text(state.settings.allowGiveUp ? "Allowed" : "Not allowed")
                    }
                    Divider()
                    LabeledContent("Scoring") {
                        Text(state.settings.silentScoring ? "Silent" : "Read aloud")
                    }
                    .accessibilityIdentifier("lobbyScoringMode")
                }
                Text(RulesText.footer(stopsRequired: stopsRequired,
                                      allowGiveUp: state.settings.allowGiveUp))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
                // The host has the switch and its ⓘ; the others get the mode explained here.
                if !client.isHost {
                    Text(RulesText.scoring(silent: state.settings.silentScoring))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.text)
        }
    }

    private var stopsBinding: Binding<Int> {
        Binding(get: { stopsRequired }, set: { stops in
            client.send(.updateRoundSettings(stopsRequired: stops, allowGiveUp: state.settings.allowGiveUp,
                                             silentScoring: state.settings.silentScoring))
        })
    }

    private var giveUpBinding: Binding<Bool> {
        Binding(get: { state.settings.allowGiveUp }, set: { allow in
            client.send(.updateRoundSettings(stopsRequired: state.settings.stopsRequired, allowGiveUp: allow,
                                             silentScoring: state.settings.silentScoring))
        })
    }

    private var silentBinding: Binding<Bool> {
        Binding(get: { state.settings.silentScoring }, set: { silent in
            client.send(.updateRoundSettings(stopsRequired: state.settings.stopsRequired,
                                             allowGiveUp: state.settings.allowGiveUp, silentScoring: silent))
        })
    }

    // MARK: Categories

    private var categoriesCard: some View {
        LobbyCard(title: "Categories (\(state.settings.categories.count))", systemImage: "square.grid.2x2.fill") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(Array(state.settings.categories.enumerated()), id: \.offset) { index, category in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text(index + 1, format: .number)
                            .font(Theme.Typography.label.monospacedDigit())
                            .foregroundStyle(Theme.accent)
                            .frame(minWidth: 24, alignment: .trailing)
                        Text(verbatim: category)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.text)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Start

    private var startHint: Text {
        if !canStart {
            Text("Waiting for players…")
        } else if isPractice {
            Text("Starts the first round against your bots.")
        } else {
            Text("Starts the first round for everyone.")
        }
    }

    @ViewBuilder private var bottomBar: some View {
        BottomActionBar {
            if client.isHost {
                Button { client.send(.startGame) } label: {
                    Label("Start game", systemImage: "play.fill")
                }
                .buttonStyle(.primary)
                .disabled(!canStart)
                .accessibilityHint(startHint)
                .accessibilityIdentifier("startGameButton")
                if !canStart {
                    Text("Waiting for players…")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("Waiting for \(hostName) to start…")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A card with its title on a speech bubble, on the lobby's cream page.
private struct LobbyCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            BubbleLabel(title, systemImage: systemImage)
            content
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pieceCard()
    }
}

#Preview("Lobby – host") {
    let client = PreviewData.client(isHost: true)
    NavigationStack {
        LobbyView(client: client, state: client.state!)
    }
}

#Preview("Lobby – guest") {
    let client = PreviewData.client(isHost: false)
    NavigationStack {
        LobbyView(client: client, state: client.state!)
    }
}

#Preview("Lobby – host, no local network") {
    let client = PreviewData.client(isHost: true)
    NavigationStack {
        LobbyView(client: client, state: client.state!, networkDenied: true)
    }
}

#Preview("Lobby – host alone") {
    let client = PreviewData.client(isHost: true, playerNames: [])
    NavigationStack {
        LobbyView(client: client, state: client.state!)
    }
}
