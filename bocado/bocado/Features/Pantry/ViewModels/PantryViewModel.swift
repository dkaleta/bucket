import Foundation
import Observation

enum PantryFilter: Equatable {
    case all
    case useSoon
    case area(PantryArea)
}

@Observable
final class PantryViewModel {
    var filter: PantryFilter = .all
    var searchText = ""
    var error: String?
    let icons: PantryIcons
    private let repository: PantryRepository

    init(repository: PantryRepository, icons: PantryIcons) {
        self.repository = repository
        self.icons = icons
    }

    var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    func filteredIngredients(_ ingredients: [PantryIngredient]) -> [PantryIngredient] {
        let scoped: [PantryIngredient] = switch filter {
        case .all: ingredients
        case .useSoon: ingredients.filter(\.useSoon)
        case .area(let area): ingredients.filter { $0.area == area }
        }
        return query.isEmpty ? scoped : scoped.filter { $0.name.localizedStandardContains(query) }
    }

    func resetFilters() {
        searchText = ""
        filter = .all
    }

    func toggleUseSoon(_ ingredient: PantryIngredient, in ingredients: [PantryIngredient]) {
        do {
            try repository.toggleUseSoon(ingredient)
            if filter == .useSoon && !ingredients.contains(where: \.useSoon) { filter = .all }
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ ingredient: PantryIngredient) {
        do {
            try repository.remove(ingredient)
            filter = .all
        } catch { self.error = error.localizedDescription }
    }
}
