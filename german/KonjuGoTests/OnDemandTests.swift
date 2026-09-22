import Foundation
import Testing
@testable import KonjuGo

@MainActor private final class DemandService: VerbLookingUp {
    var initialRequests: [[VerbTense]] = []
    var formRequests: [(String, [VerbTense])] = []
    var suspendForms = false
    var suspendLookup = false
    var pendingLookup: CheckedContinuation<VerbLookupResult, Error>?
    var failure: Error?
    var pending: [VerbTense: CheckedContinuation<[TenseTable], Error>] = [:]
    func lookup(_ query: String, apiKey: String, forms: [VerbTense]) async throws -> VerbLookupResult {
        initialRequests.append(forms)
        if let failure { throw failure }
        if suspendLookup { return try await withCheckedThrowingContinuation { pendingLookup = $0 } }
        return VerbFixtures.result(query).restricted(to: forms)
    }
    func loadTables(for verb: VerbProfile, forms: [VerbTense], apiKey: String) async throws -> [TenseTable] {
        formRequests.append((verb.id, forms))
        if let failure { throw failure }
        if suspendForms { return try await withCheckedThrowingContinuation { pending[forms[0]] = $0 } }
        return VerbFixtures.result(verb.infinitive).variants[0].tables.filter { forms.contains($0.tense) }
    }
    func finish(_ form: VerbTense, verb: String = "aufstehen") {
        pending.removeValue(forKey: form)?.resume(returning: VerbFixtures.result(verb).variants[0].tables.filter { $0.tense == form })
    }
}

