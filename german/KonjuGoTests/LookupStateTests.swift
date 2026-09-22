import Foundation
import Testing
@testable import KonjuGo

@MainActor private final class StubService: VerbLookingUp {
    var calls: [String] = []
    var shouldSuspend = false
    var failure: Error?
    var response = PreviewVerb.fahren
    var waiters: [String: CheckedContinuation<VerbLookupResult, Error>] = [:]
    func lookup(_ query: String, apiKey: String, forms: [VerbTense]) async throws -> VerbLookupResult {
        calls.append(query)
        if let failure { throw failure }
        if shouldSuspend { return try await withCheckedThrowingContinuation { waiters[query] = $0 } }
        return response
    }
    func loadTables(for verb: VerbProfile, forms: [VerbTense], apiKey: String) async throws -> [TenseTable] {
        let response = try await lookup(verb.infinitive, apiKey: apiKey, forms: forms)
        return response.variants[0].tables.filter { forms.contains($0.tense) }
    }
    func finish(_ query: String, with result: VerbLookupResult) {
        waiters.removeValue(forKey: query)?.resume(returning: result)
    }
}

@MainActor private func eventually(_ condition: () -> Bool) async {
    for _ in 0..<1000 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Expected lookup state was not reached")
}

@Suite @MainActor struct LookupStateTests {
    @Test func cacheWorksWithoutKeyAndSwitchingTensesMakesNoCalls() throws {
        let service = StubService()
        let cache = PreviewCache()
        let keys = PreviewCredentials()
        keys.key = ""
        try cache.write(PreviewVerb.fahren, for: "fahren")
        let model = ConjugationViewModel(service: service, cache: cache, credentials: keys, loadingMode: { .everything })
        model.query = " FAHREN "
        model.submit()
        #expect(model.isCached)
        #expect(model.selectedVerb?.infinitive == "fahren")
        for tense in VerbTense.allCases {
            model.selectedTense = tense
            #expect(model.table?.tense == tense)
        }
        #expect(service.calls.isEmpty)
    }

    @Test func refreshBypassesCacheAndPreservesSelectedTense() async throws {
        let service = StubService()
        let cache = PreviewCache()
        try cache.write(PreviewVerb.fahren, for: "fahren")
        let model = ConjugationViewModel(service: service, cache: cache, credentials: PreviewCredentials(), loadingMode: { .everything })
        model.query = "fahren"; model.submit()
        model.selectedTense = .perfekt
        model.refresh()
        await eventually { !model.isLoading }
        #expect(service.calls == ["fahren"])
        #expect(!model.isCached)
        #expect(model.selectedTense == .perfekt)
        #expect(cache.entries["fahren"] != nil)
        model.query = "fahren"; model.submit()
        #expect(model.selectedTense == .praesens)
        #expect(model.isCached)
    }

    @Test func missingKeyAndNetworkFailureCanBeRetried() async {
        let service = StubService()
        let keys = PreviewCredentials()
        keys.key = ""
        let model = ConjugationViewModel(service: service, cache: PreviewCache(), credentials: keys, loadingMode: { .everything })
        model.query = "fahren"; model.submit()
        await eventually { !model.isLoading }
        #expect(service.calls.isEmpty)
        #expect(model.errorMessage?.contains("Settings") == true)
        keys.key = "test-only"
        service.failure = URLError(.notConnectedToInternet)
        model.retry()
        await eventually { !model.isLoading }
        #expect(model.errorMessage?.contains("connection") == true)
        service.failure = nil
        model.retry()
        await eventually { !model.isLoading }
        #expect(model.errorMessage == nil)
        #expect(model.selectedVerb?.infinitive == "fahren")
    }

    @Test func staleRequestDoesNotOverwriteNewVerbOrCache() async {
        let service = StubService()
        service.shouldSuspend = true
        let cache = PreviewCache()
        let model = ConjugationViewModel(service: service, cache: cache, credentials: PreviewCredentials(), loadingMode: { .everything })
        model.query = "fahren"; model.submit()
        await eventually { service.waiters["fahren"] != nil }
        model.query = "machen"; model.submit()
        await eventually { service.waiters["machen"] != nil }
        service.finish("machen", with: VerbFixtures.result("machen"))
        await eventually { !model.isLoading }
        service.finish("fahren", with: PreviewVerb.fahren)
        for _ in 0..<20 { await Task.yield() }
        #expect(model.selectedVerb?.infinitive == "machen")
        #expect(cache.entries["fahren"] == nil)
        #expect(cache.entries["machen"] != nil)
    }

