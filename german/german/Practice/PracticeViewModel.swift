import Foundation
import Observation

@MainActor @Observable
final class PracticeViewModel {
    enum Phase { case idle, connecting, recording, finalizing, ready, grading, graded }
    private(set) var phase: Phase = .idle
    private(set) var index: Int
    private(set) var grade: Grade?
    private(set) var errorMessage: String?
    var answer = ""

    private let credentials: any CredentialStoring
    private let makeTranscriber: () -> any Transcribing
    private let grader: any Grading
    private let defaults: UserDefaults
    private var transcriber: (any Transcribing)?
    private var transcript = TranscriptAccumulator()
    private var task: Task<Void, Never>?
    private var attemptID = UUID()

    var sentence: PracticeSentence { Sentences.all[index] }
    var progress: String { "\(index + 1) / \(Sentences.all.count)" }
    var isLast: Bool { index == Sentences.all.count - 1 }
    var canCheck: Bool {
        (phase == .idle || phase == .ready)
            && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(credentials: any CredentialStoring, grader: any Grading,
         defaults: UserDefaults = .standard, makeTranscriber: @escaping () -> any Transcribing) {
        self.credentials = credentials
        self.grader = grader
        self.defaults = defaults
        self.makeTranscriber = makeTranscriber
        index = min(max(defaults.integer(forKey: "practice.sentenceIndex"), 0), Sentences.all.count - 1)
    }

    func record() {
        cancelWork()
        answer = ""
        grade = nil
        errorMessage = nil
        transcript = TranscriptAccumulator()
        phase = .connecting
        let id = attemptID
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try credentials.read(.elevenLabs)
                guard !key.isEmpty else { throw PracticeError(message: "Add your ElevenLabs API key in Settings to record.") }
                let service = makeTranscriber()
                transcriber = service
                service.onEvent = { [weak self] event in
                    guard let self, self.attemptID == id,
                          self.phase == .recording || self.phase == .finalizing else { return }
                    self.transcript.apply(event)
                    self.answer = self.transcript.text
                }
                service.onFailure = { [weak self] error in
                    guard let self, self.attemptID == id else { return }
                    self.recover(error, id: id)
                }
                try await service.start(apiKey: key)
                guard attemptID == id, !Task.isCancelled else { return }
                phase = .recording
            } catch {
                recover(error, id: id)
            }
        }
    }

    func stop() {
        guard phase == .recording, let service = transcriber else { return }
        phase = .finalizing
        let id = attemptID
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.stop()
                guard attemptID == id, !Task.isCancelled else { return }
                service.cancel()
                transcriber = nil
                phase = .ready
                if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errorMessage = "No speech was detected. Try recording again."
                }
            } catch { recover(error, id: id) }
        }
    }

    func check() {
        guard canCheck else { return }
        phase = .grading
        errorMessage = nil
        let id = attemptID
        let submittedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedSentence = sentence
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try credentials.read(.openAI)
                guard !key.isEmpty else { throw PracticeError(message: "Add your OpenAI API key in Settings to check your answer.") }
                let result = try await grader.grade(sentence: submittedSentence, answer: submittedAnswer, apiKey: key)
                guard attemptID == id, !Task.isCancelled else { return }
                grade = result
                phase = .graded
            } catch { recover(error, id: id) }
        }
    }

    func retry() {
        cancelWork()
        answer = ""
        grade = nil
        errorMessage = nil
        phase = .idle
    }

    func next() {
        guard phase == .graded else { return }
        index = isLast ? 0 : index + 1
        defaults.set(index, forKey: "practice.sentenceIndex")
        retry()
    }

    func leave() {
        cancelWork()
        if phase != .graded { phase = answer.isEmpty ? .idle : .ready }
    }

    private func recover(_ error: Error, id: UUID) {
        guard id == attemptID else { return }
        cancelWork()
        errorMessage = error.localizedDescription
        phase = answer.isEmpty ? .idle : .ready
    }

    private func cancelWork() {
        attemptID = UUID()
        task?.cancel()
        task = nil
        transcriber?.cancel()
        transcriber = nil
    }
}
