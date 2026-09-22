import SwiftUI

struct KonjuGoSettingsView: View {
    let credentials: any KonjuGoCredentials
    @Environment(\.dismiss) private var dismiss
    @AppStorage(VerbLoadingMode.defaultsKey, store: VerbLoadingMode.defaults) private var loadingMode: VerbLoadingMode = .onDemand
    @State private var key = ""
    @State private var message: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Conjugation loading", selection: $loadingMode) {
                        ForEach(VerbLoadingMode.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("loadingModePicker")
                } header: {
                    Text("Loading")
                } footer: {
                    Text("On demand loads Präsens first and fetches other forms when selected. Load everything fetches all moods and tenses together. Both save results for reuse. Changes apply to your next lookup or refresh.")
                }
                Section {
                    SecureField("OpenAI API key", text: $key)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("openAIKey")
                    #if !os(macOS)
                        .textInputAutocapitalization(.never)
                    #endif
                } header: {
                    Text("OpenAI")
                } footer: {
                    Text("Your key is stored in this device’s Keychain. Verbs are sent to OpenAI to generate conjugations. Normal API usage charges apply. Clear the field and save to remove your key.")
                }
                Section {
                    HStack {
                        if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                        Spacer()
                        if loaded {
                            Button("Save", action: save).buttonStyle(.borderedProminent)
                        } else {
                            Button("Try again", action: load)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 500, height: 510)
        #endif
        .onAppear(perform: load)
        .onChange(of: key) { message = nil }
    }
    private func load() {
        do { key = try credentials.load(); loaded = true }
        catch { message = error.localizedDescription }
    }
    private func save() {
        do { try credentials.save(key); message = "Saved." }
        catch { message = error.localizedDescription }
    }
}
