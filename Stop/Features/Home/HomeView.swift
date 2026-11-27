import SwiftUI

/// The main menu: host or join (and, in Debug builds only, practice with bots); the gear opens Settings.
struct HomeView: View {
    let model: AppModel

    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xxl) {
                header
                actions
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
            .centeredScrolling()
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape.fill") { showsSettings = true }
                        .accessibilityIdentifier("settingsButton")
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView(model: model)
            }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            StopSign(size: 132)
            Text(verbatim: AppInfo.name)
                .font(Theme.Typography.display)
                .accessibilityAddTraits(.isHeader)
            if let name = model.profile?.name {
                Text("Hi, \(name)! Ready to play?")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button { model.navigate(to: .hostSetup) } label: {
                Label("Host a game", systemImage: "person.3.fill")
            }
            .buttonStyle(.primary)
            .accessibilityHint("Start a game on this phone that friends nearby can join.")
            .accessibilityIdentifier("hostGameButton")

            Button { model.navigate(to: .join) } label: {
                Label("Join a game", systemImage: "wifi")
            }
            .buttonStyle(.secondary)
            .accessibilityHint("Find games hosted by friends on the same network.")
            .accessibilityIdentifier("joinGameButton")

            #if DEBUG
            // Development and testing only: Release builds (TestFlight, App Store) have no practice.
            Button { model.navigate(to: .practiceSetup) } label: {
                Label("Practice with bots", systemImage: "cpu")
            }
            .buttonStyle(.secondary)
            .accessibilityHint("Play on your own against computer players.")
            .accessibilityIdentifier("practiceButton")
            #endif
        }
    }
}

#Preview {
    HomeView(model: PreviewData.model())
}
