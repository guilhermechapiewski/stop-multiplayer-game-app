import StopCore
import StopSession
import SwiftUI

/// The host picks categories and rules, then creates the game (which opens the lobby).
struct HostSetupView: View {
    let model: AppModel

    @State private var setup: HostSetupModel

    init(model: AppModel) {
        self.model = model
        _setup = State(initialValue: model.makeSetupModel())
    }

    var body: some View {
        NavigationStack {
            List {
                GameOptionsSections(setup: setup, maxStops: Self.maxStops)
            }
            .navigationTitle("New game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.navigate(to: .home) }
                        .accessibilityIdentifier("setupCancelButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    Button { model.hostGame(settings: setup.settings()) } label: {
                        Label("Create game", systemImage: "play.fill")
                    }
                    .buttonStyle(.primary)
                    .disabled(!setup.canCreate)
                    .accessibilityHint("Opens the lobby, where friends nearby can join.")
                    .accessibilityIdentifier("createGameButton")
                }
            }
            .task { await setup.load() }
        }
    }

    /// Nobody knows yet how many friends will join; the lobby lowers this to the number of players.
    static let maxStops = 10
}

/// Categories, stops required and giving up: the options shared by host setup and practice setup.
/// Place inside a `List`.
struct GameOptionsSections: View {
    @Bindable var setup: HostSetupModel
    /// Upper bound of the stops stepper.
    let maxStops: Int

    @State private var newCategory = ""
    @FocusState private var addFieldFocused: Bool
    @Environment(\.reduceMotion) private var reduceMotion

    private var unselected: [String] { setup.available.filter { !setup.isSelected($0) } }

    var body: some View {
        Group {
            selectedSection
            if !unselected.isEmpty { moreSection }
            addSection
            rulesSection
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: setup.selected)
    }

    // MARK: Sections

    private var selectedSection: some View {
        Section {
            ForEach(Array(setup.selected.enumerated()), id: \.element) { index, category in
                SelectedCategoryRow(number: index + 1, name: category) { setup.toggle(category) }
                    .accessibilityAction(named: "Move up") { move(category, by: -1) }
                    .accessibilityAction(named: "Move down") { move(category, by: 1) }
            }
            .onMove(perform: setup.move)
        } header: {
            Text("Categories (\(setup.selected.count))")
        } footer: {
            if setup.selected.isEmpty {
                Label("Pick at least one category.", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            } else {
                Text("Played in this order. Touch and hold a category to move it; tap to remove it.")
            }
        }
    }

    private var moreSection: some View {
        Section("More categories") {
            ForEach(unselected, id: \.self) { category in
                Button { setup.toggle(category) } label: {
                    HStack {
                        Text(category)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(category)
                .accessibilityHint("Adds this category to the game.")
                .swipeActions {
                    if setup.isCustom(category) {
                        Button("Forget", systemImage: "trash", role: .destructive) {
                            Task { await setup.deleteCustom(category) }
                        }
                    }
                }
            }
        }
    }

    private var addSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.s) {
                TextField("Add your own category", text: $newCategory)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($addFieldFocused)
                    .onSubmit(addCategory)
                    .onChange(of: newCategory) {
                        newCategory = String($1.prefix(HostSetupModel.maxCategoryLength))
                    }
                    .accessibilityIdentifier("customCategoryField")
                Button("Add", action: addCategory)
                    .bold()
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("addCategoryButton")
            }
        } footer: {
            Text("Your categories are remembered on this phone for future games. Swipe left on one to forget it.")
        }
    }

    private var rulesSection: some View {
        Section {
            Stepper(value: $setup.stopsRequired, in: 1...max(1, maxStops)) {
                LabeledContent("Stops to end a round") {
                    Text(setup.stopsRequired, format: .number)
                        .font(Theme.Typography.headline)
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                }
            }
            .accessibilityIdentifier("stopsStepper")
            Toggle("Allow giving up", isOn: $setup.allowGiveUp)
                .accessibilityIdentifier("allowGiveUpToggle")
        } header: {
            Text("Rules")
        } footer: {
            Text(RulesText.footer(stopsRequired: setup.stopsRequired, allowGiveUp: setup.allowGiveUp))
        }
    }

    // MARK: Actions

    private func addCategory() {
        let name = newCategory
        newCategory = ""
        Task { await setup.addCustom(name) }
    }

    private func move(_ category: String, by offset: Int) {
        guard let index = setup.selected.firstIndex(of: category) else { return }
        let target = index + offset
        guard setup.selected.indices.contains(target) else { return }
        // `move(fromOffsets:toOffset:)` inserts before `toOffset`, so moving down skips one more.
        setup.move(from: IndexSet(integer: index), to: offset > 0 ? target + 1 : target)
    }
}

/// A category in play: its position, its name and a remove control.
private struct SelectedCategoryRow: View {
    let number: Int
    let name: String
    let onRemove: () -> Void

    @ScaledMetric(relativeTo: .body) private var badge: CGFloat = 28

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: Theme.Spacing.m) {
                Text(number, format: .number)
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: badge, minHeight: badge)
                    .background(Theme.accent.opacity(0.14), in: .circle)
                Text(name)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(number). \(name)"))
        .accessibilityValue(Text("Selected"))
        .accessibilityHint("Removes this category from the game.")
    }
}

#Preview("Host setup") {
    HostSetupView(model: PreviewData.model())
}

#Preview("Host setup – Portuguese") {
    HostSetupView(model: PreviewData.model())
        .environment(\.locale, Locale(identifier: "pt-BR"))
}
