import Foundation

struct PracticeSentence: Identifiable, Sendable {
    let id: Int
    let english: String
    let german: String
}

struct Grade: Codable, Equatable, Sendable {
    let score: Int
    let germanAnswer: String
    let tip: String?
}

struct PracticeError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

enum TranscriptionEvent: Sendable {
    case partial(String)
    case committed(String)
}

struct TranscriptAccumulator {
    private(set) var committed: [String] = []
    private(set) var partial = ""
    var text: String { (committed + [partial]).filter { !$0.isEmpty }.joined(separator: " ") }

    mutating func apply(_ event: TranscriptionEvent) {
        switch event {
        case .partial(let text): partial = text
        case .committed(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { committed.append(text) }
            partial = ""
        }
    }
}

@MainActor protocol Transcribing: AnyObject {
    var onEvent: ((TranscriptionEvent) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
    func start(apiKey: String) async throws
    func stop() async throws
    func cancel()
}

@MainActor protocol Grading {
    func grade(sentence: PracticeSentence, answer: String, apiKey: String) async throws -> Grade
}

@MainActor protocol CredentialStoring {
    func read(_ provider: APIProvider) throws -> String
    func save(_ key: String, for provider: APIProvider) throws
}

enum APIProvider: String, CaseIterable {
    case elevenLabs = "ElevenLabs"
    case openAI = "OpenAI"
}
