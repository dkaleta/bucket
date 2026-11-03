import Foundation

struct LessonTag: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let focus: String

    static let all: [LessonTag] = [
        .init(id: "when", title: "Asking when", focus: "Ask when everyday activities happen, using wann; vary activities and situations."),
        .init(id: "time", title: "Telling time", focus: "Times, weekdays, and temporal expressions."),
        .init(id: "where", title: "Asking where", focus: "Ask about locations and destinations with wo and wohin."),
        .init(id: "questions", title: "Asking questions", focus: "Everyday questions and German question word order."),
        .init(id: "requests", title: "Requests", focus: "Polite everyday requests and offers."),
        .init(id: "introductions", title: "Introductions", focus: "Names, origins, age, and introducing yourself."),
        .init(id: "family", title: "Family & pets", focus: "Family, friends, and pets."),
        .init(id: "food", title: "Food & drink", focus: "Eating, drinking, and ordering food."),
        .init(id: "home", title: "Home", focus: "Rooms, household objects, and home life."),
        .init(id: "routine", title: "Daily routines", focus: "Everyday activities and habits."),
        .init(id: "work", title: "Work & study", focus: "Work, school, and learning."),
        .init(id: "travel", title: "Travel", focus: "Transport, trips, and destinations."),
        .init(id: "shopping", title: "Shopping", focus: "Buying things, prices, and payment."),
        .init(id: "weather", title: "Weather", focus: "Weather and seasons."),
        .init(id: "describing", title: "Describing things", focus: "Simple descriptions and adjectives."),
        .init(id: "present", title: "Present tense", focus: "Present-tense verb conjugation and subject agreement."),
        .init(id: "articles", title: "Articles", focus: "Nouns and appropriate definite and indefinite articles."),
        .init(id: "possession", title: "Possession", focus: "Possessives and expressing what someone has."),
        .init(id: "place", title: "Place & direction", focus: "Locations, destinations, and prepositions."),
        .init(id: "separable", title: "Separable verbs", focus: "Common separable verbs and placement of their prefixes."),
        .init(id: "negation", title: "Negation", focus: "Negating statements with nicht and kein."),
        .init(id: "modal", title: "Modal verbs", focus: "Ability, obligation, permission, wishes, and modal word order."),
        .init(id: "commands", title: "Commands", focus: "Simple imperative instructions.")
    ]
    static func find(_ id: String) -> LessonTag? { all.first { $0.id == id } }
    static func builtInTags(for id: Int) -> [String] {
        let special: [Int: [String]] = [
            1:["place","present"], 5:["home","place"], 7:["introductions","present"],
            8:["introductions","place"],9:["introductions","place"],10:["introductions","present"],
            35:["home","place","articles"],36:["home","place","articles"],
            41:["routine","separable","time"],44:["routine","time"],45:["work","place"],
            46:["work","place"],47:["work","present"],50:["routine","time","place"],
            51:["time","present"],52:["time","present"],53:["time","present"],54:["time","work"],
            57:["weather","time","describing"],60:["time","travel"],
            64:["shopping","place"],65:["shopping","food"],66:["shopping","describing"],
            67:["shopping","present"],68:["shopping","present"],69:["travel","place"],70:["travel","place"],
            71:["introductions","questions"],72:["where","introductions"],73:["questions","describing"],
            74:["where","place"],75:["shopping","questions"],76:["time","questions"],
            77:["questions","present"],78:["questions","possession"],79:["when","travel","separable"],
            80:["questions","describing"],85:["requests","commands"],86:["commands","home"],
            87:["requests","present"],88:["requests","present"],89:["requests","possession"],90:["time","routine"],
            92:["modal","requests"],96:["modal","requests","place"],100:["modal","requests"]]
        if let tags = special[id] { return tags }
        switch id {
        case 1...10: return ["describing","present"]
        case 11...20: return ["family","present"]
        case 21...30: return ["food","articles","present"]
        case 31...40: return ["home","articles","describing"]
        case 41...50: return ["routine","present"]
        case 55...59: return ["weather","describing"]
        case 61...70: return ["travel","articles"]
        case 81...84: return ["negation","present"]
        default: return ["modal","present"]
        }
    }
}

struct PracticeSession: Codable {
    var id = UUID()
    var title: String
    var questions: [PracticeSentence]
    var index: Int = 0
    var answer = ""
    var grade: Grade?
    var kind: Kind? = nil
    var focusTagID: String? = nil
    enum Kind: String, Codable { case legacy, mixed, focused }
}

enum PracticeGenerationRequest {
    case mixedBeginner
    case focused(LessonTag, PracticeSentence)
}

@MainActor protocol LessonGenerating {
    func generate(request: PracticeGenerationRequest, count: Int, excluding: [String], apiKey: String) async throws -> [PracticeSentence]
}

@MainActor struct PracticeSessionStore {
    var url: URL
    struct Snapshot: Codable {
        var version = 2
        var sessions: [PracticeSession]
        var recentPrompts: [String]? = nil
        var pendingBatch: Bool? = nil
    }
    static var standard: Self {
        .init(url: URL.applicationSupportDirectory.appending(path: "GermanPractice/session.json"))
    }
    func loadSnapshot() throws -> Snapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard [1,2].contains(snapshot.version),
              snapshot.sessions.allSatisfy({ !$0.questions.isEmpty && $0.questions.indices.contains($0.index) }) else {
            throw PracticeError(message: "Saved practice could not be restored.")
        }
        for index in snapshot.sessions.indices {
            if snapshot.version == 1 {
                snapshot.sessions[index].kind = index == 0 ? .legacy : .focused
            }
            let session = snapshot.sessions[index]
            guard let kind = session.kind,
                  index == 0 ? kind != .focused : kind == .focused else { throw OpenAILessonGenerator.invalid }
            if kind != .legacy {
                try OpenAILessonGenerator.validate(session.questions, count: kind == .mixed ? 10 : session.questions.count)
            }
        }
        snapshot.recentPrompts = Array((snapshot.recentPrompts ?? []).suffix(200))
        return snapshot
    }
    func load() throws -> [PracticeSession]? { try loadSnapshot()?.sessions }
    func save(_ sessions: [PracticeSession], recentPrompts: [String] = [], pendingBatch: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let snapshot = Snapshot(sessions: sessions, recentPrompts: Array(recentPrompts.suffix(200)), pendingBatch: pendingBatch)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}

/// A bounded, shared history for both main practice and focused lessons.
enum QuestionHistory {
    static func normalize(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func adding(_ prompts: [String], to history: [String]) -> [String] {
        var seen = Set<String>()
        return Array((history + prompts).reversed().filter {
            let key = normalize($0)
            return !key.isEmpty && seen.insert(key).inserted
        }.prefix(200).reversed())
    }
}
