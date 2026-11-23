import Foundation

struct RecipeCache {
    struct Menu: Codable {
        let pantry: [PantryFood]
        let recipes: [RecipeRecord]
    }

    let url: URL

    func read() -> Menu? {
        guard let data = try? Data(contentsOf: url),
              let menu = try? JSONDecoder().decode(Menu.self, from: data),
              menu.recipes.count == 3 else { return nil }
        return menu
    }

    func write(_ menu: Menu) {
        // The last menu is a best-effort offline cache.
        try? JSONEncoder().encode(menu).write(to: url, options: .atomic)
    }
}
