import Foundation
import Observation

@MainActor @Observable
final class PracticeViewModel {
    enum Phase { case idle, connecting, recording, finalizing, ready, grading, graded }
    private(set) var phase: Phase = .idle
    private(set) var index: Int
    private(set) var grade: Grade?
    private(set) var errorMessage: String?
    var answer = "" { didSet { scheduleSave() } }
    private(set) var sessions: [PracticeSession] = []
    private(set) var preparingTag: LessonTag?
    private(set) var lessonError: String?
    private(set) var isPreparing = false
    private(set) var preparingCount = 10
    private(set) var recentPrompts: [String] = []
    private(set) var preparingMain = false
    private var pendingBatch = false
    private var didAttemptInitialBatch = false
    var needsMainBatch: Bool { sessions.isEmpty || (sessions.count == 1 && sessions[0].kind == .legacy) }
    var mainBatchActionTitle: String { pendingBatch ? "Retry preparing 10 questions" : "Prepare 10 questions" }
    var hasQuestion: Bool { !sessions.isEmpty }
    var showsGeneration: Bool { preparingMain || preparingTag != nil }
    private let generator: any LessonGenerating
    private var sessionStore: PracticeSessionStore?
    private var saveTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var generationID = UUID()

    private let credentials: any CredentialStoring
    private let makeTranscriber: () -> any Transcribing
    private let grader: any Grading
    private let defaults: UserDefaults
    private var transcriber: (any Transcribing)?
    private var transcript = TranscriptAccumulator()
    private var task: Task<Void, Never>?
    private var attemptID = UUID()

