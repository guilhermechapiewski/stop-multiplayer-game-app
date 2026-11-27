import SwiftUI

/// Name, sounds and About. Presented as a sheet from Home.
struct SettingsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
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
                set: { enabled in Task { await model.setSoundsEnabled(enabled) } })
    }

    /// Saves a changed name; a blank one reverts to the saved name.
    private func commitName() {
        let saved = model.profile?.name ?? ""
        guard !PlayerName.isBlank(name) else {
            name = saved
            return
        }
        guard name.trimmingCharacters(in: .whitespacesAndNewlines) != saved else { return }
        let newName = name
        Task { await model.saveName(newName) }
    }
}

#Preview {
    SettingsView(model: PreviewData.model())
}
