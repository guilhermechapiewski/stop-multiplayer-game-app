import StopCore
import StopSession
import SwiftUI

/// The writing screen: the letter, the live stop count, one field per category, and STOP / Give up.
/// Typing stays local to each field (see `WritingModel`); this view only re-renders on snapshots, on focus
/// changes and when the answers freeze.
struct WritingView: View {
    let client: any GameClient
    let state: GameState
    let round: Round

    @Environment(\.reduceMotion) private var reduceMotion
    @State private var model: WritingModel?
    @FocusState private var focus: Int?
    @State private var confirmingGiveUp = false

    private var me: PlayerID { client.localPlayerID }
    private var categories: [String] { state.settings.categories }
    private var isParticipant: Bool { round.participants.contains(me) }
    private var myStop: StopRecord? { round.stops.first { $0.playerID == me } }
    /// Answers frozen by my STOP / give up (or restored after a relaunch once I had stopped).
    private var frozen: [String]? { client.frozenAnswers ?? (myStop != nil ? round.answers[me] : nil) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header
                    if !isParticipant {
                        spectatorNote
                    } else if let model {
                        fields(model)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.Spacing.xl)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.never)
            .onChange(of: focus) { _, field in
                guard let field else { return }
                withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(field, anchor: .center) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isParticipant { bottomBar }
        }
        .task(id: round.number) { await loadDraft() }
        .confirmationDialog("Give up this round?", isPresented: $confirmingGiveUp, titleVisibility: .visible) {
            Button("Give up", role: .destructive) { giveUp() }
                .accessibilityIdentifier("confirmGiveUpButton")
            Button("Keep writing", role: .cancel) {}
        } message: {
            Text("Your answers so far are sent as they are. It counts as a stop.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            LetterTile(letter: round.letter, size: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Round \(round.number) · Letter \(round.letter)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                StopsCounter(state: state, round: round)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var spectatorNote: some View {
        Label("This round started before you joined. You’ll play from the next one.",
              systemImage: "hourglass")
            .font(Theme.Typography.body)
            .foregroundStyle(.secondary)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }

    // MARK: Fields

    private func fields(_ model: WritingModel) -> some View {
        let frozen = frozen
        return VStack(spacing: Theme.Spacing.m) {
            ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                AnswerField(model: model, index: index, category: category, isLast: index == categories.count - 1,
                            frozenText: frozen.map { $0.indices.contains(index) ? $0[index] : "" },
                            focus: $focus)
                    .id(index)
            }
        }
    }

    // MARK: Actions

    @ViewBuilder private var bottomBar: some View {
        BottomActionBar {
            if let myStop {
                StoppedBanner(kind: myStop.kind)
            } else if frozen != nil {
                StoppedBanner(kind: .stop)
            } else if let model {
                HStack(spacing: Theme.Spacing.s) {
                    if state.settings.allowGiveUp {
                        Button("Give up") { confirmingGiveUp = true }
                            .buttonStyle(.secondary)
                            .frame(maxWidth: 140)
                            .accessibilityHint(Text("Ends your round with the answers you have."))
                            .accessibilityIdentifier("giveUpButton")
                    }
                    StopButton(availability: model.availability) { stop() }
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: frozen != nil)
    }

    private func stop() {
        guard let model else { return }
        focus = nil
        GameFeedback.play(.stopTapped)
        model.stop()
    }

    private func giveUp() {
        guard let model else { return }
        focus = nil
        GameFeedback.play(.stopTapped)
        model.giveUp()
    }

    /// Seeds the fields once per round: from the saved draft (a relaunch mid-round), else from answers the host
    /// already holds.
    private func loadDraft() async {
        let draft = await client.draft()
        guard !Task.isCancelled else { return }
        let model = WritingModel(categoryCount: categories.count, client: client,
                                 initial: draft ?? client.frozenAnswers ?? round.answers[me])
        self.model = model
        GameFeedback.play(.writingStarted)
        if frozen == nil, isParticipant {
            focus = model.answers.firstIndex(where: AnswerText.isBlank) ?? 0
        }
    }
}

/// "Stops 1/2 — Ana": how many stops the round has, how many end it, and who stopped.
struct StopsCounter: View {
    let state: GameState
    let round: Round

    private var required: Int { state.effectiveStopsRequired }
    private var names: [String] {
        let display = state.displayNames
        return round.stops.compactMap { display[$0.playerID] }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text("Stops \(round.stops.count)/\(required)")
                .font(Theme.Typography.headline.monospacedDigit())
                .foregroundStyle(round.stops.isEmpty ? Color.primary : Theme.accent)
                .contentTransition(.numericText())
            if !names.isEmpty {
                Text(verbatim: "— " + names.formatted(.list(type: .and, width: .short)))
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Stops \(round.stops.count) of \(required)"))
        .accessibilityValue(Text(verbatim: names.formatted(.list(type: .and))))
        .accessibilityIdentifier("stopsCounter")
    }
}

/// The big STOP button. The only view that observes whether every category is filled.
private struct StopButton: View {
    let availability: StopAvailability
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("STOP!", systemImage: "hand.raised.fill")
        }
        .buttonStyle(.primary)
        .disabled(!availability.allFilled)
        .accessibilityLabel(Text("Stop"))
        .accessibilityHint(availability.allFilled ? Text("Ends the round for you and sends your answers.")
                                                  : Text("Fill in every category to stop."))
        .accessibilityIdentifier("stopButton")
    }
}

/// Shown in place of the buttons once I've stopped or given up.
private struct StoppedBanner: View {
    let kind: StopKind

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ProgressView()
                .accessibilityHidden(true)
            Text(kind == .giveUp ? "You gave up — waiting for others" : "You stopped — waiting for others")
                .font(Theme.Typography.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.horizontal, Theme.Spacing.m)
        .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: Theme.Radius.control))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stoppedBanner")
    }
}

#Preview("Writing – host") {
    let client = PreviewData.client(isHost: true, phase: .writing)
    let state = client.state!
    WritingView(client: client, state: state, round: state.currentRound!)
        .background(Theme.background)
}

#Preview("Writing – give up allowed, one stop") {
    let client = PreviewData.client(isHost: false, phase: .writing)
    var state = client.state!
    state.settings.allowGiveUp = true
    state.rounds[0].stops = [StopRecord(playerID: PreviewData.hostID, kind: .stop)]
    return WritingView(client: client, state: state, round: state.rounds[0])
        .background(Theme.background)
}

#Preview("Writing – stopped") {
    let client = PreviewData.client(isHost: true, phase: .writing)
    client.frozenAnswers = ["Bruno", "Bear", "Brazil", "Banana", "Blue", "Bread"]
    var state = client.state!
    state.rounds[0].stops = [StopRecord(playerID: PreviewData.hostID, kind: .stop)]
    return WritingView(client: client, state: state, round: state.rounds[0])
        .background(Theme.background)
}
