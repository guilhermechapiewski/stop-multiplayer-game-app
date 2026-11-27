import StopNetworking
import SwiftUI
import UIKit

/// Games hosted nearby, live. Tapping a joinable one joins it; tapping one in progress rejoins it (the host
/// takes back players it knows and turns anyone else away).
struct JoinView: View {
    let model: AppModel

    @State private var join: JoinModel
    @Environment(\.scenePhase) private var scenePhase

    init(model: AppModel) {
        self.model = model
        _join = State(initialValue: model.makeJoinModel())
    }

    var body: some View {
        NavigationStack {
            JoinContent(join: join, onJoin: model.join)
                .navigationTitle("Join a game")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.navigate(to: .home) }
                            .accessibilityIdentifier("joinCancelButton")
                    }
                }
        }
        .onAppear { join.start() }
        .onDisappear { join.stop() }
        .onChange(of: scenePhase) { if $1 == .active { join.sceneBecameActive() } }
    }
}

/// The Join screen's body for a given `JoinModel` (split out for previews).
struct JoinContent: View {
    let join: JoinModel
    let onJoin: (DiscoveredGame) -> Void

    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if join.permissionDenied {
                PermissionDeniedView()
            } else if join.games.isEmpty {
                SearchingView()
            } else {
                gameList
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: join.games)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: join.permissionDenied)
        .background(Theme.background)
    }

    private var gameList: some View {
        List {
            Section {
                ForEach(join.games) { game in
                    GameRow(game: game, hostName: join.hostName(of: game),
                            availability: JoinModel.availability(of: game)) { onJoin(game) }
                }
            } header: {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Games nearby")
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityHidden(true)
                }
            } footer: {
                Text("Don’t see your friend’s game? Make sure you’re both on the same Wi-Fi network.")
            }
        }
    }
}

/// One nearby game: host, player count and whether it can be joined.
private struct GameRow: View {
    let game: DiscoveredGame
    /// The host's name as listed (with a suffix if two hosts share it).
    let hostName: String
    let availability: JoinModel.Availability
    let onJoin: () -> Void

    /// Joinable, or in progress (to rejoin); not when it needs another app version.
    private var isTappable: Bool { availability != .updateRequired }

    var body: some View {
        Button(action: onJoin) {
            HStack(spacing: Theme.Spacing.m) {
                PlayerInitial(name: hostName)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("\(hostName)’s game")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Color.primary)
                    detail
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: Theme.Spacing.s)
                if isTappable {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(.rect)
        }
        .disabled(!isTappable)
        .opacity(isTappable ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint)
        .accessibilityIdentifier("game-\(hostName)")
    }

    @ViewBuilder private var detail: some View {
        let players = Text("\(game.advertisement.playerCount) players")
        switch availability {
        case .joinable: players
        case .inProgress: Text("In progress · tap to rejoin if you were playing")
        case .updateRequired: Text("Update the app")
        }
    }

    private var hint: Text {
        switch availability {
        case .joinable: Text("Joins this game.")
        case .inProgress: Text("Rejoins this game if you were playing in it.")
        case .updateRequired: Text(verbatim: "")
        }
    }
}

/// While nothing has been found yet.
private struct SearchingView: View {
    var body: some View {
        StatusMessageView(
            icon: .progress, title: Text("Looking for games nearby…"),
            message: Text("Ask a friend to host a game. It shows up here as soon as their phone is on the same Wi-Fi network as yours."))
            .accessibilityIdentifier("searchingForGames")
    }
}

/// The Local Network permission was refused: explain, and offer the way back.
private struct PermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        StatusMessageView(
            icon: .symbol("wifi.exclamationmark"), title: Text("Allow Local Network access"),
            message: Text("Games are found over your Wi-Fi network, so the app needs Local Network access. Turn it on in Settings, then come back.")
        ) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Open Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("openSettingsButton")
        }
    }
}

#if DEBUG
#Preview("Join – games nearby") {
    let demo = PreviewData.demoNetwork()
    JoinContent(join: PreviewData.startedJoinModel(demo.network), onJoin: { _ in })
        .onDisappear { _ = demo }
}
#endif

#Preview("Join – searching") {
    NavigationStack {
        JoinContent(join: JoinModel(factory: InMemoryNetwork()), onJoin: { _ in })
            .navigationTitle("Join a game")
            .navigationBarTitleDisplayMode(.inline)
    }
}
