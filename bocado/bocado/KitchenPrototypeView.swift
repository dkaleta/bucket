import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct KitchenPrototypeView: View {
    @State private var tab: KitchenTab = .recipes
    @State private var recipeID: KitchenRecipe.ID?
    @State private var openRecipe: KitchenRecipe?
    @State private var pantryFilter: PantryFilter = .all

    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var mapState = DishMapState()
    @Environment(\.modelContext) private var context

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
            KitchenRecipeDetail(recipe: recipe)
        }
        .preferredColorScheme(.light)
        .task { PantryIcons.shared.start(in: context.container) }
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
                               isActive: tab == .recipes, openPantry: { tab = .pantry }) {
                    openRecipe = $0
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { phoneHeader }
            .background(KitchenTheme.paper)
        case .pantry:
            PantryView(filter: $pantryFilter)
                .safeAreaInset(edge: .top, spacing: 0) { phoneHeader }
                .background(KitchenTheme.paper)
        case .map:
            ContentView(state: mapState)
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

enum KitchenTheme {
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let cream = Color(red: 1, green: 0.993, blue: 0.972)
    static let ink = Color(red: 0.15, green: 0.22, blue: 0.16)
    static let muted = Color(red: 0.34, green: 0.38, blue: 0.32)
    static let sage = Color(red: 0.89, green: 0.91, blue: 0.85)
    static let butter = Color(red: 0.97, green: 0.92, blue: 0.76)
    static let line = Color(red: 0.89, green: 0.87, blue: 0.82)
}

struct KitchenHeading: View {
    let title: Text
    let subtitle: String

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 47

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            title
                .font(.system(size: titleSize, weight: .medium, design: .serif))
                .tracking(-1.9)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(KitchenTheme.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    KitchenPrototypeView()
        .modelContainer(for: PantryIngredient.self, inMemory: true)
}
