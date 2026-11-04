import AVFoundation
import Foundation
import CoreAudio

@MainActor protocol RealtimeAudioIO: AnyObject {
    var onDrained: (() -> Void)? { get set }
    var playedMilliseconds: Int { get }
    var hasQueuedAudio: Bool { get }
    var deviceNames: (input: String, output: String) { get }
    func requestPermission() async throws
    func start() async throws -> AsyncThrowingStream<Data, Error>
    func enqueue(_ pcm: Data) throws
    func stopOutput()
    func stop()
}

extension RealtimeAudioIO {
    var deviceNames: (input: String, output: String) { ("System microphone", "System speakers") }
}

nonisolated enum TutorPCM {
    static func level(_ data: Data) -> Double {
        guard data.count >= 2 else { return 0 }
        let sum = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Double in
            var sum = 0.0
            for index in stride(from: 0, to: data.count - 1, by: 2) {
                let sample = Double(Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)) / 32768
                sum += sample * sample
            }
            return sum
        }
        let rms = sqrt(sum / Double(data.count / 2))
        return rms > 0 ? max(0, min(1, (20 * log10(rms) + 60) / 60)) : 0
    }

    /// A quiet, short chime with a fade at either end, in the same format as tutor replies.
    static func testTone() -> Data {
        let count = 7_200
        var data = Data(capacity: count * 2)
        for index in 0..<count {
            let fade = min(1, Double(min(index, count - 1 - index)) / 480)
            var sample = Int16(sin(Double(index) * 2 * .pi * 660 / 24_000) * 0.12 * fade * 32767).littleEndian
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }
        return data
    }
}

@MainActor protocol RealtimeReplyPlaying: AnyObject {
    var onDrained: (() -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
    var playedMilliseconds: Int { get }
    var hasQueuedAudio: Bool { get }
    var deviceName: String { get }
    func start() throws
    func enqueue(_ pcm: Data) throws
    func stopOutput()
    func stop()
}

/// Uses exactly the capture service exercised by Settings. The reply engine is
/// output-only: it never creates an input node or enables VoiceProcessingIO.
@MainActor final class RealtimeAudio: RealtimeAudioIO {
    var onDrained: (() -> Void)? {
        get { playback.onDrained }
        set { playback.onDrained = newValue }
    }
    private let capture: any LocalMicrophoneCapturing
    private let playback: any RealtimeReplyPlaying
    private let specifiedInput: MicrophoneDevice?
    private let permission: () async throws -> Void
    private var inputName = "System microphone"
    private var sink: AsyncThrowingStream<Data, Error>.Continuation?
    private var forwarding: Task<Void, Never>?
    private var closed = false

    init(capture: (any LocalMicrophoneCapturing)? = nil,
         playback: (any RealtimeReplyPlaying)? = nil,
         input: MicrophoneDevice? = nil,
         permission: (() async throws -> Void)? = nil) {
        self.capture = capture ?? LocalMicrophoneRecorder()
        self.playback = playback ?? RealtimeReplyPlayer()
        self.specifiedInput = input
        self.permission = permission ?? { try await MicrophoneCapture.requestPermission() }
    }
    var hasQueuedAudio: Bool { playback.hasQueuedAudio }
    var playedMilliseconds: Int { playback.playedMilliseconds }
    var deviceNames: (input: String, output: String) { (inputName, playback.deviceName) }
    func requestPermission() async throws { try await permission() }

