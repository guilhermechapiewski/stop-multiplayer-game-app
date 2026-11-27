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
            HostSetupView(model: model)
                .transition(.opacity)
        case .join:
            JoinView(model: model)
                .transition(.opacity)
        case .practiceSetup:
            // Replaced by PracticeSetupView (Task 17b).
            ComingSoonView(title: "Practice with bots", systemImage: "cpu") { model.navigate(to: .home) }
        case .game:
            GameContainerView(model: model)
                .transition(.opacity)
        }
    }
}
