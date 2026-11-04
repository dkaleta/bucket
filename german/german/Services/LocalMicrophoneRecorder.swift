import AVFoundation
import Foundation

struct MicrophoneDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

@MainActor protocol LocalMicrophoneCapturing: AnyObject {
    func start(deviceID: String) async throws -> AsyncThrowingStream<Data, Error>
    func stop()
}

/// Shared capture for the Settings microphone test and voice tutor. All session state belongs to queue.
/// Audio stays in memory; this service has no provider or credential dependencies.
nonisolated final class LocalMicrophoneRecorder: NSObject, LocalMicrophoneCapturing,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "GermanPractice.MicrophoneCapture")
    private let session = AVCaptureSession()
    private var sink: AsyncThrowingStream<Data, Error>.Continuation?
    private var closed = false
    private var observers: [NSObjectProtocol] = []

    static func devices() -> [MicrophoneDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
    }
    static var defaultDeviceID: String { AVCaptureDevice.default(for: .audio)?.uniqueID ?? "" }

    func start(deviceID: String) async throws -> AsyncThrowingStream<Data, Error> {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw PracticeError(message: "Microphone access is denied. Enable German Practice in System Settings → Privacy & Security → Microphone.")
        }
        try Task.checkCancellation()
        let (stream, sink) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(50))
        queue.async { [self] in
            guard !closed else { sink.finish(throwing: CancellationError()); return }
            self.sink = sink
            do {
                guard let device = AVCaptureDevice(uniqueID: deviceID), device.hasMediaType(.audio) else {
                    throw PracticeError(message: "That microphone is no longer connected. Refresh the list and choose another input.")
                }
                try configure(device)
                for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                        guard let self else { return }
                        self.queue.async { [self] in
                            self.finish(PracticeError(message: "Microphone capture was interrupted. Check the selected device and try again."))
                        }
                    })
                }
                session.startRunning()
                if !session.isRunning { throw PracticeError(message: "The microphone could not start. Try another input device.") }
            } catch { finish(error) }
        }
        return stream
    }

    private func configure(_ device: AVCaptureDevice) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw PracticeError(message: "This microphone cannot be used for the test.") }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw PracticeError(message: "Could not prepare microphone capture.") }
        session.addOutput(output)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !closed, let sink else { return }
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM, format.mSampleRate == 24_000,
              format.mChannelsPerFrame == 1, format.mBitsPerChannel == 16,
              format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            finish(PracticeError(message: "The microphone returned an unsupported recording format.")); return
        }
        let count = CMBlockBufferGetDataLength(block)
        guard count > 0, count <= 1_000_000, count.isMultiple(of: 2) else { return }
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: $0.baseAddress!)
        }
        guard result == kCMBlockBufferNoErr else {
            finish(PracticeError(message: "Could not read microphone audio.")); return
        }
        if case .dropped = sink.yield(data) {
            finish(PracticeError(message: "Microphone capture could not keep up. Please try again."))
        }
    }

    func stop() { queue.async { [self] in finish(nil) } }

    private func finish(_ error: Error?) {
        guard !closed else { return }
        closed = true
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        session.stopRunning()
        for output in session.outputs {
            (output as? AVCaptureAudioDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
        }
        sink?.finish(throwing: error); sink = nil
    }
}

nonisolated enum MicrophoneTestWAV {
    static func encode(_ pcm: Data) -> Data {
        var result = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ number: T) {
            var value = number.littleEndian
            withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        }
        append(UInt32(36 + pcm.count)); result.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(24_000)); append(UInt32(48_000)); append(UInt16(2)); append(UInt16(16))
        result.append(Data("data".utf8)); append(UInt32(pcm.count)); result.append(pcm)
        return result
    }
}
