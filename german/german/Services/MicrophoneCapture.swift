import AVFoundation
import Foundation

// The audio tap owns this converter and invokes it serially, away from the main actor.
nonisolated private final class PCMEncoder: @unchecked Sendable {
    let converter: AVAudioConverter
    let outputFormat: AVAudioFormat

    init(inputFormat: AVAudioFormat) throws {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: output) else {
            throw PracticeError(message: "This microphone's audio format is not supported.")
        }
        self.converter = converter
        outputFormat = output
    }

    func encode(_ input: AVAudioPCMBuffer) throws -> Data {
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw PracticeError(message: "Could not prepare microphone audio.")
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, let samples = output.floatChannelData?[0] else {
            throw PracticeError(message: "Could not convert microphone audio. Please record again.")
        }
        var data = Data(capacity: Int(output.frameLength) * 2)
        for index in 0..<Int(output.frameLength) {
            let sample = samples[index].isFinite ? samples[index] : 0
            var value = Int16(max(-1, min(1, sample)) * 32767).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}

@MainActor final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var tapInstalled = false

    static func requestPermission() async throws {
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard allowed else {
            throw PracticeError(message: "Allow microphone access in System Settings → Privacy & Security → Microphone, then try again.")
        }
    }

    func start() throws -> AsyncThrowingStream<Data, Error> {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw PracticeError(message: "No microphone is available. Connect one and try again.")
        }
        let encoder = try PCMEncoder(inputFormat: format)
        let (stream, sink) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(50))
        continuation = sink
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 10), format: format) { buffer, _ in
            do {
                let data = try encoder.encode(buffer)
                if case .dropped = sink.yield(data) {
                    sink.finish(throwing: PracticeError(message: "The connection could not keep up with recording. Please try again."))
                }
            } catch { sink.finish(throwing: error) }
        }
        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw PracticeError(message: "Could not start the microphone. Check your input device and try again.")
        }
        return stream
    }

    func stop() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        continuation?.finish()
        continuation = nil
    }
}
