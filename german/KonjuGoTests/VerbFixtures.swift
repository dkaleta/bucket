import Foundation
@testable import KonjuGo

// Explicit linguistic fixtures, independent of the lookup implementation.
@MainActor enum VerbFixtures {
    struct Spec {
        let infinitive: String
        let meaning: String
        let inflection: InflectionClass
        let stem: String
        let present: [String]
        let past: [String]
        let participle: String
        var auxiliary: PerfectAuxiliary = .haben
        var prefix: String? = nil
        var prefixBehavior: PrefixBehavior = .none
        var reflexive = false
        var ending = "en"
    }
    static let specs: [Spec] = [
        .init(infinitive: "ausweichen", meaning: "to avoid; to evade", inflection: .strong, stem: "weich",
              present: ["weiche", "weichst", "weicht", "weichen", "weicht", "weichen"],
              past: ["w{i}ch", "w{i}chst", "w{i}ch", "w{i}chen", "w{i}cht", "w{i}chen"], participle: "ausgew{i}ch{en}",
              auxiliary: .sein, prefix: "aus", prefixBehavior: .separable),
        .init(infinitive: "machen", meaning: "to do", inflection: .weak, stem: "mach",
              present: ["mache", "machst", "macht", "machen", "macht", "machen"],
              past: ["machte", "machtest", "machte", "machten", "machtet", "machten"], participle: "gemacht"),
        .init(infinitive: "sprechen", meaning: "to speak", inflection: .strong, stem: "sprech",
              present: ["spreche", "spr{i}chst", "spr{i}cht", "sprechen", "sprecht", "sprechen"],
              past: ["spr{a}ch", "spr{a}chst", "spr{a}ch", "spr{a}chen", "spr{a}cht", "spr{a}chen"], participle: "gespr{o}ch{en}"),
        .init(infinitive: "bringen", meaning: "to bring", inflection: .mixed, stem: "bring",
              present: ["bringe", "bringst", "bringt", "bringen", "bringt", "bringen"],
              past: ["br{ach}te", "br{ach}test", "br{ach}te", "br{ach}ten", "br{ach}tet", "br{ach}ten"], participle: "gebr{ach}t"),
        .init(infinitive: "aufstehen", meaning: "to get up", inflection: .strong, stem: "steh",
              present: ["stehe", "stehst", "steht", "stehen", "steht", "stehen"],
              past: ["st{and}", "st{and}st", "st{and}", "st{and}en", "st{and}et", "st{and}en"], participle: "aufgest{and}{en}",
              auxiliary: .sein, prefix: "auf", prefixBehavior: .separable),
        .init(infinitive: "besuchen", meaning: "to visit", inflection: .weak, stem: "such",
              present: ["besuche", "besuchst", "besucht", "besuchen", "besucht", "besuchen"],
              past: ["besuchte", "besuchtest", "besuchte", "besuchten", "besuchtet", "besuchten"], participle: "besucht",
              prefix: "be", prefixBehavior: .inseparable),
        .init(infinitive: "sich freuen", meaning: "to be happy", inflection: .weak, stem: "freu",
              present: ["freue", "freust", "freut", "freuen", "freut", "freuen"],
              past: ["freute", "freutest", "freute", "freuten", "freutet", "freuten"], participle: "gefreut", reflexive: true),
        .init(infinitive: "können", meaning: "to be able to", inflection: .irregular, stem: "könn",
              present: ["k{a}nn", "k{a}nnst", "k{a}nn", "können", "könnt", "können"],
              past: ["k{o}nnte", "k{o}nntest", "k{o}nnte", "k{o}nnten", "k{o}nntet", "k{o}nnten"], participle: "gek{o}nnt"),
        .init(infinitive: "sein", meaning: "to be", inflection: .irregular, stem: "sei",
              present: ["{bin}", "{bist}", "{ist}", "{sind}", "sei{d}", "{sind}"],
              past: ["{war}", "{war}st", "{war}", "{war}en", "{war}t", "{war}en"], participle: "ge{wes}{en}", auxiliary: .sein, ending: "n"),
        .init(infinitive: "arbeiten", meaning: "to work", inflection: .weak, stem: "arbeit",
              present: ["arbeite", "arbeitest", "arbeitet", "arbeiten", "arbeitet", "arbeiten"],
              past: ["arbeitete", "arbeitetest", "arbeitete", "arbeiteten", "arbeitetet", "arbeiteten"], participle: "gearbeitet"),
        .init(infinitive: "heißen", meaning: "to be called", inflection: .strong, stem: "heiß",
              present: ["heiße", "heißt", "heißt", "heißen", "heißt", "heißen"],
              past: ["h{ie}ß", "h{ie}ßt", "h{ie}ß", "h{ie}ßen", "h{ie}ßt", "h{ie}ßen"], participle: "geheiß{en}"),
        .init(infinitive: "sammeln", meaning: "to collect", inflection: .weak, stem: "sammel",
              present: ["sammle", "sammelst", "sammelt", "sammeln", "sammelt", "sammeln"],
              past: ["sammelte", "sammeltest", "sammelte", "sammelten", "sammeltet", "sammelten"], participle: "gesammelt", ending: "n")
    ]

