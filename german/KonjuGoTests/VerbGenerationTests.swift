import Foundation
import Testing
@testable import KonjuGo

@Suite @MainActor struct VerbGenerationTests {
    @Test func ausweichenSurvivesResponseDecodingAndCacheWithoutWordBreaks() throws {
        let fixture = VerbFixtures.result("ausweichen")
        let text = String(decoding: try JSONEncoder().encode(fixture), as: UTF8.self)
        let response = try JSONSerialization.data(withJSONObject: [
            "status": "completed",
            "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]
        ])
        let decoded = try OpenAIVerbService.decodeResponse(response)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = VerbCache(directory: directory)
        try cache.write(decoded, for: "ausweichen")
        let cached = try #require(cache.read("ausweichen"))
        for result in [decoded, cached] {
            let verb = try #require(result.variants.first)
            #expect(verb.principalParts.participle == "ausgewichen")
            #expect(verb.principalParts.auxiliary == .sein)
            let perfect = try #require(verb.table(for: .perfekt))
            #expect(perfect.orderedRows.map(\.text) == [
                "bin ausgewichen", "bist ausgewichen", "ist ausgewichen",
                "sind ausgewichen", "seid ausgewichen", "sind ausgewichen"
            ])
            for row in perfect.rows {
                #expect(row.irregularText == "ien")
                #expect(row.accessibilityDescription.contains("ausgewichen"))
            }
            #expect(verb.table(for: .praesens)?.orderedRows.first?.text == "weiche aus")
            #expect(verb.table(for: .plusquamperfekt)?.orderedRows.first?.text == "war ausgewichen")
            #expect(verb.table(for: .futurII)?.orderedRows.first?.text == "werde ausgewichen sein")
        }
    }
}

// Opt-in: real API calls using the app host's saved Keychain credential.
// Ordinary test runs never access Keychain or the network for this suite.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["KONJUGO_LIVE_TESTS"] == "1"))
@MainActor struct LiveVerbGenerationTests {
    @Test(arguments: ProcessInfo.processInfo.environment["KONJUGO_LIVE_VERBS"]?
        .split(separator: ",").map(String.init) ?? ["ausweichen", "aufstehen", "besuchen"])
    func modelGeneratesCorrectForms(_ infinitive: String) async throws {
        let key = try KonjuGoKeychain().load()
        try #require(!key.isEmpty, "Save an OpenAI key in KonjuGo Settings before running live tests.")
        let generated = try await OpenAIVerbService().lookup(infinitive, apiKey: key)
        let actual = try #require(generated.variants.first)
        let expected = VerbFixtures.result(infinitive).variants[0]
        #expect(actual.infinitive == expected.infinitive)
        #expect(actual.prefix == expected.prefix)
        #expect(actual.prefixBehavior == expected.prefixBehavior)
        #expect(actual.principalParts.participle == expected.principalParts.participle)
        #expect(actual.principalParts.auxiliary == expected.principalParts.auxiliary)
        #expect(actual.principalParts.present == expected.principalParts.present)
        #expect(actual.principalParts.past == expected.principalParts.past)
        for form in VerbTense.allCases where form.mood != .indicative && form != .imperativ {
            let row = try #require(actual.table(for: form)?.orderedRows[2])
            let reference = try #require(expected.table(for: form)?.orderedRows[2])
            let accepted = infinitive == "aufstehen" && form == .konjunktivIIPraeteritum
                ? [reference.text, "stände auf"] : [reference.text]
            #expect(accepted.contains(row.text), "\(infinitive), \(form.title): \(row.text)")
        }
        let commands = try #require(actual.table(for: .imperativ)?.orderedRows)
        let referenceCommands = try #require(expected.table(for: .imperativ)?.orderedRows)
        for (row, reference) in zip(commands, referenceCommands) {
            var accepted = [reference.text]
            if row.person == .du {
                switch infinitive {
                case "aufstehen": accepted.append("stehe auf")
                case "ausweichen": accepted.append("weiche aus")
                case "besuchen": accepted.append("besuche")
                default: break
                }
            }
            #expect(accepted.contains(row.text), "\(infinitive), Imperativ: \(row.text)")
            #expect(row.irregularText == reference.irregularText)
        }
        for tense in VerbMood.indicative.forms {
            let table = try #require(actual.table(for: tense))
            let reference = try #require(expected.table(for: tense))
            for (row, expectedRow) in zip(table.orderedRows, reference.orderedRows) {
                // Both standst and standest are standard: https://www.duden.de/konjugation/stehen
                let acceptedForms = infinitive == "aufstehen" && tense == .praeteritum && row.person == .du
                    ? [expectedRow.text, "standest auf"] : [expectedRow.text]
                #expect(acceptedForms.contains(row.text), "\(infinitive), \(tense.title), \(row.person.title): got \(row.text), expected \(acceptedForms)")
                #expect(row.irregularText == expectedRow.irregularText, "\(infinitive), \(tense.title), \(row.person.title): orange letters")
            }
        }
    }
}
