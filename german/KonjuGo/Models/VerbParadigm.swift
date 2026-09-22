import Foundation

enum VerbMood: String, CaseIterable, Identifiable, Sendable {
    case indicative, subjunctiveI, subjunctiveII, imperative
    var id: String { rawValue }
    var title: String {
        switch self {
        case .indicative: "Indikativ"
        case .subjunctiveI: "Konjunktiv I"
        case .subjunctiveII: "Konjunktiv II"
        case .imperative: "Imperativ"
        }
    }
    var forms: [VerbTense] { VerbTense.allCases.filter { $0.mood == self } }
}

enum VerbTense: String, CaseIterable, Codable, Identifiable, Sendable {
    case praesens, praeteritum, perfekt, plusquamperfekt, futurI, futurII
    case konjunktivIPraesens, konjunktivIPerfekt, konjunktivIFuturI, konjunktivIFuturII
    case konjunktivIIPraeteritum, konjunktivIIPlusquamperfekt, konjunktivIIWuerde, konjunktivIIFuturII
    case imperativ
    var id: String { rawValue }
    var mood: VerbMood {
        switch self {
        case .praesens, .praeteritum, .perfekt, .plusquamperfekt, .futurI, .futurII: .indicative
        case .konjunktivIPraesens, .konjunktivIPerfekt, .konjunktivIFuturI, .konjunktivIFuturII: .subjunctiveI
        case .konjunktivIIPraeteritum, .konjunktivIIPlusquamperfekt, .konjunktivIIWuerde, .konjunktivIIFuturII: .subjunctiveII
        case .imperativ: .imperative
        }
    }
    var persons: [VerbPerson] {
        self == .imperativ ? [.du, .ihr, .formalSie] : VerbPerson.statementCases
    }
    var hasDetachedPrefix: Bool {
        [.praesens, .praeteritum, .konjunktivIPraesens, .konjunktivIIPraeteritum, .imperativ].contains(self)
    }
    var shortTitle: String {
        switch self {
        case .praesens, .konjunktivIPraesens: "Präsens"
        case .praeteritum: "Präteritum"
        case .perfekt, .konjunktivIPerfekt: "Perfekt"
        case .plusquamperfekt: "Plusquamperfekt"
        case .futurI, .konjunktivIFuturI: "Futur I"
        case .futurII, .konjunktivIFuturII, .konjunktivIIFuturII: "Futur II"
        case .konjunktivIIPraeteritum: "Gegenwart · Präteritumform"
        case .konjunktivIIPlusquamperfekt: "Vergangenheit · Plusquamperfekt"
        case .konjunktivIIWuerde: "würde-Form · Futur I"
        case .imperativ: "Imperativ"
        }
    }
    var title: String {
        mood == .indicative || mood == .imperative ? shortTitle : "\(mood.title) · \(shortTitle)"
    }
    var english: String {
        switch self {
        case .praesens: "Present"
        case .praeteritum: "Simple past"
        case .perfekt: "Conversational past"
        case .plusquamperfekt: "Past perfect"
        case .futurI: "Future"
        case .futurII: "Future perfect"
        case .konjunktivIPraesens: "Reported speech · present"
        case .konjunktivIPerfekt: "Reported speech · past"
        case .konjunktivIFuturI: "Reported speech · future"
        case .konjunktivIFuturII: "Reported speech · future perfect"
        case .konjunktivIIPraeteritum: "Hypothetical present · wishes and polite requests"
        case .konjunktivIIPlusquamperfekt: "Hypothetical past · what would have happened"
        case .konjunktivIIWuerde: "Would + infinitive · common alternative to the simple form"
        case .konjunktivIIFuturII: "Would have + participle · less common alternative"
        case .imperativ: "Commands and requests · informal singular, plural, and formal"
        }
    }
}

