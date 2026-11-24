import FactoryKit
import ImageIO
import SwiftData
import SwiftUI

struct PantryView: View {
    @Bindable var model: PantryViewModel
    let makeScan: (PantryIngredient?) -> PantryScanViewModel

    @Query(sort: \PantryIngredient.name) private var ingredients: [PantryIngredient]
    @State private var scanning = false
    @State private var sourceItem: PantryIngredient?

    private var useSoonCount: Int {
        ingredients.filter(\.useSoon).count
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pantry")
                .navigationSubtitle(ingredients.isEmpty ? "" : "\(ingredients.count) ingredients")
                .searchable(text: $model.searchText, prompt: "Search ingredients")
                .autocorrectionDisabled()
                .navigationDestination(item: $sourceItem) { ingredient in
                    IngredientDetailView(ingredient: ingredient, model: model, makeScan: makeScan)
                }
                .toolbar {
                    if !ingredients.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Scan ingredients", systemImage: "camera.viewfinder") {
                                scanning = true
                            }
                        }
                    }
                }
        }
        .foregroundStyle(KitchenTheme.text)
        .tint(KitchenTheme.accent)
        .alert("Couldn’t update your pantry", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
        .sheet(isPresented: $scanning) {
            PantryScanView(model: makeScan(nil), didSave: model.resetFilters)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if ingredients.isEmpty {
                    emptyState.padding(.horizontal, 16)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        filterBar
                        iconStatus.padding(.horizontal, 16)
                    }
                }

                let matches = model.filteredIngredients(ingredients)
                if !ingredients.isEmpty && matches.isEmpty && !model.query.isEmpty {
                    ContentUnavailableView.search(text: model.query)
                }
                VStack(spacing: 32) {
                    ForEach(PantryArea.allCases) { area in
                        let rows = matches.filter { $0.area == area }
                        if !rows.isEmpty {
                            section(area, ingredients: rows)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(KitchenTheme.surface)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing here yet")
                    .font(.title3.weight(.semibold))
                Text("Scan a shelf, spice rack or fridge to start your list.")
                    .font(.subheadline)
                    .foregroundStyle(KitchenTheme.secondary)
            }
            Button {
                scanning = true
            } label: {
                Label("Scan ingredients", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(KitchenTheme.accent, in: .rect(cornerRadius: 14))
                    .contentShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var iconStatus: some View {
        if let name = model.icons.currentName {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Drawing icon for \(name)…")
            }
            .font(.footnote)
            .foregroundStyle(KitchenTheme.secondary)
        } else if let error = model.icons.errorMessage {
            VStack(alignment: .leading, spacing: 4) {
                Text(error).foregroundStyle(KitchenTheme.secondary)
                Button("Retry pantry icons") { model.icons.start() }
                    .fontWeight(.semibold)
            }
            .font(.footnote)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterButton("All", value: .all)
                if useSoonCount > 0 {
                    filterButton("Use soon", value: .useSoon, count: useSoonCount)
                }
                ForEach(PantryArea.allCases) { area in
                    filterButton(area.rawValue, value: .area(area))
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    private func filterButton(_ title: String, value: PantryFilter, count: Int? = nil) -> some View {
        let selected = model.filter == value
        return Button {
            model.filter = selected && value == .useSoon ? .all : value
        } label: {
            HStack(spacing: 6) {
                if count != nil {
                    Circle()
                        .fill(selected ? .white : KitchenTheme.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(title)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .opacity(0.6)
                        .accessibilityLabel("\(count) ingredients")
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? .white : KitchenTheme.text)
            .background(selected ? KitchenTheme.text : .clear, in: Capsule())
            .overlay {
                Capsule().strokeBorder(selected ? .clear : KitchenTheme.hairline)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func section(_ area: PantryArea, ingredients: [PantryIngredient]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(area.rawValue)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("\(ingredients.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(KitchenTheme.secondary)
                    .accessibilityLabel("\(ingredients.count) ingredients")
            }

            VStack(spacing: 0) {
                ForEach(ingredients) { ingredient in
                    if ingredient.id != ingredients.first?.id {
                        Rectangle()
                            .fill(KitchenTheme.hairline)
                            .frame(height: 1)
                            .padding(.leading, 62)
                    }
                    Button { sourceItem = ingredient } label: {
                        IngredientRow(ingredient: ingredient).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows ingredient details")
                        .contextMenu {
                            Button(ingredient.useSoon ? "Clear use soon" : "Mark use soon",
                                   systemImage: "hourglass") {
                                model.toggleUseSoon(ingredient, in: self.ingredients)
                            }
                            Button("Remove from pantry", systemImage: "trash", role: .destructive) {
                                model.remove(ingredient)
                            }
                        }
                }
            }
        }
    }
}

private struct IngredientRow: View {
    let ingredient: PantryIngredient

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let png = ingredient.iconPNG,
                   let source = CGImageSourceCreateWithData(png as CFData, nil),
                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                } else {
                    Text(ingredient.emoji).font(.system(size: 22))
                }
            }
            .frame(width: 48, height: 48)
            .background(KitchenTheme.fill, in: .rect(cornerRadius: 14))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                    .font(.body.weight(.medium))
                if ingredient.useSoon {
                    Text("Use soon")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KitchenTheme.accent)
                }
            }
            Spacer(minLength: 8)
            Text(ingredient.quantity)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(KitchenTheme.secondary)
                .multilineTextAlignment(.trailing)
            Image(systemName: ingredient.sourcePhoto == nil ? "chevron.right" : "photo")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KitchenTheme.secondary.opacity(0.55))
                .frame(width: 18)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Pantry") {
    let dependencies: AppContainer = {
        let storage = try! ModelContainer(for: PantryIngredient.self,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let samples: [ScannedIngredient] = [
            .init(name: "Spinach", quantity: "1 bag", area: .produce, emoji: "🥬", x: 0.5, y: 0.5),
            .init(name: "Eggs", quantity: "6", area: .fridge, emoji: "🥚", x: 0.5, y: 0.5),
            .init(name: "Paprika", quantity: "1 jar", area: .cupboard, emoji: "🌶️", x: 0.5, y: 0.5)
        ]
        for sample in samples {
            let ingredient = PantryIngredient(sample)
            ingredient.useSoon = sample.area == .produce
            storage.mainContext.insert(ingredient)
        }
        try! storage.mainContext.save()
        let container = AppContainer(storage: storage)
        container.openAI.register { OpenAIClient(session: .shared, apiKey: nil) }
        return container
    }()

    PantryView(model: dependencies.pantryViewModel(), makeScan: { dependencies.scanViewModel($0) })
        .modelContainer(dependencies.storage)
        .preferredColorScheme(.light)
}
