import Foundation

@MainActor final class ElevenLabsTranscriber: Transcribing {
    var onEvent: ((TranscriptionEvent) -> Void)?
    var onFailure: ((Error) -> Void)?
    private let microphone = MicrophoneCapture()
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var finalWaiter: CheckedContinuation<Void, Error>?
    private var finalRequested = false
    private var finalReceived = false
    private var cancelled = false
    private var failure: Error?
    private var audioBytes = 0

    func start(apiKey: String) async throws {
        try await MicrophoneCapture.requestPermission()
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        var url = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        url.queryItems = [
            .init(name: "model_id", value: "scribe_v2_realtime"),
            .init(name: "audio_format", value: "pcm_16000"),
            .init(name: "language_code", value: "de"),
            .init(name: "commit_strategy", value: "manual"),
            .init(name: "no_verbatim", value: "false")
        ]
        var request = URLRequest(url: url.url!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let connection = URLSession.shared.webSocketTask(with: request)
        socket = connection
        connection.resume()
        armTimeout(seconds: 12, message: "Could not connect to ElevenLabs. Check your API key and connection.")
        do {
            let first = try await receive(connection)
            guard first.type == "session_started" else { throw apiError(first.type) }
            timeout?.cancel()
            try Task.checkCancellation()
            guard !cancelled, failure == nil else { throw failure ?? CancellationError() }
            let audio = try microphone.start()
            receiver = Task { [weak self] in
                guard let self else { return }
                do {
                    while !Task.isCancelled {
                        let event = try await receive(connection)
                        switch event.type {
                        case "partial_transcript": onEvent?(.partial(event.text ?? ""))
                        case "committed_transcript":
                            onEvent?(.committed(event.text ?? ""))
                            if finalRequested {
                                finalReceived = true
                                finalWaiter?.resume()
                                finalWaiter = nil
                            }
                        case "warning", "session_started": break
                        default:
                            if event.error != nil || event.type.contains("error") || event.type.contains("limit") || event.type.contains("exceeded") {
                                throw apiError(event.type)
                            }
                        }
                    }
                } catch { if !cancelled { fail(error) } }
            }
            sender = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await chunk in audio {
                        try Task.checkCancellation()
                        try await send(chunk, connection: connection)
                        audioBytes += chunk.count
                    }
                } catch {
                    if !cancelled { fail(error) }
                    throw error
                }
            }
        } catch {
            let reported = failure ?? error
            cancel()
            throw reported
        }
    }

    func stop() async throws {
        guard let connection = socket, !cancelled else { throw CancellationError() }
        microphone.stop()
        armTimeout(seconds: 15, message: "Transcription took too long. Review the available text or record again.")
        defer { timeout?.cancel() }
        try await sender?.value
        try Task.checkCancellation()
        if let failure { throw failure }
        // Processing requires at least two seconds. Also leave a short silence after the last word.
        let padding = max(8_000, 64_000 - audioBytes)
        try await send(Data(count: padding), connection: connection)
        finalRequested = true
        try await send(Data(), connection: connection, commit: true)
        if let failure { throw failure }
        guard !cancelled else { throw CancellationError() }
        if !finalReceived {
            try await withCheckedThrowingContinuation { finalWaiter = $0 }
        }
    }

    func cancel() {
        cancelled = true
        microphone.stop()
        timeout?.cancel()
        sender?.cancel()
        receiver?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        finalWaiter?.resume(throwing: CancellationError())
        finalWaiter = nil
    }

    private struct Event: Decodable {
        let type: String
        let text: String?
        let error: String?
        enum CodingKeys: String, CodingKey { case type = "message_type", text, error }
    }

    private func receive(_ connection: URLSessionWebSocketTask) async throws -> Event {
        let message = try await connection.receive()
        let data: Data
        switch message {
        case .data(let bytes): data = bytes
        case .string(let text): data = Data(text.utf8)
        @unknown default: throw PracticeError(message: "Received an unsupported transcription response.")
        }
        return try JSONDecoder().decode(Event.self, from: data)
    }

    private func send(_ data: Data, connection: URLSessionWebSocketTask, commit: Bool = false) async throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "message_type": "input_audio_chunk", "audio_base_64": data.base64EncodedString(),
            "sample_rate": 16000, "commit": commit
        ])
        try await connection.send(.string(String(decoding: payload, as: UTF8.self)))
    }

    private func armTimeout(seconds: Double, message: String) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.fail(PracticeError(message: message))
        }
    }

    private func fail(_ error: Error) {
        guard failure == nil, !cancelled else { return }
        failure = error
        microphone.stop()
        socket?.cancel(with: .goingAway, reason: nil)
        finalWaiter?.resume(throwing: error)
        finalWaiter = nil
        onFailure?(error)
    }

    private func apiError(_ type: String) -> Error {
        let message: String
        switch type {
        case "auth_error": message = "Check your ElevenLabs API key in Settings."
        case "quota_exceeded", "rate_limited", "throttled", "concurrent_session_limit_exceeded":
            message = "ElevenLabs' usage limit was reached. Check your balance or try again shortly."
        case "unaccepted_terms": message = "Accept the speech-to-text terms in your ElevenLabs account, then try again."
        default: message = "ElevenLabs could not transcribe this recording. Please try again."
        }
        return PracticeError(message: message)
    }
}
