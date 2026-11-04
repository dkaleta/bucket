import Foundation
import Observation

@MainActor @Observable final class MicrophoneTest {
    static let willStart = Notification.Name("GermanPractice.MicrophoneTestWillStart")
    enum Phase { case idle, preparing, recording, recorded, playing, failed }
    private(set) var phase: Phase = .idle
    private(set) var level = 0.0
    private(set) var peakLevel = 0.0
    private(set) var seconds = 0.0
    private(set) var message = "Choose a microphone, then record a short sentence."
    private(set) var errorMessage: String?
    private(set) var capturedDevice = ""
    private var pcm = Data()
    private var capture: (any LocalMicrophoneCapturing)?
    private let makeCapture: () -> any LocalMicrophoneCapturing
    private let player: any SpeechPlaying
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var attempt = UUID()
    private let duration: Double
    var isCapturing: Bool { phase == .preparing || phase == .recording }
    var canPlay: Bool { !pcm.isEmpty && !isCapturing }

    init(duration: Double = 7, makeCapture: (() -> any LocalMicrophoneCapturing)? = nil, player: (any SpeechPlaying)? = nil) {
        self.duration = duration
        self.makeCapture = makeCapture ?? { LocalMicrophoneRecorder() }
        self.player = player ?? AnswerAudioPlayer()
    }

    func start(device: MicrophoneDevice) {
        reset()
        capturedDevice = device.name
        phase = .preparing
        message = "Opening \(device.name)…"
        NotificationCenter.default.post(name: Self.willStart, object: nil)
        let id = attempt
        task = Task { [weak self] in
            guard let self, attempt == id, !Task.isCancelled else { return }
            let recorder = makeCapture()
            capture = recorder
            do {
                let stream = try await recorder.start(deviceID: device.id)
                guard attempt == id, !Task.isCancelled else { recorder.stop(); return }
                phase = .recording
                message = "Speak now. Recording stops automatically after \(Int(duration)) seconds."
                timer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(self?.duration ?? 7)) } catch { return }
                    guard let self, attempt == id else { return }
                    self.capture?.stop()
                }
                for try await chunk in stream {
                    guard attempt == id, !Task.isCancelled else { return }
                    let remaining = max(0, Int(duration * 48_000) - pcm.count)
                    let accepted = chunk.prefix(remaining - remaining % 2)
                    pcm.append(accepted)
                    level = TutorPCM.level(Data(accepted))
                    peakLevel = max(peakLevel, level)
                    seconds = Double(pcm.count) / 48_000
                    if remaining <= chunk.count { recorder.stop(); break }
                }
                guard attempt == id, !Task.isCancelled else { return }
                timer?.cancel(); timer = nil
                recorder.stop(); capture = nil
                level = 0
                phase = .recorded
                if pcm.isEmpty { message = "No audio arrived. Try a different microphone or check microphone permission." }
                else if peakLevel == 0 { message = "Audio arrived, but no measurable sound was detected. Try another microphone and compare." }
                else { message = "Sound detected. Play the recording to check whether you can hear your voice." }
            } catch {
                guard attempt == id, !Task.isCancelled else { return }
                timer?.cancel(); timer = nil
                recorder.stop(); capture = nil
                level = 0; phase = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopRecording() {
        if phase == .preparing { reset(); return }
        guard phase == .recording else { return }
        capture?.stop()
    }

    func togglePlayback() {
        if phase == .playing {
            task?.cancel(); task = nil; player.stop(); phase = .recorded
            return
        }
        guard canPlay else { return }
        errorMessage = nil
        phase = .playing
        let id = attempt
        let wav = MicrophoneTestWAV.encode(pcm)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await player.play(wav)
                guard attempt == id, !Task.isCancelled else { return }
                phase = .recorded
            } catch {
                guard attempt == id, !Task.isCancelled else { return }
                phase = .recorded; errorMessage = error.localizedDescription
            }
        }
    }

    func reset() {
        attempt = UUID()
        task?.cancel(); task = nil
        timer?.cancel(); timer = nil
        capture?.stop(); capture = nil
        player.stop()
        pcm = Data(); level = 0; peakLevel = 0; seconds = 0
        phase = .idle; errorMessage = nil
        message = "Choose a microphone, then record a short sentence."
    }
}
