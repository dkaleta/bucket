#if DEBUG
import Foundation

// Explicit reference stems supplied by previews/tests, never used to generate live answers.
enum PreviewMoodTables {
    static func make(infinitive: String, subjunctiveI: [String], subjunctiveII: [String],
                     imperative: [String], participle: String, auxiliary: PerfectAuxiliary,
                     prefix: String? = nil, reflexive: Bool = false) -> [TenseTable] {
        let haveI = ["habe", "habest", "habe", "haben", "habet", "haben"]
        let beI = ["sei", "seiest", "sei", "seien", "seiet", "seien"]
        let haveII = ["hätte", "hättest", "hätte", "hätten", "hättet", "hätten"]
        let beII = ["wäre", "wärst", "wäre", "wären", "wärt", "wären"]
        let becomeI = ["werde", "werdest", "werde", "werden", "werdet", "werden"]
        let would = ["würde", "würdest", "würde", "würden", "würdet", "würden"]
        let reflexives = ["mich", "dich", "sich", "uns", "euch", "sich"]
        func plain(_ text: String, _ role: SegmentRole) -> [FormSegment] {
            [.init(text: text, role: role, isIrregular: false)]
        }
        return VerbTense.allCases.filter { $0.mood != .indicative }.map { form in
            let rows = form.persons.enumerated().map { index, person in
                var segments: [FormSegment]
                switch form {
                case .konjunktivIPraesens, .konjunktivIIPraeteritum:
                    segments = PreviewVerb.annotated((form == .konjunktivIPraesens ? subjunctiveI : subjunctiveII)[index])
                    if reflexive { segments += plain(" " + reflexives[index], .reflexivePronoun) }
                    if let prefix { segments += plain(" " + prefix, .separablePrefix) }
                case .imperativ:
                    segments = PreviewVerb.annotated(imperative[index])
                    if person == .formalSie && imperative[index] != "—" { segments += plain(" Sie", .subjectPronoun) }
                    if reflexive { segments += plain(" " + ["dich", "euch", "sich"][index], .reflexivePronoun) }
                    if let prefix { segments += plain(" " + prefix, .separablePrefix) }
                default:
                    let aux: [String]
                    switch form {
                    case .konjunktivIPerfekt: aux = auxiliary == .sein ? beI : haveI
                    case .konjunktivIIPlusquamperfekt: aux = auxiliary == .sein ? beII : haveII
                    case .konjunktivIFuturI, .konjunktivIFuturII: aux = becomeI
                    default: aux = would
                    }
                    segments = plain(aux[index] + " ", .auxiliary)
                    if reflexive { segments += plain(reflexives[index] + " ", .reflexivePronoun) }
                    let isInfinitive = form == .konjunktivIFuturI || form == .konjunktivIIWuerde
                    segments += PreviewVerb.annotated(isInfinitive ? infinitive : participle)
                    if form == .konjunktivIFuturII || form == .konjunktivIIFuturII {
                        segments += plain(" " + auxiliary.rawValue, .auxiliary)
                    }
                }
                return ConjugationRow(person: person, segments: segments,
                                      irregularExplanation: segments.contains(where: \.isIrregular)
                                      ? "The marked stem or ending differs from the regular pattern." : nil)
            }
            let rule: String
            switch form {
            case .konjunktivIPraesens: rule = "Present stem + -e, -est, -e, -en, -et, -en."
            case .konjunktivIPerfekt: rule = "Konjunktiv I of haben/sein + participle."
            case .konjunktivIFuturI: rule = "Konjunktiv I of werden + infinitive."
            case .konjunktivIFuturII: rule = "Konjunktiv I of werden + participle + haben/sein."
            case .konjunktivIIPraeteritum: rule = "Konjunktiv II stem + personal endings."
            case .konjunktivIIPlusquamperfekt: rule = "hätte/wäre + participle."
            case .konjunktivIIWuerde: rule = "würde + infinitive."
            case .konjunktivIIFuturII: rule = "würde + participle + haben/sein."
            default: rule = "du: singular command; ihr: plural command; Sie: formal request."
            }
            return TenseTable(tense: form, rule: rule,
                              explanation: form == .imperativ
                              ? "Omit du and ihr; retain Sie after the verb in a formal request. A separable prefix stays at the end."
                              : "\(form.english). Separable prefixes remain at the end of simple main-clause forms; compound forms use the joined infinitive or participle.", rows: rows)
        }
    }
}
#endif
