import SwiftUI

/// Shows the screen for `AppModel.route`.
struct RootView: View {
    let model: AppModel

    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        content
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.route)
    }

    @ViewBuilder private var content: some View {
        switch model.route {
        case .loading:
            Theme.background.ignoresSafeArea()
        case .onboarding:
            NameEntryView(model: model)
                .transition(.opacity)
        case .home:
            HomeView(model: model)
                .transition(.opacity)
        case .rejoining(let ref):
            RejoiningView(hostName: ref.hostName, onCancel: model.cancelRejoin)
                .transition(.opacity)
        case .hostSetup:
            // Replaced by HostSetupView (Task 14).
            ComingSoonView(title: "Host a game", systemImage: "person.3.fill") { model.navigate(to: .home) }
        case .join:
            // Replaced by JoinView (Task 14).
            ComingSoonView(title: "Join a game", systemImage: "wifi") { model.navigate(to: .home) }
        case .practiceSetup:
            // Replaced by PracticeSetupView (Task 17b).
            ComingSoonView(title: "Practice with bots", systemImage: "cpu") { model.navigate(to: .home) }
        case .game:
            // Replaced by GameContainerView (Task 14).
            ComingSoonView(title: "Game", systemImage: "gamecontroller.fill", backTitle: "Leave game",
                           onBack: model.leaveGame)
        }
    }
}
