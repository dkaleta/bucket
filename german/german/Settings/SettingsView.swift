import SwiftUI

struct SettingsView: View {
    @AppStorage("practice.lessonSize") private var lessonSize = 10
    private let store = KeychainStore()
    @State private var elevenLabs = ""
    @State private var openAI = ""
    @State private var message: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                SecureField("ElevenLabs API key", text: $elevenLabs)
                SecureField("OpenAI API key", text: $openAI)
            } header: {
                Text("API keys")
            } footer: {
                Text("Your keys are stored in this Mac’s Keychain. Audio is sent to ElevenLabs; your translation is sent to OpenAI for grading. OpenAI also prepares tagged lessons. Active lessons, answers, and feedback are saved on this Mac. Provider usage charges apply.")
            }
            Section("Practice lessons") {
                Picker("Questions per lesson", selection: $lessonSize) {
                    Text("5").tag(5)
                    Text("10").tag(10)
                    Text("20").tag(20)
                }
                Text("Applies to new lessons. Difficulty matches the question you start from.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!loaded)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 440)
        .onAppear { load() }
        .onChange(of: elevenLabs) { message = nil }
        .onChange(of: openAI) { message = nil }
    }

    private func load() {
        do {
            elevenLabs = try store.read(.elevenLabs)
            openAI = try store.read(.openAI)
            loaded = true
        } catch { message = error.localizedDescription }
    }

    private func save() {
        do {
            try store.save(elevenLabs, for: .elevenLabs)
            try store.save(openAI, for: .openAI)
            message = "Saved."
        } catch { message = error.localizedDescription }
    }
}