    func start() async throws -> AsyncThrowingStream<Data, Error> {
        do {
            try ensureOpen()
            let input: MicrophoneDevice
            if let specifiedInput { input = specifiedInput }
            else {
                let preferred = UserDefaults.standard.string(forKey: "practice.microphoneID") ?? ""
                let id = preferred.isEmpty ? LocalMicrophoneRecorder.defaultDeviceID : preferred
                guard let device = LocalMicrophoneRecorder.devices().first(where: { $0.id == id }) else {
                    throw PracticeError(message: "The selected microphone is unavailable. Choose an input in Settings → Microphone test.")
                }
                input = device
            }
            inputName = input.name
            let chunks = try await capture.start(deviceID: input.id)
            try ensureOpen()
            let (stream, sink) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(50))
            self.sink = sink
            playback.onFailure = { [weak self] error in self?.fail(error) }
            try playback.start()
            forwarding = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await chunk in chunks {
                        try ensureOpen()
                        if case .dropped = sink.yield(chunk) {
                            throw PracticeError(message: "The voice connection could not keep up. Please reconnect.")
                        }
                    }
                    if !closed { fail(PracticeError(message: "Microphone capture stopped. Start a new conversation to reconnect.")) }
                } catch { if !closed { fail(error) } }
            }
            return stream
        } catch { stop(); throw error }
    }
    private func ensureOpen() throws {
        try Task.checkCancellation()
        if closed { throw CancellationError() }
    }
    private func fail(_ error: Error) { sink?.finish(throwing: error); stop() }
    func enqueue(_ pcm: Data) throws { try playback.enqueue(pcm) }
    func stopOutput() { playback.stopOutput() }
    func stop() {
        closed = true
        forwarding?.cancel(); forwarding = nil
        capture.stop()
        playback.onFailure = nil
        playback.onDrained = nil
        playback.stop()
        sink?.finish(); sink = nil
    }
}

@MainActor final class RealtimeReplyPlayer: RealtimeReplyPlaying {
    var onDrained: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private var configurationObserver: NSObjectProtocol?
    private var queuedBuffers = 0
    private var scheduledSamples: Int64 = 0
    private var playedSamples: Int64 = 0
    private var outputGeneration = UUID()
    var hasQueuedAudio: Bool { queuedBuffers > 0 }
    var deviceName: String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return "System speakers" }
        address.mSelector = kAudioObjectPropertyName
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return "System speakers" }
        return name?.takeRetainedValue() as String? ?? "System speakers"
    }
    var playedMilliseconds: Int {
        let rendered = player.lastRenderTime.flatMap { player.playerTime(forNodeTime: $0) }?.sampleTime ?? playedSamples
        return Int(max(0, min(rendered, scheduledSamples)) * 1000 / 24_000)
    }
    func start() throws {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onFailure?(PracticeError(message: "Your audio output changed. Start a new conversation to reconnect."))
            }
        }
        do { engine.prepare(); try engine.start() }
        catch { stop(); throw PracticeError(message: "Could not start reply playback. Check your sound output and try again.") }
    }
    func enqueue(_ pcm: Data) throws {
        guard !pcm.isEmpty, pcm.count.isMultiple(of: 2), engine.isRunning else {
            throw PracticeError(message: "The tutor returned invalid audio. Please reconnect.")
        }
        let sampleCount = pcm.count / 2
        guard scheduledSamples - playedSamples + Int64(sampleCount) <= 24_000 * 90,
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(sampleCount)),
              let samples = buffer.floatChannelData?[0] else {
            throw PracticeError(message: "The tutor's audio buffer is full. Please reconnect.")
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        pcm.withUnsafeBytes { bytes in
            for index in 0..<sampleCount {
                let raw = UInt16(bytes[index * 2]) | (UInt16(bytes[index * 2 + 1]) << 8)
                samples[index] = Float(Int16(bitPattern: raw)) / 32768
            }
        }
        queuedBuffers += 1
        scheduledSamples += Int64(sampleCount)
        let generation = outputGeneration
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.outputGeneration == generation else { return }
                self.playedSamples += Int64(sampleCount)
                self.queuedBuffers -= 1
                if self.queuedBuffers == 0 { self.onDrained?() }
            }
        }
        if !player.isPlaying { player.play() }
    }

    func stopOutput() {
        outputGeneration = UUID()
        player.stop()
        queuedBuffers = 0; scheduledSamples = 0; playedSamples = 0
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        stopOutput()
        engine.stop()
    }
}