enum VerbPerson: String, CaseIterable, Codable, Identifiable, Sendable {
    case ich, du, erSieEs, wir, ihr, sieSie, formalSie
    static let statementCases: [Self] = [.ich, .du, .erSieEs, .wir, .ihr, .sieSie]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .erSieEs: "er / sie / es"
        case .sieSie: "sie / Sie"
        case .formalSie: "Sie"
        default: rawValue
        }
    }
}

enum InflectionClass: String, Codable, CaseIterable, Sendable {
    case weak, strong, mixed, irregular
    var title: String {
        switch self {
        case .weak: "Regular · weak"
        case .strong: "Irregular · strong"
        case .mixed: "Irregular · mixed"
        case .irregular: "Irregular"
        }
    }
}

enum Reflexivity: String, Codable, CaseIterable, Sendable {
    case none, optional, required
    var title: String {
        switch self {
        case .none: "Not reflexive"
        case .optional: "Can be reflexive"
        case .required: "Reflexive"
        }
    }
}

enum ReflexiveCase: String, Codable, CaseIterable, Sendable { case accusative, dative }
enum PrefixBehavior: String, Codable, CaseIterable, Sendable {
    case none, separable, inseparable
    var title: String {
        switch self {
        case .none: "No prefix"
        case .separable: "Separable prefix"
        case .inseparable: "Inseparable prefix"
        }
    }
}
enum PerfectAuxiliary: String, Codable, CaseIterable, Sendable { case haben, sein }
enum SegmentRole: String, Codable, CaseIterable, Sendable {
    case verb, auxiliary, subjectPronoun, reflexivePronoun, separablePrefix, spacing
}

struct FormSegment: Codable, Equatable, Sendable {
    let text: String
    let role: SegmentRole
    let isIrregular: Bool
}

struct ConjugationRow: Codable, Equatable, Identifiable, Sendable {
    let person: VerbPerson
    let segments: [FormSegment]
    let irregularExplanation: String?
    var id: VerbPerson { person }
    var text: String { segments.map(\.text).joined() }
    var irregularText: String { segments.filter(\.isIrregular).map(\.text).joined() }
    var accessibilityDescription: String {
        let form = "\(person.title) \(text)"
        guard let irregularExplanation else { return form }
        return "\(form). Irregular: \(irregularExplanation)"
    }
}

struct TenseTable: Codable, Equatable, Identifiable, Sendable {
    let tense: VerbTense
    let rule: String
    let explanation: String
    let rows: [ConjugationRow]
    var id: VerbTense { tense }
    var orderedRows: [ConjugationRow] {
        tense.persons.compactMap { person in rows.first { $0.person == person } }
    }
}

struct PrincipalParts: Codable, Equatable, Sendable {
    let present: String
    let past: String
    let participle: String
    let auxiliary: PerfectAuxiliary
}

struct VerbProfile: Codable, Equatable, Identifiable, Sendable {
    let infinitive: String
    let meaning: String
    let inflection: InflectionClass
    let reflexivity: Reflexivity
    let reflexiveCase: ReflexiveCase?
    let usesReflexivePronoun: Bool
    let prefix: String?
    let prefixBehavior: PrefixBehavior
    let stem: String
    let infinitiveEnding: String
    let principalParts: PrincipalParts
    let usageNote: String?
    var tables: [TenseTable]
    var id: String { "\(infinitive)|\(meaning)" }
    var components: [String] {
        (usesReflexivePronoun ? ["sich"] : []) + [prefix, stem, infinitiveEnding].compactMap { $0 }.filter { !$0.isEmpty }
    }
    func table(for tense: VerbTense) -> TenseTable? { tables.first { $0.tense == tense } }
}

