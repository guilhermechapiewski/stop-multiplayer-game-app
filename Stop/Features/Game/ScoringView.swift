import StopCore
import StopSession
import SwiftUI

/// Scoring, one category at a time: everyone's answers and current scores, read-only, and each player scores
/// their own (10 / 5 / 0). The host can score for players who are away. Once everyone has scored, picks stay
/// editable until the host taps Next category (See results after the last).
struct ScoringView: View {
    let client: any GameClient
    let state: GameState
    let round: Round

    @Environment(\.reduceMotion) private var reduceMotion
    /// My pick, shown at once while the host confirms it.
    @State private var pendingPick: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The back-arrow-only Previous button's width.
    @ScaledMetric(relativeTo: .title3) private var compactPreviousWidth: CGFloat = 64
    /// The category this view last settled on. It still holds the old one during the update that changes it,
    /// which is how that update knows which way to slide.
    @State private var settledCategory: Int?
    /// Which way the last category change went; kept while the card slides.
    @State private var slideDirection = ScoringCategoryChange.Direction.forward

    private var me: PlayerID { client.localPlayerID }
    private var presentation: ScoringPresentation { ScoringPresentation(state: state, viewer: me) }
    private var isCompleted: Bool { presentation.isCompleted }
    private var isParticipant: Bool { round.participants.contains(me) }

