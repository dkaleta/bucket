import FactoryKit
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct KitchenRootView: View {
    @State private var tab: KitchenTab = .recipes
    @State private var recipeID: RecipeDetailViewModel.ID?
    @State private var openRecipe: RecipeDetailViewModel?
    private let dependencies: AppContainer
    @State private var pantry: PantryViewModel
    private let recipes: RecipesViewModel

    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var mapState = DishMapViewModel()

    init(dependencies: AppContainer) {
        self.dependencies = dependencies
        _pantry = State(initialValue: dependencies.pantryViewModel())
        recipes = dependencies.recipesViewModel()
    }

    var body: some View {
        Group {
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                sidebar
            } else {
                tabs
            }
            #elseif os(macOS)
            sidebar
            #else
            tabs
            #endif
        }
        .foregroundStyle(KitchenTheme.ink)
        .tint(KitchenTheme.ink)
        .sheet(item: $openRecipe) { recipe in
            RecipeDetailView(recipe: recipe)
        }
        .preferredColorScheme(.light)
        .task { pantry.icons.start() }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            ForEach(KitchenTab.allCases) { item in
                Tab(item.rawValue, systemImage: item.symbol, value: item) {
                    destination(item)
                }
                .accessibilityIdentifier(item.identifier)
            }
        }
    }

    private var sidebar: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: Binding<KitchenTab?>($tab)) {
                ForEach(KitchenTab.allCases) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.symbol)
                    }
                    .accessibilityIdentifier(item.identifier)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("bocado")
            .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 320)
        } detail: {
            ZStack {
                ForEach(KitchenTab.allCases) { item in
                    if item != .map || tab == .map {
                        destination(item)
                            .zIndex(tab == item ? 1 : 0)
                            .opacity(tab == item ? 1 : 0)
                            .allowsHitTesting(tab == item)
                            .accessibilityHidden(tab != item)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder private func destination(_ item: KitchenTab) -> some View {
        switch item {
        case .recipes:
            GeometryReader { geometry in
                RecipeCarousel(width: min(geometry.size.width, 760), recipeID: $recipeID,
                               isActive: tab == .recipes, openPantry: { tab = .pantry },
                               openRecipe: { openRecipe = $0 }, shelf: recipes)
            }
            .safeAreaInset(edge: .top, spacing: 0) { phoneHeader }
            .background(KitchenTheme.paper)
        case .pantry:
            PantryView(model: pantry, makeScan: { dependencies.scanViewModel($0) })
                .safeAreaInset(edge: .top, spacing: 0) { phoneHeader }
                .background(KitchenTheme.paper)
        case .map:
            DishMapView(state: mapState)
        }
    }

    @ViewBuilder private var phoneHeader: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            wordmark
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(KitchenTheme.paper)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(KitchenTheme.line).frame(height: 1)
                }
        }
        #endif
    }

    private var wordmark: some View {
        HStack(spacing: 9) {
            Image(systemName: "fork.knife")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KitchenTheme.cream)
                .frame(width: 34, height: 34)
                .background(KitchenTheme.ink, in: Circle())
                .accessibilityHidden(true)
            Text("bocado")
                .font(.system(.title, design: .serif, weight: .bold))
                .tracking(-1.2)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum KitchenTab: String, CaseIterable, Identifiable {
    case recipes = "Recipes"
    case pantry = "Pantry"
    case map = "Map"

    var id: Self { self }
    var identifier: String { "kitchen-tab-" + rawValue.lowercased() }

    var symbol: String {
        switch self {
        case .recipes: "book"
        case .pantry: "basket"
        case .map: "map"
        }
    }
}

#Preview {
    let storage = try! ModelContainer(for: PantryIngredient.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    KitchenRootView(dependencies: AppContainer(storage: storage))
        .modelContainer(storage)
}