struct VerbLookupResult: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case found, notFound }
    let status: Status
    let message: String?
    let suggestions: [String]
    var variants: [VerbProfile]

    func validated(requiredForms: [VerbTense]? = nil) throws -> Self {
        let malformed = LookupError("The conjugation response was incomplete. Please try again.")
        guard suggestions.count <= 5, Set(suggestions).count == suggestions.count, suggestions.allSatisfy({ !$0.trimmed.isEmpty }) else { throw malformed }
        if status == .notFound {
            guard variants.isEmpty, let message, !message.trimmed.isEmpty else { throw malformed }
            return self
        }
        guard !variants.isEmpty, variants.count <= 3, Set(variants.map(\.id)).count == variants.count else { throw malformed }
        for verb in variants {
            guard [verb.infinitive, verb.meaning, verb.stem, verb.infinitiveEnding,
                   verb.principalParts.present, verb.principalParts.past, verb.principalParts.participle].allSatisfy({ !$0.trimmed.isEmpty }),
                  !verb.tables.isEmpty,
                  Set(verb.tables.map(\.tense)).count == verb.tables.count,
                  requiredForms.map({ Set(verb.tables.map(\.tense)) == Set($0) }) ?? true,
                  (verb.prefixBehavior == .none ? verb.prefix == nil : !(verb.prefix?.trimmed.isEmpty ?? true)),
                  (!verb.usesReflexivePronoun || (verb.reflexivity != .none && verb.reflexiveCase != nil)) else { throw malformed }
            if verb.prefixBehavior == .separable, let prefix = verb.prefix {
                guard verb.principalParts.present.hasSuffix(" " + prefix),
                      verb.principalParts.past.hasSuffix(" " + prefix) else { throw malformed }
            }
            for table in verb.tables {
                guard !table.rule.trimmed.isEmpty, !table.explanation.trimmed.isEmpty,
                      table.rows.count == table.tense.persons.count,
                      Set(table.rows.map(\.person)) == Set(table.tense.persons) else { throw malformed }
                for row in table.rows {
                    if verb.prefixBehavior == .separable, table.tense.hasDetachedPrefix,
                       let prefix = verb.prefix, row.text.trimmed != "—" {
                        guard row.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                            .hasSuffix(" " + prefix) else { throw malformed }
                    }
                    guard !row.text.trimmed.isEmpty, !row.segments.isEmpty,
                          row.segments.contains(where: { $0.role == .verb }),
                          row.segments.allSatisfy({ !$0.text.isEmpty && (!$0.isIrregular || ($0.role == .verb && !$0.text.trimmed.isEmpty)) }),
                          (row.irregularText.isEmpty || !(row.irregularExplanation?.trimmed.isEmpty ?? true)) else { throw malformed }
                }
            }
        }
        return self
    }
}

struct LookupError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var normalizedVerbQuery: String {
        precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "de_DE"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

@MainActor protocol VerbLookingUp {
    func lookup(_ query: String, apiKey: String, forms: [VerbTense]) async throws -> VerbLookupResult
    func loadTables(for verb: VerbProfile, forms: [VerbTense], apiKey: String) async throws -> [TenseTable]
}

extension VerbLookingUp {
    func lookup(_ query: String, apiKey: String) async throws -> VerbLookupResult {
        try await lookup(query, apiKey: apiKey, forms: VerbTense.allCases)
    }
}

extension VerbLookupResult {
    func restricted(to forms: [VerbTense]) -> Self {
        var copy = self
        for index in copy.variants.indices {
            copy.variants[index].tables = copy.variants[index].tables.filter { forms.contains($0.tense) }
        }
        return copy
    }

    func merging(_ tables: [TenseTable], into profileID: String) throws -> Self {
        var copy = self
        guard let index = copy.variants.firstIndex(where: { $0.id == profileID }) else {
            throw LookupError("This verb meaning is no longer selected. Please try again.")
        }
        let replacements = Set(tables.map(\.tense))
        copy.variants[index].tables.removeAll { replacements.contains($0.tense) }
        copy.variants[index].tables += tables
        return try copy.validated()
    }
}
@MainActor protocol VerbCaching {
    func read(_ query: String) -> VerbLookupResult?
    func write(_ result: VerbLookupResult, for query: String) throws
}
@MainActor protocol KonjuGoCredentials {
    func load() throws -> String
    func save(_ key: String) throws
}
