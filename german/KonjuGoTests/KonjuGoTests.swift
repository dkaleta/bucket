import Foundation
import Testing
@testable import KonjuGo

@Suite @MainActor struct KonjuGoTests {
    private func row(_ verb: String, _ tense: VerbTense, _ person: VerbPerson) throws -> ConjugationRow {
        let data = try JSONEncoder().encode(VerbFixtures.result(verb))
        let parsed = try JSONDecoder().decode(VerbLookupResult.self, from: data).validated()
        return try #require(parsed.variants[0].table(for: tense)?.rows.first { $0.person == person })
    }

    @Test func allFixturesHaveCompleteMoodTables() throws {
        for verb in ["fahren"] + VerbFixtures.specs.map(\.infinitive) {
            let result = try VerbFixtures.result(verb).validated()
            #expect(result.variants[0].tables.count == VerbTense.allCases.count)
            #expect(result.variants[0].tables.allSatisfy { $0.orderedRows.map(\.person) == $0.tense.persons })
        }
    }

    @Test func exactLetterHighlightsAndNeutralRows() throws {
        #expect(try row("fahren", .praesens, .du).text == "fährst")
        #expect(try row("fahren", .praesens, .du).irregularText == "ä")
        #expect(try row("fahren", .praesens, .erSieEs).irregularText == "ä")
        #expect(try row("fahren", .praesens, .wir).irregularText.isEmpty)
        #expect(try row("fahren", .praesens, .ihr).irregularText.isEmpty)
        #expect(try row("sprechen", .praesens, .du).irregularText == "i")
        #expect(try row("bringen", .praeteritum, .ich).irregularText == "ach")
        #expect(try row("sein", .praesens, .ich).irregularText == "bin")
        #expect(try row("können", .praesens, .du).irregularText == "a")
    }

    @Test func regularRulesDoNotGetOrange() throws {
        for verb in ["machen", "besuchen", "sich freuen", "arbeiten", "sammeln"] {
            for table in VerbFixtures.result(verb).variants[0].tables {
                #expect(table.rows.allSatisfy { $0.irregularText.isEmpty })
            }
        }
        #expect(try row("heißen", .praesens, .du).irregularText.isEmpty)
        #expect(try row("arbeiten", .praesens, .du).text == "arbeitest")
        #expect(try row("sammeln", .praesens, .ich).text == "sammle")
    }

    @Test func compoundTensesHighlightOnlyStudiedVerb() throws {
        let perfect = try row("fahren", .perfekt, .ich)
        #expect(perfect.text == "bin gefahren")
        #expect(perfect.irregularText == "en")
        #expect(perfect.segments.filter { $0.role == .auxiliary }.allSatisfy { !$0.isIrregular })
        #expect(try row("fahren", .futurI, .du).text == "wirst fahren")
        #expect(try row("fahren", .futurI, .du).irregularText.isEmpty)
        #expect(try row("fahren", .futurII, .ich).text == "werde gefahren sein")
        #expect(try row("machen", .plusquamperfekt, .ich).text == "hatte gemacht")
        #expect(try row("machen", .futurII, .ich).text == "werde gemacht haben")
    }

    @Test func reflexivePronounsAndSeparatedPrefixes() throws {
        #expect(try row("sich freuen", .praesens, .du).text == "freust dich")
        #expect(try row("sich freuen", .perfekt, .wir).text == "haben uns gefreut")
        #expect(try row("sich freuen", .futurII, .ihr).text == "werdet euch gefreut haben")
        #expect(try row("aufstehen", .praesens, .ich).text == "stehe auf")
        #expect(try row("aufstehen", .perfekt, .ich).text == "bin aufgestanden")
        #expect(try row("besuchen", .perfekt, .ich).text == "habe besucht")
    }

    @Test func accessibilityExplainsHighlight() throws {
        let form = try row("fahren", .praesens, .du)
        #expect(form.accessibilityDescription.contains("du fährst"))
        #expect(form.accessibilityDescription.contains("a changes to ä"))
        #expect(try row("machen", .praesens, .ich).accessibilityDescription == "ich mache")
    }