    var sentence: PracticeSentence { sessions.last!.questions[index] }
    var sessionID: UUID { sessions.last!.id }
    var title: String { sessions.last?.title ?? "German practice" }
    var parentTitle: String? { sessions.dropLast().last?.title }
    var breadcrumbs: String { sessions.map(\.title).joined(separator: " › ") }
    var canStartLesson: Bool { hasQuestion && !showsGeneration && (phase == .idle || phase == .ready || phase == .graded) }
    var tags: [LessonTag] { sentence.tagIDs.compactMap(LessonTag.find) }
    var progress: String { "\(index + 1) / \(sessions.last!.questions.count)" }
    var isLast: Bool { index == sessions.last!.questions.count - 1 }
    var canCheck: Bool {
        hasQuestion && !showsGeneration && (phase == .idle || phase == .ready)
            && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(credentials: any CredentialStoring, grader: any Grading,
         defaults: UserDefaults = .standard,
         generator: (any LessonGenerating)? = nil,
         sessionStore: PracticeSessionStore? = nil, makeTranscriber: @escaping () -> any Transcribing) {
        self.credentials = credentials
        self.grader = grader
        self.defaults = defaults
        self.generator = generator ?? OpenAILessonGenerator()
        self.sessionStore = sessionStore
        self.makeTranscriber = makeTranscriber
        index = min(max(defaults.integer(forKey: "practice.sentenceIndex"), 0), Sentences.all.count - 1)
        if defaults.object(forKey: "practice.sentenceIndex") != nil {
            sessions = [PracticeSession(title: "German practice", questions: Sentences.all, index: index, kind: .legacy)]
        }
        do {
            if let restored = try sessionStore?.loadSnapshot() {
                sessions = restored.sessions
                recentPrompts = restored.recentPrompts ?? []
                pendingBatch = restored.pendingBatch ?? false
                didAttemptInitialBatch = pendingBatch
                restoreCurrent()
            }
        } catch {
            // Preserve the original bytes before allowing a fresh snapshot to replace them.
            if let store = self.sessionStore {
                do {
                    try FileManager.default.copyItem(at: store.url, to: store.url.appendingPathExtension("unreadable-" + UUID().uuidString))
                } catch { self.sessionStore = nil }
            }
            errorMessage = "Saved lessons could not be restored. Start a fresh batch to continue."
        }
    }

    func record() {
        guard hasQuestion, !showsGeneration else { return }
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
                saveProgress()
            } catch { recover(error, id: id) }
        }
    }

    func retry() {
        cancelWork()
        answer = ""
        grade = nil
        errorMessage = nil
        phase = .idle
        saveProgress()
    }

    func next() {
        guard phase == .graded else { return }
        if isLast && sessions.count > 1 { returnToParent(); return }
        if isLast { startMainBatch(); return }
        index += 1
        if sessions.count == 1 && sessions[0].kind == .legacy { defaults.set(index, forKey: "practice.sentenceIndex") }
        retry()
    }

    func leave() {
        cancelWork()
        if phase != .graded { phase = answer.isEmpty ? .idle : .ready }
        cancelLesson()
        saveProgress()
    }

    func prepareInitialBatchIfNeeded() {
        guard needsMainBatch, !didAttemptInitialBatch else { return }
        didAttemptInitialBatch = true
        startMainBatch()
    }

    func retryGeneration() {
        if preparingMain { startMainBatch() }
        else if let tag = preparingTag { startLesson(tag) }
    }

    func startMainBatch() {
        guard !isPreparing, sessions.count <= 1,
              needsMainBatch || (phase == .graded && isLast) else { return }
        didAttemptInitialBatch = true
        preparingMain = true
        pendingBatch = true
        preparingCount = 10
        isPreparing = true
        lessonError = nil
        saveProgress()
        let id = UUID()
        generationID = id
        let excluded = Sentences.all.map(\.english) + recentPrompts + (sessions.first?.questions.map(\.english) ?? [])
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try credentials.read(.openAI)
                guard !key.isEmpty else { throw PracticeError(message: "Add your OpenAI API key in Settings to prepare practice questions.") }
                let questions = try await generator.generate(request: .mixedBeginner, count: 10, excluding: excluded, apiKey: key)
                guard generationID == id, !Task.isCancelled else { return }
                try OpenAILessonGenerator.validate(questions, count: 10)
                let next = PracticeSession(title: "German practice", questions: questions, kind: .mixed)
                let history = Array((recentPrompts + questions.map(\.english)).suffix(200))
                // Persist the validated replacement before discarding the current batch.
                try sessionStore?.save([next], recentPrompts: history)
                cancelWork()
                sessions = [next]
                recentPrompts = history
                pendingBatch = false
                preparingMain = false
                isPreparing = false
                restoreCurrent()
                saveProgress()
            } catch {
                guard generationID == id, !Task.isCancelled else { return }
                isPreparing = false
                lessonError = error.localizedDescription
            }
        }
    }

    func startLesson(_ tag: LessonTag) {
        guard canStartLesson || (preparingTag?.id == tag.id && !isPreparing) else { return }
        saveProgress()
        preparingTag = tag
        lessonError = nil
        isPreparing = true
        let id = UUID()
        generationID = id
        let source = sentence
        let excluded = sessions.last!.questions.map(\.english)
        let preference = defaults.integer(forKey: "practice.lessonSize")
        let count = [5,10,20].contains(preference) ? preference : 10
        preparingCount = count
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try credentials.read(.openAI)
                guard !key.isEmpty else { throw PracticeError(message: "Add your OpenAI API key in Settings to prepare a lesson.") }
                let questions = try await generator.generate(request: .focused(tag, source), count: count, excluding: excluded, apiKey: key)
                guard generationID == id, !Task.isCancelled else { return }
                try OpenAILessonGenerator.validate(questions, count: count)
                cancelWork()
                sessions.append(PracticeSession(title: tag.title, questions: questions, kind: .focused))
                restoreCurrent()
                preparingTag = nil
                isPreparing = false
                saveProgress()
            } catch {
                guard generationID == id, !Task.isCancelled else { return }
                isPreparing = false
                lessonError = error.localizedDescription
            }
        }
    }

    func cancelLesson() {
        generationID = UUID()
        generationTask?.cancel()
        generationTask = nil
        preparingTag = nil
        preparingMain = false
        isPreparing = false
        lessonError = nil
        // Preserve the interrupted marker so reopening does not silently retry generation.
        saveProgress()
    }

    func returnToParent() {
        guard sessions.count > 1 else { return }
        cancelLesson()
        cancelWork()
        sessions.removeLast()
        restoreCurrent()
        saveProgress()
        if needsMainBatch { startMainBatch() }
    }

    private func restoreCurrent() {
        guard let current = sessions.last else { return }
        index = current.index
        answer = current.answer
        grade = current.grade
        errorMessage = nil
        phase = grade != nil ? .graded : answer.isEmpty ? .idle : .ready
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.saveProgress()
        }
    }

    func saveProgress() {
        saveTask?.cancel()
        guard !sessions.isEmpty else {
            do { try sessionStore?.save([], recentPrompts: recentPrompts, pendingBatch: pendingBatch) }
            catch { errorMessage = "Your progress could not be saved on this Mac." }
            return
        }
        let last = sessions.count - 1
        sessions[last].index = index
        sessions[last].answer = answer
        sessions[last].grade = phase == .graded ? grade : nil
        do { try sessionStore?.save(sessions, recentPrompts: recentPrompts, pendingBatch: pendingBatch) }
        catch { errorMessage = "Your progress could not be saved on this Mac." }
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
