import SwiftUI

/// The main menu: host or join (and, in Debug builds only, practice with bots); the gear opens Settings.
struct HomeView: View {
    let model: AppModel

    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
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
        VStack(spacing: Theme.Spacing.s) {
            LogoBurst(size: 168)
            Text(verbatim: AppInfo.name)
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            if let name = model.profile?.name {
                Text("Hi, \(name)! Ready to play?")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.secondaryText)
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

/// The logo on a sunburst disc, like the app icon. Decorative; the sunburst turns slowly unless Reduce Motion
/// is on.
struct LogoBurst: View {
    var size: CGFloat = 168

    @Environment(\.reduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 1.3)
        ZStack {
            Sunburst(isAnimated: !reduceMotion, rays: 20, period: 60, fades: false)
                .clipShape(.circle)
                .overlay { Circle().strokeBorder(Theme.outline, lineWidth: 2.5) }
                .background { Circle().fill(Theme.edge).offset(y: 5) }
                .frame(width: side * 0.9, height: side * 0.9)
            StopSign(size: side)
                .offset(y: -side * 0.02)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

#Preview {
    HomeView(model: PreviewData.model())
}