    @Test func normalizationPreservesGermanLettersAndReflexivity() {
        #expect("  SICH \n FREUEN  ".normalizedVerbQuery == "sich freuen")
        #expect(" HEIẞEN ".normalizedVerbQuery == "heißen")
        #expect(" KO\u{308}NNEN ".normalizedVerbQuery == "können")
        #expect("können".normalizedVerbQuery != "konnen".normalizedVerbQuery)
    }

    private func altered(_ mutate: (inout [String: Any]) -> Void) throws -> VerbLookupResult {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(PreviewVerb.fahren)) as? [String: Any])
        mutate(&json)
        return try JSONDecoder().decode(VerbLookupResult.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func malformedAndIncompleteParadigmsAreRejected() throws {
        let noTables = try altered { json in
            var variants = json["variants"] as! [[String: Any]]
            variants[0]["tables"] = []
            json["variants"] = variants
        }
        #expect(throws: LookupError.self) { try noTables.validated() }
        let duplicatePerson = try altered { json in
            var variants = json["variants"] as! [[String: Any]]
            var tables = variants[0]["tables"] as! [[String: Any]]
            var rows = tables[0]["rows"] as! [[String: Any]]
            rows[1]["person"] = "ich"
            tables[0]["rows"] = rows; variants[0]["tables"] = tables; json["variants"] = variants
        }
        #expect(throws: LookupError.self) { try duplicatePerson.validated() }
        let coloredAuxiliary = try altered { json in
            var variants = json["variants"] as! [[String: Any]]
            var tables = variants[0]["tables"] as! [[String: Any]]
            var rows = tables[2]["rows"] as! [[String: Any]]
            var segments = rows[0]["segments"] as! [[String: Any]]
            segments[0]["isIrregular"] = true
            rows[0]["segments"] = segments; tables[2]["rows"] = rows; variants[0]["tables"] = tables; json["variants"] = variants
        }
        #expect(throws: LookupError.self) { try coloredAuxiliary.validated() }
    }

    @Test func structuredResponseAndFailures() throws {
        func envelope(_ result: VerbLookupResult, status: String = "completed") throws -> Data {
            let text = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
            return try JSONSerialization.data(withJSONObject: ["status": status, "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]])
        }
        #expect(try OpenAIVerbService.decodeResponse(envelope(PreviewVerb.fahren)) == PreviewVerb.fahren)
        let unknown = VerbLookupResult(status: .notFound, message: "Try a German infinitive.", suggestions: ["fahren"], variants: [])
        #expect(try OpenAIVerbService.decodeResponse(envelope(unknown)).status == .notFound)
        #expect(throws: LookupError.self) { try OpenAIVerbService.decodeResponse(envelope(PreviewVerb.fahren, status: "incomplete")) }
        #expect(throws: LookupError.self) { try OpenAIVerbService.decodeResponse(Data("bad".utf8)) }
        let refusal = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal"}]}]}"#.utf8)
        #expect(throws: LookupError.self) { try OpenAIVerbService.decodeResponse(refusal) }
        let body = try #require(JSONSerialization.jsonObject(with: OpenAIVerbService.requestBody(query: "fahren")) as? [String: Any])
        #expect(body["store"] as? Bool == false)
        #expect(body["model"] as? String == "gpt-5.6-terra")
        let reasoning = try #require(body["reasoning"] as? [String: Any])
        #expect(reasoning["effort"] as? String == "low")
        let text = try #require(body["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["strict"] as? Bool == true)
    }

    @Test func diskCacheNormalizesAndRejectsCorruptionAndVersionMismatch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = VerbCache(directory: directory)
        try cache.write(PreviewVerb.fahren, for: " FAHREN ")
        #expect(cache.read("fahren") == PreviewVerb.fahren)
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var entry = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        entry["version"] = 6
        try JSONSerialization.data(withJSONObject: entry).write(to: file)
        #expect(cache.read("fahren") == nil)
        try Data("corrupt".utf8).write(to: file)
        #expect(cache.read("fahren") == nil)
        #expect(cache.read("machen") == nil)
    }
}
