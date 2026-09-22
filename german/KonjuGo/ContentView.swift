import SwiftUI

struct ContentView: View {
    @State private var model: ConjugationViewModel
    private let credentials: any KonjuGoCredentials
    @State private var settingsPresented = false
    @FocusState private var inputFocused: Bool

    init(model: ConjugationViewModel, credentials: any KonjuGoCredentials) {
        _model = State(initialValue: model)
        self.credentials = credentials
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    search
                    if model.isLoading {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text(model.loadingDescription).font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel", action: model.cancel).font(.callout)
                        }
                    }
                    if let error = model.errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(error).font(.callout)
                            if !model.submittedQuery.isEmpty {
                                Button("Try again", action: model.retry).disabled(model.isLoading)
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("lookupError")
                    }
                    if let result = model.result, result.status == .notFound {
                        notFound(result)
                    } else if let verb = model.selectedVerb {
                        if let variants = model.result?.variants, variants.count > 1 {
                            Picker("Meaning / use", selection: $model.selectedVariantID) {
                                ForEach(variants) { Text($0.meaning).tag($0.id) }
                            }
                            .pickerStyle(.menu).accessibilityIdentifier("meaningPicker")
                        }
                        VerbDetailsView(verb: verb)
                        Divider()
                        tensePicker
                        if let table = model.table {
                            ConjugationTableView(table: table, ruleExpanded: $model.ruleExpanded)
                        } else if !model.isLoading && model.errorMessage == nil {
                            Button("Load \(model.selectedTense.title)") { model.loadSelectedForm() }
                                .accessibilityIdentifier("loadSelectedForm")
                        }
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.isCached ? "Saved on this device" : "Generated with OpenAI")
                                if let notice = model.cacheNotice { Text(notice) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh)
                                .font(.caption).disabled(model.isLoading)
                                .help("Generate a fresh conjugation using OpenAI")
                        }
                    } else if !model.isLoading && model.errorMessage == nil {
                        emptyState
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 28)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .navigationTitle("KonjuGo")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .toolbar {
                ToolbarItem {
                    Button("Settings", systemImage: "gearshape") { settingsPresented = true }
                        .accessibilityIdentifier("settingsButton")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 600)
        #endif
        .sheet(isPresented: $settingsPresented) { KonjuGoSettingsView(credentials: credentials) }
        .onChange(of: model.selectedTense) { model.ruleExpanded = false }
        .onChange(of: model.selectedVariantID) { model.ruleExpanded = false }
        .onDisappear { model.cancel() }
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One verb. Every mood.").font(.title2.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { input; searchButton }
                VStack(alignment: .leading, spacing: 10) { input; searchButton }
            }
            Text("Enter a German infinitive, with “sich” if reflexive.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var input: some View {
        TextField("e.g. fahren or sich freuen", text: $model.query)
            .textFieldStyle(.plain).font(.body)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .frame(minWidth: 180)
            .autocorrectionDisabled()
            .focused($inputFocused)
            .onSubmit { submit() }
            .accessibilityLabel("German verb")
            .accessibilityIdentifier("verbInput")
            #if !os(macOS)
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            #endif
    }
    private var searchButton: some View {
        Button("Conjugate", action: submit)
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(model.query.trimmed.isEmpty)
            .accessibilityIdentifier("conjugateButton")
    }
    private func submit() { inputFocused = false; model.submit() }

    private var tensePicker: some View {
        HStack {
            Text("Mood / tense").font(.subheadline.weight(.medium))
            Spacer()
            Picker("Mood / tense", selection: $model.selectedTense) {
                ForEach(VerbMood.allCases) { mood in
                    if mood != .indicative { Divider() }
                    Section(mood.title) {
                        ForEach(mood.forms) { Text($0.title).tag($0) }
                    }
                }
            }
            .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("tensePicker")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "text.book.closed").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
            Text("See how a verb works.").font(.title3.weight(.medium))
            Text("Explore statements, reported speech, hypothetical forms, and commands. Understand the rules and spot irregular changes at a glance.")
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { examples }
                VStack(alignment: .leading) { examples }
            }
        }
        .padding(.vertical, 28)
    }
    @ViewBuilder private var examples: some View {
        ForEach(["machen", "fahren", "sich freuen"], id: \.self) { example in
            Button(example) { model.query = example; submit() }.buttonStyle(.bordered)
        }
    }
    private func notFound(_ result: VerbLookupResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.message ?? "This verb was not recognized.").foregroundStyle(.secondary)
            ForEach(result.suggestions, id: \.self) { suggestion in
                Button(suggestion) { model.chooseSuggestion(suggestion) }.buttonStyle(.bordered)
            }
        }
    }
}
