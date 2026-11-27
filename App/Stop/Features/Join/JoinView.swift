import StopNetworking
import SwiftUI
import UIKit

/// Games hosted nearby, live. Tapping a joinable one joins it.
struct JoinView: View {
    let model: AppModel

    @State private var join: JoinModel

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
                    GameRow(game: game, availability: JoinModel.availability(of: game)) { onJoin(game) }
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
    let availability: JoinModel.Availability
    let onJoin: () -> Void

    private var isJoinable: Bool { availability == .joinable }
    private var hostName: String { game.advertisement.hostName }

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
                if isJoinable {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(.rect)
        }
        .disabled(!isJoinable)
        .opacity(isJoinable ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isJoinable ? Text("Joins this game.") : Text(verbatim: ""))
        .accessibilityIdentifier("game-\(hostName)")
    }

    @ViewBuilder private var detail: some View {
        let players = Text("\(game.advertisement.playerCount) players")
        switch availability {
        case .joinable: players
        case .inProgress: Text("\(players) · In progress")
        case .updateRequired: Text("Update the app")
        }
    }
}

/// While nothing has been found yet.
private struct SearchingView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
                .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.s) {
                Text("Looking for games nearby…")
                    .font(Theme.Typography.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Ask a friend to host a game. It shows up here as soon as their phone is on the same Wi-Fi network as yours.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
        .accessibilityIdentifier("searchingForGames")
    }
}

/// The Local Network permission was refused: explain, and offer the way back.
private struct PermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Allow Local Network access")
                    .font(Theme.Typography.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Games are found over your Wi-Fi network, so the app needs Local Network access. Turn it on in Settings, then come back.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Open Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("openSettingsButton")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
    }
}

#Preview("Join – games nearby") {
    let demo = PreviewData.demoNetwork()
    JoinContent(join: PreviewData.startedJoinModel(demo.network), onJoin: { _ in })
        .onDisappear { _ = demo }
}

#Preview("Join – searching") {
    NavigationStack {
        JoinContent(join: JoinModel(factory: InMemoryNetwork()), onJoin: { _ in })
            .navigationTitle("Join a game")
            .navigationBarTitleDisplayMode(.inline)
    }
}