    private static func moodForms(_ verb: String) -> ([String], [String], [String]) {
        func eForms(_ base: String) -> [String] { [base + "e", base + "est", base + "e", base + "en", base + "et", base + "en"] }
        func weakPast(_ base: String) -> [String] { [base, base + "st", base, base + "n", base + "t", base + "n"] }
        switch verb {
        case "ausweichen": return (eForms("weich"), eForms("w{i}ch"), ["weich", "weicht", "weichen"])
        case "machen": return (eForms("mach"), weakPast("machte"), ["mach", "macht", "machen"])
        case "sprechen": return (eForms("sprech"), eForms("spr{ä}ch"), ["spr{i}ch", "sprecht", "sprechen"])
        case "bringen": return (eForms("bring"), weakPast("br{äch}te"), ["bring", "bringt", "bringen"])
        case "aufstehen": return (eForms("steh"), eForms("st{ünd}"), ["steh", "steht", "stehen"])
        case "besuchen": return (eForms("besuch"), weakPast("besuchte"), ["besuch", "besucht", "besuchen"])
        case "sich freuen": return (eForms("freu"), weakPast("freute"), ["freue", "freut", "freuen"])
        case "können": return (eForms("könn"), weakPast("könnte"), ["—", "—", "—"])
        case "sein": return (["sei", "seiest", "sei", "seien", "seiet", "seien"],
                             ["{wär}e", "{wär}st", "{wär}e", "{wär}en", "{wär}t", "{wär}en"], ["sei", "sei{d}", "sei{e}n"])
        case "arbeiten": return (eForms("arbeit"), weakPast("arbeitete"), ["arbeite", "arbeitet", "arbeiten"])
        case "heißen": return (eForms("heiß"), eForms("h{ie}ß"), ["heiß", "heißt", "heißen"])
        case "sammeln": return (["sammle", "sammlest", "sammle", "sammeln", "sammlet", "sammeln"],
                                weakPast("sammelte"), ["sammle", "sammelt", "sammeln"])
        default: preconditionFailure("Missing mood fixture: \(verb)")
        }
    }

    static func result(_ infinitive: String) -> VerbLookupResult {
        if infinitive == "fahren" { return PreviewVerb.fahren }
        let spec = specs.first { $0.infinitive == infinitive }!
        let presentAux = spec.auxiliary == .sein ? ["bin", "bist", "ist", "sind", "seid", "sind"] : ["habe", "hast", "hat", "haben", "habt", "haben"]
        let pastAux = spec.auxiliary == .sein ? ["war", "warst", "war", "waren", "wart", "waren"] : ["hatte", "hattest", "hatte", "hatten", "hattet", "hatten"]
        let futureAux = ["werde", "wirst", "wird", "werden", "werdet", "werden"]
        let pronouns = ["mich", "dich", "sich", "uns", "euch", "sich"]
        let infinitive = spec.infinitive.replacingOccurrences(of: "sich ", with: "")
        func plain(_ value: String, role: SegmentRole) -> FormSegment { .init(text: value, role: role, isIrregular: false) }
        var tables = VerbMood.indicative.forms.map { tense in
            let rows = VerbPerson.statementCases.enumerated().map { index, person in
                var segments: [FormSegment] = []
                let reflexive = spec.reflexive ? [plain(pronouns[index] + " ", role: .reflexivePronoun)] : []
                switch tense {
                case .praesens, .praeteritum:
                    segments = PreviewVerb.annotated(tense == .praesens ? spec.present[index] : spec.past[index])
                    if spec.reflexive { segments += [plain(" ", role: .spacing), plain(pronouns[index], role: .reflexivePronoun)] }
                    if spec.prefixBehavior == .separable { segments += [plain(" " + spec.prefix!, role: .separablePrefix)] }
                case .perfekt, .plusquamperfekt:
                    segments = [plain((tense == .perfekt ? presentAux[index] : pastAux[index]) + " ", role: .auxiliary)]
                        + reflexive + PreviewVerb.annotated(spec.participle)
                case .futurI:
                    segments = [plain(futureAux[index] + " ", role: .auxiliary)] + reflexive + PreviewVerb.annotated(infinitive)
                case .futurII:
                    segments = [plain(futureAux[index] + " ", role: .auxiliary)] + reflexive
                        + PreviewVerb.annotated(spec.participle) + [plain(" " + spec.auxiliary.rawValue, role: .auxiliary)]
                default: preconditionFailure("Indicative fixture only")
                }
                return ConjugationRow(person: person, segments: segments,
                                      irregularExplanation: segments.contains(where: \.isIrregular) ? "The marked stem or ending differs from the weak pattern." : nil)
            }
            return TenseTable(tense: tense, rule: "Formation of \(tense.title)", explanation: "Use the appropriate stem and personal endings for this tense.", rows: rows)
        }
        let moods = moodForms(spec.infinitive)
        tables += PreviewMoodTables.make(infinitive: infinitive, subjunctiveI: moods.0,
            subjunctiveII: moods.1, imperative: moods.2, participle: spec.participle,
            auxiliary: spec.auxiliary, prefix: spec.prefixBehavior == .separable ? spec.prefix : nil,
            reflexive: spec.reflexive)
        let parts = PrincipalParts(present: tables[0].rows[2].text, past: tables[1].rows[2].text,
                                   participle: PreviewVerb.annotated(spec.participle).map(\.text).joined(), auxiliary: spec.auxiliary)
        return .init(status: .found, message: nil, suggestions: [], variants: [.init(
            infinitive: spec.infinitive, meaning: spec.meaning, inflection: spec.inflection,
            reflexivity: spec.reflexive ? .required : .none, reflexiveCase: spec.reflexive ? .accusative : nil,
            usesReflexivePronoun: spec.reflexive, prefix: spec.prefix, prefixBehavior: spec.prefixBehavior,
            stem: spec.stem, infinitiveEnding: spec.ending, principalParts: parts, usageNote: nil, tables: tables
        )])
    }
}
