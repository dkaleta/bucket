import SwiftUI
import AVFoundation

struct SettingsView: View {
    @AppStorage("practice.lessonSize") private var lessonSize = 10
    private let store = KeychainStore()
    @State private var elevenLabs = ""
    @State private var openAI = ""
    @State private var message: String?
    @State private var loaded = false
    @State private var microphoneTest = MicrophoneTest()
    @State private var microphones: [MicrophoneDevice] = []
    @AppStorage("practice.microphoneID") private var selectedMicrophone = ""
    @State private var microphonePermission = ""

    var body: some View {
        Form {
            Section("Microphone test") {
                HStack {
                    Picker("Microphone", selection: $selectedMicrophone) {
                        if microphones.isEmpty { Text("No microphones found").tag("") }
                        ForEach(microphones) { microphone in Text(microphone.name).tag(microphone.id) }
                    }
                    .disabled(microphoneTest.isCapturing)
                    Button("Refresh", systemImage: "arrow.clockwise", action: refreshMicrophones)
                        .labelStyle(.iconOnly).disabled(microphoneTest.isCapturing)
                }
                HStack {
                    Text("Microphone permission: \(microphonePermission)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Permissions…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }.font(.caption)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Microphone level").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.1f s recorded", microphoneTest.seconds)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: microphoneTest.level)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Test microphone level")
                        .accessibilityValue("\(Int(microphoneTest.level * 100)) percent")
                    Text(microphoneTest.errorMessage ?? microphoneTest.message)
                        .font(.callout).foregroundStyle(microphoneTest.errorMessage == nil ? Color.secondary : .red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if microphoneTest.isCapturing {
                        Button(microphoneTest.phase == .preparing ? "Cancel" : "Stop recording", systemImage: "stop.fill", action: microphoneTest.stopRecording)
                    } else {
                        Button("Record 7-second test", systemImage: "mic.fill") {
                            guard let device = microphones.first(where: { $0.id == selectedMicrophone }) else { return }
                            microphoneTest.start(device: device)
                        }.disabled(selectedMicrophone.isEmpty)
                    }
                    Spacer()
                    Button(microphoneTest.phase == .playing ? "Stop playback" : "Play recording",
                           systemImage: microphoneTest.phase == .playing ? "stop.fill" : "play.fill",
                           action: microphoneTest.togglePlayback)
                        .disabled(!microphoneTest.canPlay)
                }
                Text("Local test only: no API key or internet needed. Audio stays in memory and is discarded when you close Settings. This input is also used for new tutor conversations. Starting a test stops any voice conversation or answer recording.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                SecureField("ElevenLabs API key", text: $elevenLabs)
                SecureField("OpenAI API key", text: $openAI)
            } header: {
                Text("API keys")
            } footer: {
                Text("Your keys are stored in this Mac’s Keychain. Answer recordings and speaker playback use ElevenLabs. OpenAI grades answers and prepares questions. Ask tutor sends microphone audio, the current question, your answer, and feedback directly to OpenAI for a voice conversation. Active lessons and answers are saved on this Mac; voice conversations are not. Provider usage charges apply.")
            }
            Section("Practice lessons") {
                Picker("Questions per focused lesson", selection: $lessonSize) {
                    Text("5").tag(5)
                    Text("10").tag(10)
                    Text("20").tag(20)
                }
                Text("Main practice always uses 10 questions. This setting applies to new tagged lessons; difficulty matches the source question.")
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
        .frame(width: 600, height: 700)
        .onAppear { load(); refreshMicrophones() }
        .onDisappear { microphoneTest.reset() }
        .onChange(of: selectedMicrophone) { microphoneTest.reset() }
        .onChange(of: microphoneTest.phase) { refreshPermission() }
        .onChange(of: elevenLabs) { message = nil }
        .onChange(of: openAI) { message = nil }
    }

    private func refreshMicrophones() {
        microphones = LocalMicrophoneRecorder.devices()
        if !microphones.contains(where: { $0.id == selectedMicrophone }) {
            let preferred = LocalMicrophoneRecorder.defaultDeviceID
            selectedMicrophone = microphones.first(where: { $0.id == preferred })?.id ?? microphones.first?.id ?? ""
        }
        refreshPermission()
    }

    private func refreshPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphonePermission = "Allowed"
        case .notDetermined: microphonePermission = "Requested when you record"
        case .denied: microphonePermission = "Denied"
        case .restricted: microphonePermission = "Restricted"
        @unknown default: microphonePermission = "Unknown"
        }
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
