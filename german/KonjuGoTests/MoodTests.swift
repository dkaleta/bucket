import Foundation
import Testing
@testable import KonjuGo

@Suite @MainActor struct MoodTests {
    @Test func menuGroupsCoverEveryFormOnce() {
        #expect(VerbMood.allCases.map { $0.forms.count } == [6, 4, 4, 1])
        #expect(VerbMood.allCases.flatMap(\.forms) == VerbTense.allCases)
        #expect(Set(VerbTense.allCases.map(\.title)).count == VerbTense.allCases.count)
        #expect(VerbTense.imperativ.persons == [.du, .ihr, .formalSie])
    }

    @Test func subjunctiveAndImperativeFormsKeepTheirOwnGrammar() throws {
        let stand = try VerbFixtures.result("aufstehen").validated().variants[0]
        #expect(stand.table(for: .konjunktivIPraesens)?.orderedRows[2].text == "stehe auf")
        #expect(stand.table(for: .konjunktivIIPraeteritum)?.orderedRows[2].text == "stünde auf")
        #expect(stand.table(for: .konjunktivIIPlusquamperfekt)?.orderedRows[2].text == "wäre aufgestanden")
        #expect(stand.table(for: .konjunktivIIWuerde)?.orderedRows[2].text == "würde aufstehen")
        #expect(stand.table(for: .konjunktivIFuturII)?.orderedRows[2].text == "werde aufgestanden sein")
        #expect(stand.table(for: .konjunktivIIFuturII)?.orderedRows[2].text == "würde aufgestanden sein")
        #expect(stand.table(for: .imperativ)?.orderedRows.map(\.text) == ["steh auf", "steht auf", "stehen Sie auf"])
        let speak = VerbFixtures.result("sprechen").variants[0]
        #expect(speak.table(for: .imperativ)?.orderedRows.first?.text == "sprich")
        #expect(speak.table(for: .imperativ)?.orderedRows.first?.irregularText == "i")
        #expect(PreviewVerb.fahren.variants[0].table(for: .imperativ)?.orderedRows.first?.text == "fahr")
        let happy = VerbFixtures.result("sich freuen").variants[0]
        #expect(happy.table(for: .imperativ)?.orderedRows.map(\.text) == ["freue dich", "freut euch", "freuen Sie sich"])
        #expect(VerbFixtures.result("sein").variants[0].table(for: .imperativ)?.orderedRows.map(\.text) == ["sei", "seid", "seien Sie"])
    }

    private func changed(_ mutation: (inout [String: Any]) -> Void) throws -> VerbLookupResult {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(VerbFixtures.result("aufstehen"))) as? [String: Any])
        var variants = object["variants"] as! [[String: Any]]
        mutation(&variants[0])
        object["variants"] = variants
        return try JSONDecoder().decode(VerbLookupResult.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func missingMoodAndInventedImperativePersonsAreRejected() throws {
        let missing = try changed { profile in
            var tables = profile["tables"] as! [[String: Any]]
            tables.removeLast()
            profile["tables"] = tables
        }
        #expect(throws: LookupError.self) { try missing.validated(requiredForms: VerbTense.allCases) }
        let invented = try changed { profile in
            var tables = profile["tables"] as! [[String: Any]]
            let index = tables.firstIndex { $0["tense"] as? String == "imperativ" }!
            var rows = tables[index]["rows"] as! [[String: Any]]
            rows[0]["person"] = "ich"
            tables[index]["rows"] = rows
            profile["tables"] = tables
        }
        #expect(throws: LookupError.self) { try invented.validated() }
    }

    @Test func missingSeparatedPrefixIsRejectedInEverySimpleMoodAndSummary() throws {
        for form in VerbTense.allCases.filter(\.hasDetachedPrefix) {
            let missing = try changed { profile in
                var tables = profile["tables"] as! [[String: Any]]
                let index = tables.firstIndex { $0["tense"] as? String == form.rawValue }!
                var rows = tables[index]["rows"] as! [[String: Any]]
                var segments = rows[0]["segments"] as! [[String: Any]]
                segments.removeLast()
                rows[0]["segments"] = segments
                tables[index]["rows"] = rows
                profile["tables"] = tables
            }
            #expect(throws: LookupError.self) { try missing.validated() }
        }
        let missingSummary = try changed { profile in
            var parts = profile["principalParts"] as! [String: Any]
            parts["past"] = "stand"
            profile["principalParts"] = parts
        }
        #expect(throws: LookupError.self) { try missingSummary.validated() }
    }
}
