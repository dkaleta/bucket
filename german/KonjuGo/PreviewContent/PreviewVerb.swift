#if DEBUG
import Foundation
import SwiftUI

// Deterministic preview data also used by the UI-test launch path; never used for live lookups.
enum PreviewVerb {
    static let fahren: VerbLookupResult = {
        let present = ["fahre", "f{ä}hrst", "f{ä}hrt", "fahren", "fahrt", "fahren"]
        let past = ["f{u}hr", "f{u}hrst", "f{u}hr", "f{u}hren", "f{u}hrt", "f{u}hren"]
        let sein = ["bin", "bist", "ist", "sind", "seid", "sind"]
        let war = ["war", "warst", "war", "waren", "wart", "waren"]
        let werden = ["werde", "wirst", "wird", "werden", "werdet", "werden"]
        let rules: [(String, String)] = [
            ("Stem + present endings; a → ä for du and er/sie/es.", "Use -e, -st, -t, -en, -t, -en. The stem vowel changes from a to ä only for du and er/sie/es: du fährst, er fährt. The other present forms keep fahr-."),
            ("Strong past stem fuhr- + personal endings.", "The stem vowel changes from a to u. Strong past forms omit the weak -te suffix; ich and er/sie/es have no personal ending. The other endings are -st, -en, -t, -en."),
            ("Present of sein + gefahren.", "For travel from one place to another, use sein. The participle is ge- + fahr- + -en; the strong ending -en is highlighted. The auxiliary remains neutral."),
            ("Simple past of sein + gefahren.", "Use war, warst, war, waren, wart, waren followed by gefahren. This describes travel completed before another past event. The participle's strong -en ending is highlighted."),
            ("Present of werden + fahren.", "Use werde, wirst, wird, werden, werdet, werden followed by the unchanged infinitive fahren. The studied verb has no irregular change here; auxiliaries remain neutral."),
            ("Present of werden + gefahren + sein.", "Use the present of werden, followed by the participle gefahren and infinitive sein. This describes travel completed by a future point. Only the participle's strong ending is highlighted.")
        ]
        var tables = VerbMood.indicative.forms.enumerated().map { offset, tense in
            let rows = VerbPerson.statementCases.enumerated().map { index, person in
                let segments: [FormSegment]
                switch tense {
                case .praesens: segments = annotated(present[index])
                case .praeteritum: segments = annotated(past[index])
                case .perfekt: segments = [.init(text: sein[index] + " ", role: .auxiliary, isIrregular: false)] + annotated("gefahr{en}")
                case .plusquamperfekt: segments = [.init(text: war[index] + " ", role: .auxiliary, isIrregular: false)] + annotated("gefahr{en}")
                case .futurI: segments = [.init(text: werden[index] + " ", role: .auxiliary, isIrregular: false)] + annotated("fahren")
                case .futurII: segments = [.init(text: werden[index] + " ", role: .auxiliary, isIrregular: false)] + annotated("gefahr{en}") + [.init(text: " sein", role: .auxiliary, isIrregular: false)]
                default: preconditionFailure("Indicative fixture only")
                }
                let note: String?
                if !segments.contains(where: \.isIrregular) { note = nil }
                else if tense == .praesens { note = "The stem vowel a changes to ä." }
                else if tense == .praeteritum { note = "The stem vowel a changes to u; the weak -te suffix is omitted." }
                else { note = "The strong participle ends in -en rather than the regular -t." }
                return ConjugationRow(person: person, segments: segments, irregularExplanation: note)
            }
            return TenseTable(tense: tense, rule: rules[offset].0, explanation: rules[offset].1, rows: rows)
        }
        tables += PreviewMoodTables.make(infinitive: "fahren",
            subjunctiveI: ["fahre", "fahrest", "fahre", "fahren", "fahret", "fahren"],
            subjunctiveII: ["f{ü}hre", "f{ü}hrest", "f{ü}hre", "f{ü}hren", "f{ü}hret", "f{ü}hren"],
            imperative: ["fahr", "fahrt", "fahren"], participle: "gefahr{en}", auxiliary: .sein)
        return VerbLookupResult(status: .found, message: nil, suggestions: [], variants: [VerbProfile(
            infinitive: "fahren", meaning: "to travel / go by vehicle", inflection: .strong,
            reflexivity: .none, reflexiveCase: nil, usesReflexivePronoun: false,
            prefix: nil, prefixBehavior: .none, stem: "fahr", infinitiveEnding: "en",
            principalParts: .init(present: "fährt", past: "fuhr", participle: "gefahren", auxiliary: .sein),
            usageNote: "This use describes travelling. Driving a particular vehicle can take haben instead.", tables: tables
        )])
    }()

    static func annotated(_ marked: String) -> [FormSegment] {
        var segments: [FormSegment] = []
        var buffer = ""
        var irregular = false
        for character in marked {
            if character == "{" || character == "}" {
                if !buffer.isEmpty { segments.append(.init(text: buffer, role: .verb, isIrregular: irregular)); buffer = "" }
                irregular = character == "{"
            } else { buffer.append(character) }
        }
        if !buffer.isEmpty { segments.append(.init(text: buffer, role: .verb, isIrregular: irregular)) }
        return segments
    }
}

@MainActor final class PreviewCredentials: KonjuGoCredentials {
    var key = "preview-only"
    func load() throws -> String { key }
    func save(_ key: String) throws { self.key = key }
}
@MainActor final class PreviewCache: VerbCaching {
    var entries: [String: VerbLookupResult] = [:]
    func read(_ query: String) -> VerbLookupResult? { entries[query] }
    func write(_ result: VerbLookupResult, for query: String) throws {
        if result.status == .found { entries[query] = result }
    }
}
@MainActor final class PreviewLookupService: VerbLookingUp {
    func loadTables(for verb: VerbProfile, forms: [VerbTense], apiKey: String) async throws -> [TenseTable] {
        PreviewVerb.fahren.variants[0].tables.filter { forms.contains($0.tense) }
    }
    func lookup(_ query: String, apiKey: String, forms: [VerbTense]) async throws -> VerbLookupResult {
        if query == "fahren" { return PreviewVerb.fahren.restricted(to: forms) }
        return .init(status: .notFound, message: "Try a German infinitive.", suggestions: ["fahren"], variants: [])
    }
}

#Preview("Conjugation") {
    let keys = PreviewCredentials()
    let cache = PreviewCache()
    let _ = try? cache.write(PreviewVerb.fahren, for: "fahren")
    let model = ConjugationViewModel(service: PreviewLookupService(), cache: cache, credentials: keys)
    let _ = { model.query = "fahren"; model.submit() }()
    ContentView(model: model, credentials: keys)
}
#endif
