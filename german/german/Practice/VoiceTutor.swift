import Foundation
import Observation
import WebKit

struct TutorContext: Identifiable, Codable, Sendable {
    var id = UUID()
    let lesson: String
    let question: String
    let referenceGerman: String
    let learnerAnswer: String
    let grade: Grade?
    let tags: [String]

    init(lesson: String, sentence: PracticeSentence, answer: String, grade: Grade?) {
        self.lesson = lesson
        question = sentence.english
        referenceGerman = sentence.german
        learnerAnswer = answer
        self.grade = grade
        tags = sentence.tagIDs.compactMap { LessonTag.find($0)?.title }
    }
}

enum TutorStatus: String {
    case listening = "Listening", hearing = "Hearing you", thinking = "Thinking…", speaking = "Speaking"
}
struct TutorMessage: Identifiable {
    enum Role: String { case learner = "You", tutor = "Tutor" }
    let id: String
    let role: Role
    var text: String
}
enum TutorEvent {
    case status(TutorStatus)
    case input(level: Double, secondsSent: Double)
    case devices(input: String, output: String)
    case notice(String?)
    case playback(String)
    case transcript(id: String, role: TutorMessage.Role, text: String, append: Bool)
}

@MainActor protocol TutorConnecting: AnyObject {
    var isFullDuplex: Bool { get }
    var onEvent: ((TutorEvent) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
    func connect(context: TutorContext, apiKey: String) async throws
    func setMuted(_ muted: Bool)
    func testSpeaker() throws
    func interrupt() async throws
    func disconnect()
}

extension TutorConnecting { var isFullDuplex: Bool { false } }

@MainActor @Observable final class VoiceTutor {
    enum Phase { case idle, connecting, active, ended, failed }
    private(set) var phase: Phase = .idle
    private(set) var status: TutorStatus = .listening
    private(set) var messages: [TutorMessage] = []
    private(set) var errorMessage: String?
    private(set) var isMuted = false
    private(set) var inputLevel = 0.0
    private(set) var secondsSent = 0.0
    private(set) var inputDevice = "System microphone"
    private(set) var outputDevice = "System speakers"
    private(set) var notice: String?
    private(set) var playbackStatus = "No reply audio yet"
    var canTestSpeaker: Bool { phase == .active && status == .listening }
    var canInterrupt: Bool { phase == .active && status == .speaking && !isFullDuplex }
    var inputPausedForReply: Bool { phase == .active && status == .speaking && !isFullDuplex }
    var isFullDuplex: Bool { connection?.isFullDuplex == true }
    var webView: WKWebView? { (connection as? OpenAILiveTutor)?.webView }
    private let credentials: any CredentialStoring
    private let makeConnection: () -> any TutorConnecting
    private var connection: (any TutorConnecting)?
    private var task: Task<Void, Never>?
    private var attempt = UUID()

    init(credentials: any CredentialStoring, makeConnection: (() -> any TutorConnecting)? = nil) {
        self.credentials = credentials
        self.makeConnection = makeConnection ?? { OpenAILiveTutor() }
    }

    func start(context: TutorContext) {
        guard phase != .connecting && phase != .active else { return }
        stop()
        messages = []
        errorMessage = nil
        isMuted = false
        inputLevel = 0
        secondsSent = 0
        notice = nil
        playbackStatus = "No reply audio yet"
        phase = .connecting
        let id = attempt
        task = Task { [weak self] in
            guard let self, self.attempt == id, !Task.isCancelled else { return }
            do {
                let key = try credentials.read(.openAI)
                guard !key.isEmpty else { throw PracticeError(message: "Add your OpenAI API key in Settings to talk to the tutor.") }
                let service = makeConnection()
                connection = service
                service.onEvent = { [weak self] event in
                    guard let self, self.attempt == id else { return }
                    switch event {
                    case .status(let status): self.status = status
                    case let .input(level, seconds):
                        self.inputLevel = self.isMuted ? 0 : level
                        self.secondsSent = seconds
                    case let .devices(input, output): self.inputDevice = input; self.outputDevice = output
                    case .notice(let text): self.notice = text
                    case .playback(let text): self.playbackStatus = text
                    case let .transcript(messageID, role, text, append):
                        if let index = self.messages.firstIndex(where: { $0.id == messageID }) {
                            if append { self.messages[index].text += text }
                            else { self.messages[index].text = text }
                        } else { self.messages.append(TutorMessage(id: messageID, role: role, text: text)) }
                    }
                }
                service.onFailure = { [weak self] error in
                    guard let self, self.attempt == id else { return }
                    self.fail(error)
                }
                try await service.connect(context: context, apiKey: key)
                guard attempt == id, !Task.isCancelled else { service.disconnect(); return }
                phase = .active
            } catch {
                guard attempt == id, !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    func toggleMute() {
        guard phase == .active else { return }
        isMuted.toggle()
        inputLevel = 0
        connection?.setMuted(isMuted)
    }

    func testSpeaker() {
        guard canTestSpeaker else { return }
        do { try connection?.testSpeaker() }
        catch { notice = error.localizedDescription }
    }

    func interrupt() {
        guard canInterrupt else { return }
        let id = attempt
        task = Task { [weak self] in
            guard let self else { return }
            do { try await connection?.interrupt() }
            catch {
                guard attempt == id, !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    func stop() {
        attempt = UUID()
        task?.cancel(); task = nil
        connection?.onEvent = nil
        connection?.onFailure = nil
        connection?.disconnect(); connection = nil
        isMuted = false
        inputLevel = 0
        phase = .ended
    }

    private func fail(_ error: Error) {
        stop()
        errorMessage = error.localizedDescription
        phase = .failed
    }
}