    var body: some View {
        let presentation = presentation
        let index = presentation.categoryIndex
        let settled = settledCategory ?? index
        let direction = ScoringCategoryChange.direction(from: settled, to: index, otherwise: slideDirection)
        let categoryAnimation: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.4)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header(presentation)
                // The new card slides in from the side it comes from (trailing for next, leading for previous).
                // The old one just fades: a removed view keeps the transition of its last update, which can't
                // know the direction of a change that hadn't happened yet.
                answersCard(presentation)
                    .id(index)
                    .transition(reduceMotion ? .opacity
                                : .asymmetric(insertion: .move(edge: direction == .forward ? .trailing : .leading)
                                                .combined(with: .opacity),
                                              removal: .opacity))
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.l)
        }
        .safeAreaInset(edge: .bottom) { picker(presentation) }
        .animation(categoryAnimation, value: index)
        // Arriving at a category that is already complete moves with the slide, without the completion spring.
        .animation(settled != index ? categoryAnimation : reduceMotion ? nil : .spring(duration: 0.35),
                   value: isCompleted)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: presentation.rows.map(\.score))
        .onAppear { settledCategory = index }
        .onChange(of: index) { old, new in
            pendingPick = nil
            slideDirection = ScoringCategoryChange.direction(from: old, to: new, otherwise: slideDirection)
            settledCategory = new
        }
        .onChange(of: presentation.myScore) { _, score in
            if score == pendingPick { pendingPick = nil }
        }
        .onChange(of: ScoringCategoryChange.Snapshot(categoryIndex: index, isCompleted: isCompleted)) { old, new in
            if ScoringCategoryChange.celebratesCompletion(from: old, to: new) {
                GameFeedback.play(.categoryCompleted)
            }
        }
    }

    // MARK: Header

    private func header(_ presentation: ScoringPresentation) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Round \(round.number) · Letter \(round.letter)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: presentation.categoryName)
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: Theme.Spacing.s)
                Text("\(presentation.categoryIndex + 1) of \(presentation.total)")
                    .font(Theme.Typography.headline.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("scoringCategory-\(presentation.categoryIndex)")
            ChunkyProgress(value: Double(presentation.categoryIndex + (isCompleted ? 1 : 0)),
                           total: Double(max(1, presentation.total)))
        }
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: Answers

    private func answersCard(_ presentation: ScoringPresentation) -> some View {
        VStack(spacing: 0) {
            ForEach(presentation.rows) { row in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    AnswerRow(row: row, isMe: row.playerID == me)
                    if presentation.canHostScore.contains(row.playerID) {
                        HostScoreControl(row: row) { points in
                            client.send(.setScore(round: round.number, category: presentation.categoryIndex,
                                                  points: points, player: row.playerID))
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s + 2)
                .background(row.playerID == me ? Theme.accentTint : .clear)
                if row.id != presentation.rows.last?.id { Divider().overlay(Theme.divider).padding(.leading, 64) }
            }
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .background(PieceBackground(shape: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous),
                                    outline: .clear))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isCompleted ? Theme.teal : Theme.outline,
                              lineWidth: isCompleted ? 3 : Theme.Stroke.outline)
        }
        .overlay(alignment: .topTrailing) {
            if isCompleted { CompletedBurst().offset(x: 10, y: -22) }
        }
        .padding(.top, isCompleted ? 12 : 0)
    }

    // MARK: Picker and Next

    @ViewBuilder private func picker(_ presentation: ScoringPresentation) -> some View {
        BottomActionBar {
            if !isParticipant {
                Text("You’ll play from the next round.")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minHeight: 44)
            } else {
                Text(isCompleted ? "Everyone has scored!" : "Score your answer")
                    .font(Theme.Typography.headline)
                    .fontWeight(.heavy)
                    .foregroundStyle(isCompleted ? Theme.teal : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(isCompleted ? "categoryCompleted" : "scorePickerTitle")
                // Stays enabled once the category is complete: a wrong pick can be fixed until the host moves on.
                ScorePicker(selection: pendingPick ?? presentation.myScore,
                            options: presentation.myAnswerIsBlank ? [0] : [10, 5, 0]) { points in
                    pendingPick = points
                    GameFeedback.play(.scorePicked)
                    client.send(.setScore(round: round.number, category: presentation.categoryIndex,
                                          points: points, player: me))
                }
                if presentation.myAnswerIsBlank {
                    Text("Blank answers score 0.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else if presentation.isReadAloud, presentation.myScore == nil,
                          !dynamicTypeSize.isAccessibilitySize {
                    // Left out at accessibility sizes, where the pinned bar has no room to spare.
                    Text("Read your answer out loud, then score it.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("readAloudHint")
                }
            }
            if !isCompleted {
                waitingLine(presentation)
            } else if !presentation.showsAdvanceButton {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("Waiting for \(presentation.hostName) to continue…")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(minHeight: 32)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("waitingForHost")
            }
            if presentation.showsAdvanceButton { hostButtons(presentation) }
        }
    }

    /// Host only: Previous beside Next (from the second category on). Its label shows when both fit side by
    /// side; otherwise it's just the back arrow, so the pinned bar stays one button tall.
    @ViewBuilder private func hostButtons(_ presentation: ScoringPresentation) -> some View {
        if presentation.showsPreviousButton {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.s) {
                    previousButton(presentation, compact: false)
                    nextButton(presentation)
                }
                // Next stays on one line (shrinking a little at the largest sizes) rather than hyphenating.
                HStack(spacing: Theme.Spacing.s) {
                    previousButton(presentation, compact: true)
                    nextButton(presentation, oneLine: true)
                }
            }
        } else {
            nextButton(presentation)
        }
    }

    /// Host only: takes everyone back to the category before, to review or correct its scores.
    @ViewBuilder private func previousButton(_ presentation: ScoringPresentation, compact: Bool) -> some View {
        let button = Button {
            client.send(.previousCategory(round: round.number, category: presentation.categoryIndex))
        } label: {
            if compact {
                Image(systemName: "arrow.backward")
            } else {
                Label("Previous category", systemImage: "arrow.backward")
            }
        }
        .buttonStyle(.secondary)
        .accessibilityLabel(Text("Previous category"))
        .accessibilityHint(Text("Takes everyone back to the category before."))
        .accessibilityIdentifier("previousCategoryButton")
        if compact {
            button.frame(width: compactPreviousWidth)
        } else {
            button
        }
    }

    /// Host only: moves everyone on once the category is complete.
    private func nextButton(_ presentation: ScoringPresentation, oneLine: Bool = false) -> some View {
        Button {
            client.send(.nextCategory(round: round.number, category: presentation.categoryIndex))
        } label: {
            Group {
                if presentation.isLastCategory {
                    Label("See results", systemImage: "trophy")
                } else {
                    Label("Next category", systemImage: "arrow.forward")
                }
            }
            .lineLimit(oneLine ? 1 : nil)
            .minimumScaleFactor(oneLine ? 0.6 : 1)
        }
        .buttonStyle(.primary)
        .disabled(!presentation.canAdvance)
        .accessibilityHint(presentation.canAdvance ? Text(verbatim: "") : Text("Available once everyone has scored."))
        .accessibilityIdentifier("nextCategoryButton")
    }

    /// "Waiting for Ana and Bia" while others still have to score.
    @ViewBuilder private func waitingLine(_ presentation: ScoringPresentation) -> some View {
        let waiting = presentation.rows.filter { $0.score == nil && $0.presence.isActive && $0.playerID != me }
        if !waiting.isEmpty {
            Text("Waiting for \(waiting.map(\.name).formatted(.list(type: .and)))")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

/// One player's answer and their current score (10 / 5 / 0), or "…" until they pick one.
private struct AnswerRow: View {
    let row: ScoringPresentation.Row
    let isMe: Bool

    private var isBlank: Bool { row.isBlank }
    private var isAway: Bool { row.presence != .present }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.reduceMotion) private var reduceMotion

    /// "Ana (you) · away": one string, so it wraps as a sentence at large text sizes.
    private var nameLine: String {
        var parts = [row.name]
        if isMe { parts.append(String(localized: "(you)")) }
        if row.presence == .away { parts.append(String(localized: "· away")) }
        if row.presence == .left || row.presence == .removed { parts.append(String(localized: "· left")) }
        return parts.joined(separator: " ")
    }

    var body: some View {
        // At accessibility sizes the (decorative) initial gives its room to the name and answer.
        HStack(spacing: Theme.Spacing.m) {
            if !dynamicTypeSize.isAccessibilitySize {
                PlayerInitial(name: row.name, dimmed: isAway, size: 36, isYou: isMe)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: nameLine)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
                if row.isHidden {
                    // Read aloud: shown once this player scores it.
                    Text(verbatim: "…")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.secondaryText)
                        .transition(.opacity)
                } else {
                    Text(verbatim: row.answer)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(isBlank ? Theme.secondaryText : Theme.text)
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .scale(scale: 0.85, anchor: .leading)
                                                      .combined(with: .opacity),
                                                  removal: .opacity))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Spacing.s)
            status
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.name))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(row.isHidden ? "answerRowHidden" : "answerRow")
    }

    private var status: some View {
        ScoreBadge(score: row.score)
    }

    private var accessibilityValue: Text {
        if row.isHidden { return Text("Answer hidden until scored") }
        let answer = isBlank ? Text("Blank") : Text(verbatim: row.answer)
        guard let score = row.score else { return Text("\(answer), not scored yet") }
        return Text("\(answer), \(score) points")
    }
}

