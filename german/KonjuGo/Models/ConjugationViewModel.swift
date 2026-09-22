import Foundation
import Observation

@MainActor @Observable final class ConjugationViewModel {
    var query = ""
    var selectedTense: VerbTense = .praesens {
        didSet {
            if selectedTense != oldValue && !applyingResponse { ruleExpanded = false; loadSelectedForm() }
        }
    }
    var selectedVariantID = "" {
        didSet {
            if selectedVariantID != oldValue && !applyingResponse { ruleExpanded = false; loadSelectedForm() }
        }
    }
    var ruleExpanded = false
    private(set) var result: VerbLookupResult?
    private(set) var isLoading = false
    private(set) var loadingDescription = ""
    private(set) var errorMessage: String?
    private(set) var cacheNotice: String?
    private(set) var isCached = false
    private(set) var submittedQuery = ""
    private let service: any VerbLookingUp
    private let cache: any VerbCaching
    private let credentials: any KonjuGoCredentials
    private let loadingMode: () -> VerbLoadingMode
    private var work: Task<Void, Never>?
    private var requestID = UUID()
    private var applyingResponse = false
    private var loadingAllForms = false

    var selectedVerb: VerbProfile? {
        result?.variants.first { $0.id == selectedVariantID } ?? result?.variants.first
    }
    var table: TenseTable? { selectedVerb?.table(for: selectedTense) }

    init(service: any VerbLookingUp, cache: any VerbCaching, credentials: any KonjuGoCredentials,
         loadingMode: @escaping () -> VerbLoadingMode = { VerbLoadingMode.saved() }) {
        self.service = service
        self.cache = cache
        self.credentials = credentials
        self.loadingMode = loadingMode
    }

    func submit() {
        let normalized = query.normalizedVerbQuery
        cancel()
        errorMessage = nil
        cacheNotice = nil
        guard !normalized.isEmpty, normalized.count <= 100 else {
            errorMessage = normalized.isEmpty ? "Enter a German verb to begin." : "Enter a single verb, such as machen or sich freuen."
            return
        }
        submittedQuery = normalized
        applyingResponse = true
        result = nil
        selectedVariantID = ""
        selectedTense = .praesens
        ruleExpanded = false
        isCached = false
        applyingResponse = false
        if let saved = cache.read(normalized), let validated = try? saved.validated() {
            accept(validated, cached: true)
            if loadingMode() == .everything && !hasAllForms {
                loadInitial(forms: VerbTense.allCases)
            } else { loadSelectedForm() }
        } else {
            loadInitial(forms: loadingMode() == .onDemand ? [.praesens] : VerbTense.allCases)
        }
    }

    private var hasAllForms: Bool {
        result?.status == .found && result?.variants.allSatisfy {
            Set($0.tables.map(\.tense)) == Set(VerbTense.allCases)
        } == true
    }

    func refresh() {
        guard !submittedQuery.isEmpty else { return }
        if loadingMode() == .everything { loadInitial(forms: VerbTense.allCases) }
        else if selectedVerb != nil { loadSelectedForm(force: true) }
        else { loadInitial(forms: [.praesens]) }
    }
    func retry() { refresh() }
    func chooseSuggestion(_ suggestion: String) { query = suggestion; submit() }

    func loadSelectedForm(force: Bool = false) {
        guard let profile = selectedVerb else { return }
        if !force, loadingAllForms, loadingMode() == .everything { return }
        cancel()
        errorMessage = nil
        cacheNotice = nil
        if !force, profile.table(for: selectedTense) != nil {
            isCached = true
            return
        }
        if loadingMode() == .everything {
            loadInitial(forms: VerbTense.allCases)
            return
        }
        let form = selectedTense
        let profileID = profile.id
        start(description: "Loading \(form.title) for \(profile.infinitive)…") { [service] key in
            let tables = try await service.loadTables(for: profile, forms: [form], apiKey: key)
            // Validate before merging so unrelated/missing tables cannot silently satisfy a request.
            var responseProfile = profile
            responseProfile.tables = tables
            _ = try VerbLookupResult(status: .found, message: nil, suggestions: [], variants: [responseProfile])
                .validated(requiredForms: [form])
            return .tables(tables, profileID: profileID)
        }
    }

    private func loadInitial(forms: [VerbTense]) {
        let query = submittedQuery
        start(description: forms.count == 1 ? "Loading Präsens for \(query)…" : "Loading all forms for \(query)…") { [service] key in
            .lookup(try await service.lookup(query, apiKey: key, forms: forms).validated(requiredForms: forms))
        }
        loadingAllForms = forms.count == VerbTense.allCases.count
    }

    private enum Response {
        case lookup(VerbLookupResult)
        case tables([TenseTable], profileID: String)
    }

    private func start(description: String, operation: @escaping (String) async throws -> Response) {
        cancel()
        errorMessage = nil
        cacheNotice = nil
        isLoading = true
        loadingDescription = description
        let id = requestID
        let query = submittedQuery
        work = Task { [weak self] in
            guard let self else { return }
            defer { if requestID == id { isLoading = false; loadingAllForms = false } }
            do {
                let key = try credentials.load()
                guard !key.isEmpty else { throw LookupError("Add your OpenAI API key in Settings to look up a new verb.") }
                let response = try await operation(key)
                guard requestID == id, !Task.isCancelled else { return }
                let accepted: VerbLookupResult
                switch response {
                case .lookup(let lookup): accepted = lookup
                case .tables(let tables, let profileID):
                    guard let result else { return }
                    accepted = try result.merging(tables, into: profileID)
                }
                accept(accepted, cached: false)
                do { try cache.write(accepted, for: query) }
                catch { cacheNotice = "This result is available now, but could not be saved for offline use." }
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                if let urlError = error as? URLError {
                    errorMessage = urlError.code == .timedOut
                        ? "The lookup took too long. Please try again."
                        : "Could not reach OpenAI. Check your connection or look up a previously saved verb."
                } else { errorMessage = error.localizedDescription }
            }
        }
    }

    private func accept(_ response: VerbLookupResult, cached: Bool) {
        applyingResponse = true
        defer { applyingResponse = false }
        result = response
        isCached = cached
        if !response.variants.contains(where: { $0.id == selectedVariantID }) {
            selectedVariantID = response.variants.first?.id ?? ""
        }
    }

    func cancel() {
        requestID = UUID()
        work?.cancel()
        work = nil
        isLoading = false
        loadingAllForms = false
    }
}