    @Test func cancellationIgnoresLateCompletion() async {
        let service = StubService()
        service.shouldSuspend = true
        let model = ConjugationViewModel(service: service, cache: PreviewCache(), credentials: PreviewCredentials(), loadingMode: { .everything })
        model.query = "fahren"; model.submit()
        await eventually { service.waiters["fahren"] != nil }
        model.cancel()
        service.finish("fahren", with: PreviewVerb.fahren)
        for _ in 0..<20 { await Task.yield() }
        #expect(!model.isLoading)
        #expect(model.result == nil)
        #expect(model.errorMessage == nil)
    }

    @Test func invalidInputAndSuggestions() async {
        let service = StubService()
        let cache = PreviewCache()
        let model = ConjugationViewModel(service: service, cache: cache, credentials: PreviewCredentials(), loadingMode: { .everything })
        model.query = " \n "; model.submit()
        #expect(model.errorMessage != nil)
        #expect(service.calls.isEmpty)
        service.response = .init(status: .notFound, message: "Try a German infinitive.", suggestions: ["fahren"], variants: [])
        model.query = "fahern"; model.submit()
        await eventually { !model.isLoading }
        #expect(model.result?.status == .notFound)
        #expect(cache.entries.isEmpty)
        service.response = PreviewVerb.fahren
        model.chooseSuggestion("fahren")
        await eventually { !model.isLoading }
        #expect(model.query == "fahren")
        #expect(model.selectedVerb?.infinitive == "fahren")
    }

    @Test func failedRefreshKeepsSavedResult() async throws {
        let service = StubService()
        service.failure = URLError(.timedOut)
        let cache = PreviewCache()
        try cache.write(PreviewVerb.fahren, for: "fahren")
        let model = ConjugationViewModel(service: service, cache: cache, credentials: PreviewCredentials(), loadingMode: { .everything })
        model.query = "fahren"; model.submit(); model.refresh()
        await eventually { !model.isLoading }
        #expect(model.selectedVerb?.infinitive == "fahren")
        #expect(model.isCached)
        #expect(model.errorMessage?.contains("too long") == true)
    }

    @Test func meaningSelectionUsesCorrespondingParadigm() async throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(PreviewVerb.fahren)) as? [String: Any])
        var variants = object["variants"] as! [[String: Any]]
        var transitive = variants[0]
        transitive["meaning"] = "to drive a vehicle"
        var parts = transitive["principalParts"] as! [String: Any]
        parts["auxiliary"] = "haben"; transitive["principalParts"] = parts
        var tables = transitive["tables"] as! [[String: Any]]
        let have = ["habe ", "hast ", "hat ", "haben ", "habt ", "haben "]
        let had = ["hatte ", "hattest ", "hatte ", "hatten ", "hattet ", "hatten "]
        for t in tables.indices {
            var rows = tables[t]["rows"] as! [[String: Any]]
            for r in rows.indices {
                var segments = rows[r]["segments"] as! [[String: Any]]
                if t == 2 { segments[0]["text"] = have[r] }
                if t == 3 { segments[0]["text"] = had[r] }
                if t == 5 { segments[segments.count - 1]["text"] = " haben" }
                rows[r]["segments"] = segments
            }
            tables[t]["rows"] = rows
        }
        transitive["tables"] = tables; variants.append(transitive); object["variants"] = variants
        let result = try JSONDecoder().decode(VerbLookupResult.self, from: JSONSerialization.data(withJSONObject: object)).validated()
        let service = StubService(); service.response = result
        let model = ConjugationViewModel(service: service, cache: PreviewCache(), credentials: PreviewCredentials(), loadingMode: { .everything })
        model.query = "fahren"; model.submit()
        await eventually { !model.isLoading }
        model.selectedTense = .perfekt
        #expect(model.table?.orderedRows.first?.text == "bin gefahren")
        model.selectedVariantID = result.variants[1].id
        #expect(model.table?.orderedRows.first?.text == "habe gefahren")
        #expect(service.calls.count == 1)
    }
}
