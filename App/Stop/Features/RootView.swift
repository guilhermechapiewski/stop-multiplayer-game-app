import StopSession
import SwiftUI

/// Shows the screen for `AppModel.route`.
struct RootView: View {
    let model: AppModel

    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        content
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.route)
            .onChange(of: model.keepsScreenAwake, initial: true) { _, awake in IdleTimer.setDisabled(awake) }
            .alert(endNoticeTitle, isPresented: showsEndNotice, presenting: model.endNotice) { _ in
                Button("OK") { model.dismissEndNotice() }
            } message: { reason in
                Text(EndReasonCopy(reason).message)
            }
    }

    private var endNoticeTitle: Text {
        model.endNotice.map { Text(EndReasonCopy($0).title) } ?? Text(verbatim: "")
    }

    private var showsEndNotice: Binding<Bool> {
        Binding(get: { model.endNotice != nil }, set: { if !$0 { model.dismissEndNotice() } })
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
            RejoiningView(hostName: ref.hostName, mayBeGone: model.client?.hostStatus == .mayBeGone,
                          networkDenied: model.isLocalNetworkDenied, onCancel: model.cancelRejoin)
                .transition(.opacity)
        case .hostSetup:
            HostSetupView(model: model)
                .transition(.opacity)
        case .join:
            JoinView(model: model)
                .transition(.opacity)
        case .practiceSetup:
            PracticeSetupView(model: model)
                .transition(.opacity)
        case .game:
            GameContainerView(model: model)
                .environment(\.isPracticeGame, model.isPractice)
                .transition(.opacity)
        }
    }
}
