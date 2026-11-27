import SwiftUI

/// Name, sounds and About. Presented as a sheet from Home.
struct SettingsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    /// The name being saved, so the several commit points (submit, focus loss, Done, dismiss) save it once.
    @State private var savingName: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .font(Theme.Typography.headline)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(commitName)
                        .onChange(of: name) { name = PlayerName.limited($1) }
                        .onChange(of: nameFocused) { if !$1 { commitName() } }
                        .accessibilityLabel("Your name")
                        .accessibilityIdentifier("settingsNameField")
                } header: {
                    Text("Your name")
                } footer: {
                    Text("Friends see this name when you play together.")
                }

                Section {
                    Toggle(isOn: soundsBinding) {
                        Label("Sounds", systemImage: "speaker.wave.2.fill")
                    }
                    .accessibilityIdentifier("soundsToggle")
                } footer: {
                    Text("Sound effects never play while your phone is on silent.")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle.fill")
                    }
                    .accessibilityIdentifier("aboutLink")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitName()
                        dismiss()
                    }
                    .accessibilityIdentifier("settingsDoneButton")
                }
            }
        }
        .fontDesign(.rounded)
        .onAppear { name = model.profile?.name ?? "" }
        .onDisappear(perform: commitName)
    }

    private var soundsBinding: Binding<Bool> {
        Binding(get: { model.profile?.soundsEnabled ?? true },
                set: { model.setSoundsEnabled($0) })
    }

    /// Saves a changed name; a blank one reverts to the saved name.
    private func commitName() {
        let saved = model.profile?.name ?? ""
        guard !PlayerName.isBlank(name) else {
            name = saved
            return
        }
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newName != saved, newName != savingName else { return }
        savingName = newName
        Task {
            await model.saveName(newName)
            if savingName == newName { savingName = nil }
        }
    }
}

#Preview {
    SettingsView(model: PreviewData.model())
}
