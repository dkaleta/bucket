import ImageIO
import SwiftData
import SwiftUI

enum PantryFilter: Equatable {
    case all
    case useSoon
    case area(PantryArea)
}

struct PantryView: View {
    @Binding var filter: PantryFilter

    @Query(sort: \PantryIngredient.name) private var ingredients: [PantryIngredient]
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var scanning = false
    @State private var sourceItem: PantryIngredient?
    @Environment(\.modelContext) private var context

    private var useSoonCount: Int {
        ingredients.filter(\.useSoon).count
    }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filteredIngredients: [PantryIngredient] {
        let scoped: [PantryIngredient] = switch filter {
        case .all: ingredients
        case .useSoon: ingredients.filter(\.useSoon)
        case .area(let area): ingredients.filter { $0.area == area }
        }
        return query.isEmpty ? scoped : scoped.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                KitchenHeading(
                    title: Text("Your \(Text("pantry").italic())"),
                    subtitle: "\(ingredients.count) ingredients in your kitchen."
                )
                .padding(.horizontal, 24)

                Button {
                    scanning = true
                } label: {
                    Label("Scan ingredients", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(KitchenTheme.ink)
                .padding(.horizontal, 24)

                if ingredients.isEmpty {
                    ContentUnavailableView("Your pantry is empty", systemImage: "basket",
                        description: Text("Scan a shelf, spice rack or fridge to start your list."))
                } else {
                    if useSoonCount > 0 {
                        useSoonButton.padding(.horizontal, 24)
                    }
                    if let name = PantryIcons.shared.currentName {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Drawing icon for \(name)…").font(.footnote)
                        }
                        .padding(.horizontal, 24)
                    } else if let error = PantryIcons.shared.errorMessage {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error).font(.footnote)
                            Button("Retry pantry icons") { PantryIcons.shared.start(in: context.container) }
                        }
                        .padding(.horizontal, 24)
                    }
                    searchField.padding(.horizontal, 24)
                    filterBar
                }

                let matches = filteredIngredients
                if !ingredients.isEmpty && matches.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                VStack(spacing: 22) {
                    ForEach(PantryArea.allCases) { area in
                        let rows = matches.filter { $0.area == area }
                        if !rows.isEmpty {
                            section(area, ingredients: rows)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $sourceItem) { ingredient in
            PantryScanView(replacing: ingredient, didSave: showAll)
        }
        .sheet(isPresented: $scanning) {
            PantryScanView(didSave: showAll)
        }
    }

    private func showAll() {
        searchText = ""
        filter = .all
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(KitchenTheme.muted)
                .accessibilityHidden(true)
            TextField("Search ingredients", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .autocorrectionDisabled()
                .accessibilityIdentifier("pantry-search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KitchenTheme.muted)
                        .frame(minWidth: 36, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 46)
        .background(KitchenTheme.cream, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(searchFocused ? KitchenTheme.ink : KitchenTheme.line)
                .allowsHitTesting(false)
        }
    }

    private var useSoonButton: some View {
        Button {
            filter = filter == .useSoon ? .all : .useSoon
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(KitchenTheme.cream.opacity(0.72), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Use soon")
                        .font(.subheadline.weight(.bold))
                    Text("\(useSoonCount) ingredients to cook with first")
                        .font(.footnote)
                        .foregroundStyle(KitchenTheme.muted)
                }

                Spacer(minLength: 6)
                Image(systemName: filter == .useSoon ? "checkmark" : "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .padding(12)
            .padding(.trailing, 4)
            .background(KitchenTheme.butter, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(filter == .useSoon ? KitchenTheme.ink : .clear)
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == .useSoon ? [.isSelected] : [])
        .accessibilityHint(filter == .useSoon ? "Show all ingredients" : "Show only ingredients to use soon")
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterButton("All", value: .all)
                ForEach(PantryArea.allCases) { area in
                    filterButton(area.rawValue, value: .area(area))
                }
            }
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    private func filterButton(_ title: String, value: PantryFilter) -> some View {
        Button {
            filter = value
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .foregroundStyle(filter == value ? KitchenTheme.cream : KitchenTheme.ink)
                .background(filter == value ? KitchenTheme.ink : KitchenTheme.cream, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(filter == value ? .clear : KitchenTheme.line)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == value ? [.isSelected] : [])
    }

    private func section(_ area: PantryArea, ingredients: [PantryIngredient]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(area.rawValue)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(ingredients.count)")
                    .font(.footnote.monospacedDigit().weight(.medium))
                    .foregroundStyle(KitchenTheme.muted)
                    .accessibilityLabel("\(ingredients.count) ingredients")
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(ingredients) { ingredient in
                    if ingredient.id != ingredients.first?.id {
                        Rectangle()
                            .fill(KitchenTheme.line)
                            .frame(height: 1)
                            .padding(.leading, 62)
                    }
                    Button { sourceItem = ingredient } label: {
                        IngredientRow(ingredient: ingredient).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .accessibilityHint("View ingredient source or rescan this item")
                        .contextMenu {
                            Button(ingredient.useSoon ? "Clear use soon" : "Mark use soon",
                                   systemImage: "hourglass") {
                                ingredient.useSoon.toggle()
                                if useSoonCount == 0 && filter == .useSoon { filter = .all }
                            }
                            Button("Remove from pantry", systemImage: "trash", role: .destructive) {
                                ingredient.releaseSource(in: context)
                                context.delete(ingredient)
                                filter = .all
                            }
                        }
                }
            }
            .background(KitchenTheme.cream, in: .rect(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17).strokeBorder(KitchenTheme.line)
            }
        }
    }
}

private struct IngredientRow: View {
    let ingredient: PantryIngredient

    var body: some View {
        HStack(spacing: 11) {
            Group {
                if let png = ingredient.iconPNG,
                   let source = CGImageSourceCreateWithData(png as CFData, nil),
                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text(ingredient.emoji).font(.system(size: 20))
                }
            }
            .frame(width: 38, height: 38)
            .background(KitchenTheme.paper, in: .rect(cornerRadius: 11))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.semibold))
                if ingredient.useSoon {
                    Label("Use soon", systemImage: "hourglass")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(red: 0.47, green: 0.31, blue: 0.12))
                }
            }
            Spacer(minLength: 8)
            Text(ingredient.quantity)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(KitchenTheme.muted)
                .multilineTextAlignment(.trailing)
            Image(systemName: ingredient.sourcePhoto == nil ? "chevron.right" : "photo")
                .foregroundStyle(KitchenTheme.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
