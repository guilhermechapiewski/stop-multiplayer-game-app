import StopSession
import SwiftUI

/// Shows the screen for `AppModel.route`.
struct RootView: View {
    let model: AppModel

    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.route)
            .onChange(of: model.keepsScreenAwake, initial: true) { _, awake in IdleTimer.setDisabled(awake) }
            .alert(endNoticeTitle, isPresented: showsEndNotice, presenting: model.endNotice) { _ in
                Button("OK") { model.dismissEndNotice() }
            } message: { reason in
                Text(EndReasonCopy(reason).message)
            }
            // The Settings toggle (and `-uiTesting`, which always mutes) drives the sound effects. The unit
            // tests' host app never starts audio.
            .onChange(of: model.soundsEnabled && !StopApp.isHostingUnitTests, initial: true) { _, enabled in
                SoundEngine.shared.enabled = enabled
            }
            // Warm the audio engine up on entering a game, not on the first frame; stop it in the background.
            .onChange(of: isInGame, initial: true) { _, inGame in
                if inGame { SoundEngine.shared.warmUp() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { SoundEngine.shared.pause() }
            }
    }

    private var endNoticeTitle: Text {
        model.endNotice.map { Text(EndReasonCopy($0).title) } ?? Text(verbatim: "")
    }

    private var showsEndNotice: Binding<Bool> {
        Binding(get: { model.endNotice != nil }, set: { if !$0 { model.dismissEndNotice() } })
    }

    private var isInGame: Bool {
        if case .game = model.route { true } else { false }
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
