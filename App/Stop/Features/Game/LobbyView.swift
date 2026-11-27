import StopCore
import StopSession
import SwiftUI

/// Before the first round: who's here, the rules and the categories. The host can tune the rules and start.
struct LobbyView: View {
    let client: any GameClient
    let state: GameState

    @Environment(\.reduceMotion) private var reduceMotion

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
            (client.isHost ? Text("Your game") : Text("\(hostName)’s game"))
                .font(Theme.Typography.display)
                .accessibilityAddTraits(.isHeader)
            Text(client.isHost
                 ? "Friends nearby can join now from “Join a game”."
                 : "You’re in! The game starts when \(hostName) is ready.")
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: Players

    private var playersCard: some View {
        LobbyCard(title: "Players (\(players.count))", systemImage: "person.2.fill") {
            FlowLayout(spacing: Theme.Spacing.s) {
                ForEach(players, id: \.id) { player in
                    PlayerChip(name: names[player.id] ?? player.name, presence: player.presence,
                               isHost: player.id == state.hostID, isYou: player.id == client.localPlayerID)
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
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .accessibilityIdentifier("lobbyStopsStepper")
                    Divider()
                    Toggle("Allow giving up", isOn: giveUpBinding)
                        .accessibilityIdentifier("lobbyAllowGiveUpToggle")
                } else {
                    LabeledContent("Stops to end a round") {
                        Text(stopsRequired, format: .number).monospacedDigit()
                    }
                    Divider()
                    LabeledContent("Giving up") {
                        Text(state.settings.allowGiveUp ? "Allowed" : "Not allowed")
                    }
                }
                Text(RulesText.footer(stopsRequired: stopsRequired,
                                      allowGiveUp: state.settings.allowGiveUp))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .font(Theme.Typography.body)
        }
    }

    private var stopsBinding: Binding<Int> {
        Binding(get: { stopsRequired }, set: { stops in
            client.send(.updateRoundSettings(stopsRequired: stops, allowGiveUp: state.settings.allowGiveUp))
        })
    }

    private var giveUpBinding: Binding<Bool> {
        Binding(get: { state.settings.allowGiveUp }, set: { allow in
            client.send(.updateRoundSettings(stopsRequired: state.settings.stopsRequired, allowGiveUp: allow))
        })
    }

    // MARK: Categories

    private var categoriesCard: some View {
        LobbyCard(title: "Categories (\(state.settings.categories.count))", systemImage: "square.grid.2x2.fill") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(Array(state.settings.categories.enumerated()), id: \.offset) { index, category in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text(index + 1, format: .number)
                            .font(Theme.Typography.caption.monospacedDigit())
                            .foregroundStyle(Theme.accent)
                            .frame(minWidth: 24, alignment: .trailing)
                        Text(verbatim: category)
                            .font(Theme.Typography.body)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Start

    @ViewBuilder private var bottomBar: some View {
        BottomActionBar {
            if client.isHost {
                Button { client.send(.startGame) } label: {
                    Label("Start game", systemImage: "play.fill")
                }
                .buttonStyle(.primary)
                .disabled(!canStart)
                .accessibilityHint(canStart ? Text("Starts the first round for everyone.")
                                            : Text("Waiting for players…"))
                .accessibilityIdentifier("startGameButton")
                if !canStart {
                    Text("Waiting for players…")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("Waiting for \(hostName) to start…")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A titled rounded card on the lobby's grouped background.
private struct LobbyCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.headline)
                .foregroundStyle(Color.primary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }
}

/// A player's name in a capsule. Away players are greyed out with "reconnecting…".
struct PlayerChip: View {
    let name: String
    let presence: Presence
    var isHost = false
    var isYou = false

    private var isAway: Bool { presence == .away }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            PlayerInitial(name: name, dimmed: isAway, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: name)
                        .font(Theme.Typography.body.weight(.semibold))
                    if isHost {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                    }
                }
                if isAway {
                    Text("reconnecting…")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                } else if isYou {
                    Text("you")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, Theme.Spacing.xs)
        .padding(.trailing, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs)
        .background(isAway ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(Theme.accent.opacity(isYou ? 0.2 : 0.1)),
                    in: .capsule)
        .overlay {
            if isYou { Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.5) }
        }
        .opacity(isAway ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(accessibilityDetails)
    }

    private var accessibilityDetails: Text {
        var parts: [String] = []
        if isHost { parts.append(String(localized: "Host")) }
        if isYou { parts.append(String(localized: "You")) }
        if isAway { parts.append(String(localized: "Reconnecting")) }
        return Text(verbatim: parts.formatted(.list(type: .and, width: .narrow)))
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            if !current.indices.isEmpty, current.width + spacing + itemWidth > width {
                rows.append(current)
                current = Row()
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + itemWidth
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
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

#Preview("Lobby – host alone") {
    let client = PreviewData.client(isHost: true, playerNames: [])
    NavigationStack {
        LobbyView(client: client, state: client.state!)
    }
}