/// A player's points for the category as a chunky tile: red-orange for 10, yellow for 5, flat for 0, a dashed
/// slot while not scored yet. A minimum width keeps the answers lined up whatever the score.
private struct ScoreBadge: View {
    let score: Int?

    @ScaledMetric(relativeTo: .title3) private var width: CGFloat = 48
    @ScaledMetric(relativeTo: .title3) private var height: CGFloat = 34

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if let score {
            Text(score, format: .number)
                .font(Theme.Typography.headline.monospacedDigit().weight(.black))
                .foregroundStyle(colors(score).text)
                .padding(.horizontal, Theme.Spacing.s)
                .frame(minWidth: width, minHeight: height)
                .piece(shape, fill: colors(score).fill, outline: score > 0 ? Theme.ink : Theme.outline,
                       depth: score > 0 ? 3 : 0)
                .padding(.bottom, 3)
                .contentTransition(.numericText(value: Double(score)))
                .transition(.scale.combined(with: .opacity))
        } else {
            Text(verbatim: "…")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: width, minHeight: height)
                .overlay {
                    shape.strokeBorder(Theme.secondaryText.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
                .padding(.bottom, 3)
                .accessibilityLabel(Text("Not scored yet"))
        }
    }

    /// 10 on red-orange, 5 on yellow, 0 sunk flat.
    private func colors(_ score: Int) -> (fill: Color, text: Color) {
        switch score {
        case 10: (Theme.accentFill, Theme.onAccent)
        case 5: (Theme.yellow, Theme.ink)
        default: (Theme.sunken, Theme.secondaryText)
        }
    }
}

/// Three large segments: 10, 5, 0 (only 0 for a blank answer).
private struct ScorePicker: View {
    let selection: Int?
    let options: [Int]
    let onPick: (Int) -> Void

    @ScaledMetric(relativeTo: .title) private var height: CGFloat = 64

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(options, id: \.self) { points in
                let selected = selection == points
                Button { onPick(points) } label: {
                    Text(points, format: .number)
                        .monospacedDigit()
                }
                .buttonStyle(ScoreTileButtonStyle(selected: selected, minHeight: height))
                .accessibilityLabel(Text(verbatim: AccessibilityText.score(points)))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("score-\(points)")
            }
        }
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

/// A score choice as a game piece: red-orange once picked, cream before.
private struct ScoreTileButtonStyle: ButtonStyle {
    let selected: Bool
    let minHeight: CGFloat
    var font: Font = Theme.Typography.title.weight(.black)

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.reduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        PieceButtonBody(configuration: configuration, fill: selected ? Theme.accentFill : Theme.surface,
                        foreground: selected ? Theme.onAccent : Theme.accent,
                        edge: selected ? Theme.accentEdge : Theme.edge, minHeight: minHeight, isEnabled: isEnabled,
                        reduceMotion: reduceMotion, font: font)
    }
}

/// The "category done" badge: a check on a small teal comic burst, popping in (fading with Reduce Motion).
private struct CompletedBurst: View {
    @Environment(\.reduceMotion) private var reduceMotion
    @State private var shown = false
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 52