@Suite @MainActor struct OnDemandTests {
    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Expected loading state was not reached")
    }

    @Test func presentFirstThenSelectedFormAndOfflineReuse() async throws {
        let service = DemandService(), cache = PreviewCache(), keys = PreviewCredentials()
        let model = ConjugationViewModel(service: service, cache: cache, credentials: keys, loadingMode: { .onDemand })
        model.query = "aufstehen"; model.submit()
        await eventually { !model.isLoading }
        #expect(service.initialRequests == [[.praesens]])
        #expect(model.selectedVerb?.tables.map(\.tense) == [.praesens])
        model.selectedTense = .perfekt
        await eventually { !model.isLoading }
        #expect(service.formRequests.map { $0.1 } == [[.perfekt]])
        #expect(model.table?.orderedRows.first?.text == "bin aufgestanden")
        #expect(model.selectedVerb?.tables.count == 2)
        keys.key = ""
        model.selectedTense = .praesens
        model.selectedTense = .perfekt
        #expect(service.formRequests.count == 1)
        #expect(model.errorMessage == nil)
        let restored = ConjugationViewModel(service: service, cache: cache, credentials: keys, loadingMode: { .onDemand })
        restored.query = "aufstehen"; restored.submit(); restored.selectedTense = .perfekt
        #expect(restored.table?.orderedRows.first?.text == "bin aufgestanden")
        #expect(service.initialRequests.count == 1)
    }

    @Test func failedLoadRetryAndRefreshPreserveOtherForms() async {
        let service = DemandService(), cache = PreviewCache()
        let model = ConjugationViewModel(service: service, cache: cache, credentials: PreviewCredentials(), loadingMode: { .onDemand })
        model.query = "aufstehen"; model.submit()
        await eventually { !model.isLoading }
        service.failure = URLError(.timedOut)
        model.selectedTense = .imperativ
        await eventually { !model.isLoading }
        #expect(model.errorMessage != nil)
        #expect(model.selectedVerb?.table(for: .praesens) != nil)
        #expect(model.table == nil)
        service.failure = nil
        model.retry()
        await eventually { !model.isLoading }
        #expect(model.table?.rows.count == 3)
        model.refresh()
        await eventually { !model.isLoading }
        #expect(service.initialRequests.count == 1)
        #expect(service.formRequests.map { $0.1 } == [[.imperativ], [.imperativ], [.imperativ]])
        #expect(model.selectedVerb?.tables.count == 2)
    }

    @Test func lateFormResponseCannotOverwriteSelectionOrAnotherVerb() async {
        let service = DemandService(), cache = PreviewCache()
        let model = ConjugationViewModel(service: service, cache: cache, credentials: PreviewCredentials(), loadingMode: { .onDemand })
        model.query = "aufstehen"; model.submit()
        await eventually { !model.isLoading }
        service.suspendForms = true
        model.selectedTense = .perfekt
        await eventually { service.pending[.perfekt] != nil }
        model.selectedTense = .imperativ
        await eventually { service.pending[.imperativ] != nil }
        service.finish(.perfekt)
        service.finish(.imperativ)
        await eventually { !model.isLoading }
        #expect(model.selectedTense == .imperativ)
        #expect(model.table?.rows.count == 3)
        #expect(model.selectedVerb?.table(for: .perfekt) == nil)
        model.selectedTense = .perfekt
        await eventually { service.pending[.perfekt] != nil }
        model.query = "machen"; model.submit()
        await eventually { !model.isLoading }
        service.finish(.perfekt)
        for _ in 0..<20 { await Task.yield() }
        #expect(model.selectedVerb?.infinitive == "machen")
        #expect(cache.entries["aufstehen"]?.variants[0].table(for: .perfekt) == nil)
    }

    @Test func cancelAndReturnToSavedFormAvoidsRequest() async {
        let service = DemandService()
        let model = ConjugationViewModel(service: service, cache: PreviewCache(), credentials: PreviewCredentials(), loadingMode: { .onDemand })
        model.query = "aufstehen"; model.submit()
        await eventually { !model.isLoading }
        service.suspendForms = true
        model.selectedTense = .perfekt
        await eventually { service.pending[.perfekt] != nil }
        model.cancel()
        #expect(!model.isLoading)
        model.selectedTense = .praesens
        service.finish(.perfekt)
        for _ in 0..<20 { await Task.yield() }
        #expect(model.table?.tense == .praesens)
        #expect(service.formRequests.count == 1)
    }

    @Test func everythingCompletesPartialCacheAndPreservesSelectedFormOnRefresh() async throws {
        let service = DemandService(), cache = PreviewCache()
        try cache.write(VerbFixtures.result("aufstehen").restricted(to: [.praesens]), for: "aufstehen")
        let model = ConjugationViewModel(service: service, cache: cache, credentials: PreviewCredentials(), loadingMode: { .everything })
        model.query = "aufstehen"; model.submit()
        await eventually { !model.isLoading }
        #expect(service.initialRequests == [VerbTense.allCases])
        model.selectedTense = .konjunktivIIWuerde
        #expect(service.formRequests.isEmpty)
        model.refresh()
        await eventually { !model.isLoading }
        #expect(model.selectedTense == .konjunktivIIWuerde)
        #expect(model.selectedVerb?.tables.count == 15)
    }

    @Test func switchingFormsDoesNotCancelEverythingLoading() async throws {
        let service = DemandService(), cache = PreviewCache()
        service.suspendLookup = true
        try cache.write(VerbFixtures.result("aufstehen").restricted(to: [.praesens, .perfekt]), for: "aufstehen")
        let model = ConjugationViewModel(service: service, cache: cache, credentials: PreviewCredentials(), loadingMode: { .everything })
        model.query = "aufstehen"; model.submit()
        await eventually { service.pendingLookup != nil }
        model.selectedTense = .perfekt
        #expect(model.isLoading)
        #expect(model.table?.tense == .perfekt)
        model.selectedTense = .imperativ
        #expect(model.isLoading)
        #expect(service.initialRequests.count == 1)
        service.pendingLookup?.resume(returning: VerbFixtures.result("aufstehen"))
        service.pendingLookup = nil
        await eventually { !model.isLoading }
        #expect(model.table?.tense == .imperativ)
        #expect(model.selectedVerb?.tables.count == 15)
    }

    @Test func mergingTablesKeepsOtherMeaningsSeparate() throws {
        let base = PreviewVerb.fahren.restricted(to: [.praesens])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        var variants = object["variants"] as! [[String: Any]]
        var other = variants[0]
        other["meaning"] = "to drive a vehicle"
        var parts = other["principalParts"] as! [String: Any]
        parts["auxiliary"] = "haben"
        other["principalParts"] = parts
        variants.append(other)
        object["variants"] = variants
        let partial = try JSONDecoder().decode(VerbLookupResult.self, from: JSONSerialization.data(withJSONObject: object)).validated()
        let perfect = try #require(PreviewVerb.fahren.variants[0].table(for: .perfekt))
        let have = ["habe ", "hast ", "hat ", "haben ", "habt ", "haben "]
        let rows = perfect.orderedRows.enumerated().map { index, row in
            ConjugationRow(person: row.person,
                segments: [.init(text: have[index], role: .auxiliary, isIrregular: false)] + row.segments.dropFirst(),
                irregularExplanation: row.irregularExplanation)
        }
        let table = TenseTable(tense: .perfekt, rule: "haben + participle", explanation: "Driving a particular vehicle uses haben.", rows: rows)
        let merged = try partial.merging([table], into: partial.variants[1].id)
        #expect(merged.variants[0].table(for: .perfekt) == nil)
        #expect(merged.variants[1].table(for: .perfekt)?.orderedRows.first?.text == "habe gefahren")
        #expect(merged.variants[1].principalParts.auxiliary == .haben)
        #expect(merged.variants[0].tables == base.variants[0].tables)
    }

    @Test func settingsDefaultToOnDemandAndPersist() throws {
        let suite = "KonjuGoTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(VerbLoadingMode.saved(in: defaults) == .onDemand)
        defaults.set(VerbLoadingMode.everything.rawValue, forKey: VerbLoadingMode.defaultsKey)
        #expect(VerbLoadingMode.saved(in: defaults) == .everything)
        defaults.set("old-value", forKey: VerbLoadingMode.defaultsKey)
        #expect(VerbLoadingMode.saved(in: defaults) == .onDemand)
    }

    @Test func partialDiskCacheAndLegacyCompleteCacheRemainUsable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = VerbCache(directory: directory)
        let partial = VerbFixtures.result("aufstehen").restricted(to: [.praesens, .imperativ])
        try cache.write(partial, for: "aufstehen")
        #expect(cache.read("aufstehen") == partial)
        try cache.write(VerbFixtures.result("aufstehen"), for: "aufstehen")
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var entry = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        entry["version"] = 7
        try JSONSerialization.data(withJSONObject: entry).write(to: file)
        #expect(cache.read("aufstehen")?.variants[0].tables.count == 15)
    }

    @Test func formRequestKeepsMeaningAndOnlyDecodesRequestedTable() throws {
        let profile = VerbFixtures.result("aufstehen").variants[0]
        let body = try #require(JSONSerialization.jsonObject(with: OpenAIVerbService.requestBody(query: "aufstehen", forms: [.imperativ], profile: profile)) as? [String: Any])
        let inputString = try #require(body["input"] as? String)
        let input = try #require(JSONSerialization.jsonObject(with: Data(inputString.utf8)) as? [String: Any])
        #expect(input["requestedForms"] as? [String] == ["imperativ"])
        let context = try #require(input["verbProfile"] as? [String: Any])
        #expect(context["meaning"] as? String == profile.meaning)
        #expect((context["tables"] as? [Any])?.isEmpty == true)
        let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["required"] as? [String] == ["tables"])
        let table = try #require(profile.table(for: .imperativ))
        let tableObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode([table]))
        let content = try JSONSerialization.data(withJSONObject: ["tables": tableObject])
        let envelope = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": String(decoding: content, as: UTF8.self)]]]]])
        #expect(try OpenAIVerbService.decodeTables(envelope, for: profile, requiredForms: [.imperativ]) == [table])
        #expect(throws: LookupError.self) { try OpenAIVerbService.decodeTables(envelope, for: profile, requiredForms: [.perfekt]) }
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["KONJUGO_LIVE_TESTS"] == "1"))
@MainActor struct OnDemandLiveTests {
    @Test func presentThenIndividualFormsUsingTerra() async throws {
        let key = try KonjuGoKeychain().load()
        try #require(!key.isEmpty, "Save an OpenAI key in KonjuGo Settings before running live tests.")
        let service = OpenAIVerbService()
        var result = try await service.lookup("aufstehen", apiKey: key, forms: [.praesens])
        let profile = try #require(result.variants.first)
        #expect(profile.tables.map(\.tense) == [.praesens])
        #expect(profile.table(for: .praesens)?.orderedRows.first?.text == "stehe auf")
        for form in [VerbTense.perfekt, .imperativ, .konjunktivIIWuerde] {
            let tables = try await service.loadTables(for: profile, forms: [form], apiKey: key)
            #expect(tables.map(\.tense) == [form])
            result = try result.merging(tables, into: profile.id)
            let first = try #require(tables.first?.orderedRows.first?.text)
            switch form {
            case .perfekt: #expect(first == "bin aufgestanden")
            case .imperativ: #expect(["steh auf", "stehe auf"].contains(first))
            case .konjunktivIIWuerde: #expect(first == "würde aufstehen")
            default: break
            }
        }
        #expect(result.variants[0].tables.count == 4)
        #expect(result.variants[0].meaning == profile.meaning)
    }
}
