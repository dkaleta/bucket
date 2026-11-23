import Foundation
import Observation

@MainActor @Observable
final class RecipesViewModel {
    private(set) var recipes: [RecipeDetailViewModel] = []
    private(set) var pantry: [PantryFood] = []
    private(set) var loading = false
    private(set) var error: String?
    private var request: Task<Void, Never>?

    private let generator: any RecipeGenerating
    private let images: any ImageGenerating
    private let cache: RecipeCache
    private var photoTasks: [Task<Void, Never>] = []

    init(generator: any RecipeGenerating, images: any ImageGenerating, cache: RecipeCache) {
        self.generator = generator
        self.images = images
        self.cache = cache
        if let saved = cache.read() {
            pantry = saved.pantry
            recipes = saved.recipes.map(makeRecipe)
        }
    }

    private func makeRecipe(_ record: RecipeRecord) -> RecipeDetailViewModel {
        RecipeDetailViewModel(record: record, generator: generator, images: images) { [weak self] in
            self?.saveMenu()
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
            cancelPhotos()
            recipes = []
            pantry = foods
        }
        error = nil
        loading = !foods.isEmpty
        guard !foods.isEmpty else { return }
        request = Task {
            do {
                let ideas = try await generator.ideas(for: foods, previous: previousNames)
                try Task.checkCancellation()
                cancelPhotos()
                recipes = ideas.map { idea in
                    makeRecipe(RecipeRecord(id: UUID(), idea: idea, foods: foods.filter { idea.pantryNames.contains($0.name) }))
                }
                saveMenu()
                startPhotos()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func startPhotos() {
        guard photoTasks.isEmpty else { return }
        photoTasks = recipes.filter { $0.record.photo == nil && $0.photoError == nil }.map { recipe in
            Task { await recipe.loadPhoto() }
        }
    }

    private func cancelPhotos() {
        photoTasks.forEach { $0.cancel() }
        photoTasks.removeAll()
    }

    private func saveMenu() {
        cache.write(.init(pantry: pantry, recipes: recipes.map(\.record)))
    }
}