    var body: some View {
        let burst = Starburst(points: 10, innerRatio: 0.76)
        Image(systemName: "checkmark")
            .font(.system(size: side * 0.36, weight: .black))
            .foregroundStyle(Theme.ink)
            .frame(width: side, height: side)
            .background {
                burst.fill(Theme.edge).offset(x: 1.5, y: 3)
                burst.fill(Theme.tealFill)
                burst.strokeBorder(Theme.ink, lineWidth: 2)
            }
            .rotationEffect(.degrees(reduceMotion || shown ? -8 : -60))
            .scaleEffect(reduceMotion || shown ? 1 : 0.2)
            .opacity(shown ? 1 : 0)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.5)) {
                    shown = true
                }
            }
    }
}

/// Progress through the categories: a chunky outlined bar. Decorative (the header says "3 of 12").
struct ChunkyProgress: View {
    let value: Double
    let total: Double

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 14

    var body: some View {
        let fraction = total > 0 ? min(1, max(0, value / total)) : 0
        Capsule()
            .fill(Theme.sunken)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.accentFill)
                        .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
                }
            }
            .clipShape(.capsule)
            .overlay { Capsule().strokeBorder(Theme.outline, lineWidth: Theme.Stroke.outline) }
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// Host-only: score for a player who is away (or left) so the category can finish.
private struct HostScoreControl: View {
    let row: ScoringPresentation.Row
    let onPick: (Int) -> Void

    private var isBlank: Bool { row.isBlank }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(row.presence == .away ? "Away — score for \(row.name)" : "Left — score for \(row.name)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(isBlank ? [0] : [10, 5, 0], id: \.self) { points in
                Button { onPick(points) } label: {
                    Text(points, format: .number)
                        .monospacedDigit()
                }
                .buttonStyle(ScoreTileButtonStyle(selected: false, minHeight: 36,
                                                  font: Theme.Typography.caption.weight(.heavy)))
                .fixedSize()
                .accessibilityLabel(Text("Give \(row.name) \(points) points"))
                .accessibilityIdentifier("hostScore-\(points)")
            }
        }
        .padding(.leading, 52)
    }
}

#Preview("Scoring – host, away player") {
    let client = PreviewData.client(isHost: true, phase: .scoring(categoryIndex: 1, completed: false))
    var state = client.state!
    let ids = state.players.map(\.id)
    state.rounds[0].answers = Dictionary(uniqueKeysWithValues: ids.map {
        ($0, ["Bruno", "Bear", "Brazil", "Banana", "Blue", "Bread"])
    })
    state.rounds[0].answers[ids[2]]?[1] = ""
    state.rounds[0].scores = Dictionary(uniqueKeysWithValues: ids.map { ($0, [10, nil, nil, nil, nil, nil]) })
    state.rounds[0].scores[ids[1]]?[1] = 5
    state.rounds[0].scores[ids[2]]?[1] = 0
    client.state = state
    return ScoringView(client: client, state: state, round: state.rounds[0])
        .background(Theme.background)
}

#Preview("Scoring – host, completed") {
    let client = PreviewData.client(isHost: true, phase: .scoring(categoryIndex: 5, completed: true))
    var state = client.state!
    let ids = state.players.map(\.id)
    state.rounds[0].answers = Dictionary(uniqueKeysWithValues: ids.map { ($0, Array(repeating: "Bread", count: 6)) })
    state.rounds[0].answers[ids[1]]?[5] = "Bagel"
    state.rounds[0].answers[ids[3]]?[5] = ""
    state.rounds[0].scores = Dictionary(uniqueKeysWithValues: ids.map { ($0, [10, 10, 10, 10, 10, 5]) })
    state.rounds[0].scores[ids[1]]?[5] = 10
    state.rounds[0].scores[ids[3]]?[5] = 0
    client.state = state
    return ScoringView(client: client, state: state, round: state.rounds[0])
        .background(Theme.background)
}

#Preview("Scoring – completed") {
    let client = PreviewData.client(isHost: false, phase: .scoring(categoryIndex: 0, completed: true))
    var state = client.state!
    let ids = state.players.map(\.id)
    state.rounds[0].answers = Dictionary(uniqueKeysWithValues: ids.map { ($0, Array(repeating: "Bear", count: 6)) })
    state.rounds[0].scores = Dictionary(uniqueKeysWithValues: ids.map { ($0, [10, nil, nil, nil, nil, nil]) })
    state.rounds[0].scores[ids[1]]?[0] = 5
    return ScoringView(client: client, state: state, round: state.rounds[0])
        .background(Theme.background)
}
