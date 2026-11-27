import StopCore
import StopSession
import StopSimulation
import SwiftUI

/// A solo game against bots: the player picks the bots and the usual game options, then the lobby opens with
/// the bots already in it.
struct PracticeSetupView: View {
    let model: AppModel

    @State private var practice: PracticeSetupModel
    @Environment(\.reduceMotion) private var reduceMotion

    init(model: AppModel) {
        self.model = model
        _practice = State(initialValue: model.makePracticeSetupModel())
    }

    var body: some View {
        NavigationStack {
            List {
                botsSection
                speedSection
                GameOptionsSections(setup: practice.setup, maxStops: practice.maxStops)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: practice.botCount)
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.navigate(to: .home) }
                        .accessibilityIdentifier("practiceCancelButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    Button(action: start) {
                        Label("Start practice", systemImage: "play.fill")
                    }
                    .buttonStyle(.primary)
                    .disabled(!practice.canStart)
                    .accessibilityHint("Opens the lobby with your bots. Start the first round from there.")
                    .accessibilityIdentifier("startPracticeButton")
                }
            }
            .task { await practice.setup.load() }
        }
    }

    // MARK: Sections

    private var botsSection: some View {
        Section {
            Stepper(value: $practice.botCount, in: PracticeSetupModel.botRange) {
                LabeledContent("Bots") {
                    Text(practice.botCount, format: .number)
                        .font(Theme.Typography.headline)
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                }
            }
            .accessibilityIdentifier("botsStepper")
            FlowLayout(spacing: Theme.Spacing.s) {
                ForEach(practice.botNames, id: \.self) { name in
                    PlayerChip(name: name, presence: .present, isBot: true)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Playing against"))
            .accessibilityValue(Text(verbatim: practice.botNames.formatted(.list(type: .and))))
        } header: {
            Text("Opponents")
        } footer: {
            if practice.hasCustomCategories {
                Text("Bots don’t know your own categories — they guess there and score 0.")
            } else {
                Text("A solo game on this phone. No network needed.")
            }
        }
    }

    private var speedSection: some View {
        Section {
            Picker("Bot speed", selection: $practice.speed) {
                ForEach(BotSpeed.allCases, id: \.self) { speed in
                    Text(speed.title).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .accessibilityLabel(Text("Bot speed"))
            .accessibilityIdentifier("botSpeedPicker")
        } header: {
            Text("Bot speed")
        } footer: {
            Text(practice.speed.summary)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: practice.speed)
        }
    }

    private func start() {
        model.startPractice(settings: practice.settings(), botNames: practice.botNames, speed: practice.speed)
    }
}

extension BotSpeed {
    var title: LocalizedStringKey {
        switch self {
        case .relaxed: "Relaxed"
        case .normal: "Normal"
        case .fast: "Fast"
        }
    }

    /// When the bots call STOP, in words (matches `stopWindow`).
    var summary: LocalizedStringKey {
        switch self {
        case .relaxed: "Bots take their time and call STOP after a minute or more. Good for learning."
        case .normal: "Bots call STOP after about 35 to 60 seconds."
        case .fast: "Bots call STOP after 20 to 35 seconds. Think fast!"
        }
    }
}

#Preview("Practice setup") {
    PracticeSetupView(model: PreviewData.model())
}

#Preview("Practice setup – Portuguese") {
    PracticeSetupView(model: PreviewData.model())
        .environment(\.locale, Locale(identifier: "pt-BR"))
}
