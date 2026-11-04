import AVFoundation
import Foundation
import Testing
@testable import GermanPractice

@MainActor private final class TestCapture: LocalMicrophoneCapturing {
    var selectedID: String?
    var sink: AsyncThrowingStream<Data, Error>.Continuation?
    var stops = 0
    var deny = false
    var suspend = false
    var waiter: CheckedContinuation<Void, Never>?
    func start(deviceID: String) async throws -> AsyncThrowingStream<Data, Error> {
        selectedID = deviceID
        if deny { throw PracticeError(message: "Microphone permission denied") }
        if suspend { await withCheckedContinuation { waiter = $0 } }
        return AsyncThrowingStream { sink = $0 }
    }
    func stop() { stops += 1; sink?.finish(); sink = nil }
}
@MainActor private final class TestRecordingPlayer: SpeechPlaying {
    var data: Data?
    var plays = 0
    var stops = 0
    func play(_ data: Data) async throws { self.data = data; plays += 1 }
    func stop() { stops += 1 }
}
@Suite @MainActor struct MicrophoneTestTests {
    private let device = MicrophoneDevice(id: "usb-mic", name: "USB microphone")
    private func settle(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Microphone test did not settle")
    }
    @Test func recordsSelectedDeviceAndPlaysOnlyOnDemand() async throws {
        let capture = TestCapture(), player = TestRecordingPlayer()
        let test = MicrophoneTest(makeCapture: { capture }, player: player)
        #expect(capture.selectedID == nil)
        test.start(device: device)
        try await settle { test.phase == .recording }
        #expect(capture.selectedID == "usb-mic")
        capture.sink?.yield(TutorPCM.testTone())
        try await settle { test.seconds > 0 }
        #expect(test.level > 0.5)
        #expect(player.plays == 0)
        test.stopRecording()
        try await settle { test.phase == .recorded }
        #expect(test.message.contains("Sound detected"))
        #expect(test.canPlay)
        test.togglePlayback()
        try await settle { test.phase == .recorded }
        #expect(player.plays == 1)
        let wav = try #require(player.data)
        let decoded = try AVAudioPlayer(data: wav)
        #expect(decoded.numberOfChannels == 1)
        #expect(abs(decoded.duration - 0.3) < 0.001)
        #expect(wav.suffix(14_400) == TutorPCM.testTone())
        test.reset()
        #expect(!test.canPlay && test.seconds == 0 && test.peakLevel == 0)
    }
    @Test func silenceAndMissingBuffersAreNotReportedAsSuccessfulSound() async throws {
        let capture = TestCapture()
        let test = MicrophoneTest(makeCapture: { capture }, player: TestRecordingPlayer())
        test.start(device: device)
        try await settle { test.phase == .recording }
        capture.sink?.yield(Data(count: 4800))
        try await settle { test.seconds > 0 }
        test.stopRecording()
        try await settle { test.phase == .recorded }
        #expect(test.peakLevel == 0)
        #expect(test.message.contains("no measurable sound"))
        test.start(device: device)
        try await settle { test.phase == .recording }
        test.stopRecording()
        try await settle { test.phase == .recorded }
        #expect(!test.canPlay)
        #expect(test.message.contains("No audio arrived"))
    }
    @Test func recordingHasTimeAndMemoryBounds() async throws {
        let capture = TestCapture()
        let test = MicrophoneTest(duration: 0.1, makeCapture: { capture }, player: TestRecordingPlayer())
        test.start(device: device)
        try await settle { test.phase == .recording }
        capture.sink?.yield(Data(count: 100_000))
        try await settle { test.phase == .recorded }
        #expect(test.seconds == 0.1)
        #expect(capture.stops > 0)
        test.start(device: device)
        try await settle { test.phase == .recorded }
        #expect(test.message.contains("No audio arrived"))
    }
    @Test func closingDuringPermissionRequestRejectsLateCapture() async throws {
        let capture = TestCapture()
        capture.suspend = true
        let test = MicrophoneTest(makeCapture: { capture }, player: TestRecordingPlayer())
        test.start(device: device)
        try await settle { capture.waiter != nil }
        test.reset()
        capture.waiter?.resume(); capture.waiter = nil
        try await settle { capture.stops >= 2 }
        #expect(test.phase == .idle)
        #expect(capture.sink == nil)
        #expect(!test.canPlay)
    }
    @Test func permissionAndCaptureFailuresAreVisible() async throws {
        let capture = TestCapture()
        capture.deny = true
        let test = MicrophoneTest(makeCapture: { capture }, player: TestRecordingPlayer())
        test.start(device: device)
        try await settle { test.phase == .failed }
        #expect(test.errorMessage?.contains("permission") == true)
        capture.deny = false
        test.start(device: device)
        try await settle { test.phase == .recording }
        capture.sink?.finish(throwing: PracticeError(message: "Device unplugged"))
        try await settle { test.phase == .failed }
        #expect(test.errorMessage == "Device unplugged")
        #expect(capture.sink == nil)
    }
}
