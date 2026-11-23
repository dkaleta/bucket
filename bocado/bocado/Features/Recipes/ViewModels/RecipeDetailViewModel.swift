import Foundation
import Observation

@MainActor @Observable
final class RecipeDetailViewModel: Identifiable {
    private(set) var record: RecipeRecord
    nonisolated let id: UUID
    var name: String { record.idea.name }
    var minutes: Int { record.idea.minutes }
    var summary: String { record.idea.summary }
    var photoError: String?
    var methodError: String?
    private(set) var drawing = false
    private(set) var writing = false

    private let generator: any RecipeGenerating
    private let images: any ImageGenerating
    private let didUpdate: () -> Void

    init(record: RecipeRecord, generator: any RecipeGenerating, images: any ImageGenerating,
         didUpdate: @escaping () -> Void) {
        self.generator = generator
        self.images = images
        self.didUpdate = didUpdate
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
            record.photo = try await images.generate(prompt: prompt, transparent: false, maxPixels: 960)
            didUpdate()
        } catch { if !Task.isCancelled { photoError = error.localizedDescription } }
    }

    func loadMethod() async {
        guard record.method == nil, !writing else { return }
        writing = true
        methodError = nil
        defer { writing = false }
        do {
            record.method = try await generator.method(for: record)
            didUpdate()
        } catch { if !Task.isCancelled { methodError = error.localizedDescription } }
    }
}
