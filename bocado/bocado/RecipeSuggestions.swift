import Foundation
import Observation

nonisolated struct PantryFood: Codable, Equatable {
    let name: String
    let quantity: String
    let useSoon: Bool
}

nonisolated struct RecipeIdea: Codable {
    let name: String
    let summary: String
    let minutes: Int
    var pantryNames: [String]
    var extras: [String]
}

nonisolated struct RecipeMethod: Codable {
    let amounts: [String]
    let steps: [String]
}

nonisolated struct RecipeRecord: Codable {
    let id: UUID
    let idea: RecipeIdea
    let foods: [PantryFood]
    var photo: Data?
    var method: RecipeMethod?
}

@MainActor @Observable
final class KitchenRecipe: Identifiable {
    var record: RecipeRecord
    nonisolated let id: UUID
    var name: String { record.idea.name }
    var minutes: Int { record.idea.minutes }
    var summary: String { record.idea.summary }
    var photoError: String?
    var methodError: String?
    private(set) var drawing = false
    private(set) var writing = false

    init(_ record: RecipeRecord) {
        self.id = record.id
        self.record = record
    }

    func loadPhoto() async {
        guard record.photo == nil, !drawing else { return }
        drawing = true
        photoError = nil
        defer { drawing = false }
        do {
            let ingredients = record.foods.map(\.name) + record.idea.extras
            let prompt = """
            Warm editorial cookbook photograph of the FINISHED dish described below, served on a ceramic plate
            in natural window light. The food fills the frame. Use only the listed ingredients, including
            garnishes. No text, diagrams, packaging or people.
            Dish: \(name). \(summary) Ingredients: \(ingredients.joined(separator: ", ")).
            """
            record.photo = try await KitchenImage.generate(prompt: prompt, transparent: false, maxPixels: 960)
            RecipeShelf.shared.cache()
        } catch { if !Task.isCancelled { photoError = error.localizedDescription } }
    }

    func loadMethod() async {
        guard record.method == nil, !writing else { return }
        writing = true
        methodError = nil
        defer { writing = false }
        do {
            record.method = try await RecipeGenerator.method(for: record)
            RecipeShelf.shared.cache()
        } catch { if !Task.isCancelled { methodError = error.localizedDescription } }
    }
}

@MainActor @Observable
final class RecipeShelf {
    static let shared = RecipeShelf()
    private(set) var recipes: [KitchenRecipe] = []
    private(set) var pantry: [PantryFood] = []
    private(set) var loading = false
    private(set) var error: String?
    private var request: Task<Void, Never>?

    private struct Cache: Codable {
        let pantry: [PantryFood]
        let recipes: [RecipeRecord]
    }

    private let cacheURL = URL.cachesDirectory.appending(path: "pantry-recipes-v1.json")

    private init() {
        if let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode(Cache.self, from: data), saved.recipes.count == 3 {
            pantry = saved.pantry
            recipes = saved.recipes.map(KitchenRecipe.init)
        }
    }

    func load(_ foods: [PantryFood], refresh: Bool = false) {
        if pantry == foods && !refresh && (loading || !recipes.isEmpty || error != nil) {
            startPhotos()
            return
        }
        request?.cancel()
        let previousNames = pantry == foods ? recipes.map(\.name) : []
        if pantry != foods {
            recipes = []
            pantry = foods
        }
        error = nil
        loading = !foods.isEmpty
        guard !foods.isEmpty else { return }
        request = Task {
            do {
                let ideas = try await RecipeGenerator.ideas(for: foods, previous: previousNames)
                try Task.checkCancellation()
                recipes = ideas.map { idea in
                    KitchenRecipe(RecipeRecord(id: UUID(), idea: idea, foods: foods.filter { idea.pantryNames.contains($0.name) }))
                }
                cache()
                startPhotos()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func startPhotos() {
        for recipe in recipes where recipe.record.photo == nil && recipe.photoError == nil {
            Task { await recipe.loadPhoto() }
        }
    }

    func cache() {
        let snapshot = Cache(pantry: pantry, recipes: recipes.map(\.record))
        try? JSONEncoder().encode(snapshot).write(to: cacheURL, options: .atomic)
    }
}
