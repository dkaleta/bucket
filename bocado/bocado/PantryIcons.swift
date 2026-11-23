import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

@MainActor @Observable
final class PantryIcons {
    static let shared = PantryIcons()
    private(set) var currentName: String?
    private(set) var errorMessage: String?
    private var running = false

    func start(in container: ModelContainer) {
        guard !running else { return }
        running = true
        errorMessage = nil
        Task {
            defer { running = false; currentName = nil }
            do {
                var pending = FetchDescriptor<PantryIngredient>(
                    predicate: #Predicate { $0.iconPNG == nil },
                    sortBy: [SortDescriptor(\.name)]
                )
                pending.fetchLimit = 1
                while let row = try container.mainContext.fetch(pending).first {
                    let name = row.name
                    let key = row.lookupName
                    currentName = name
                    let png = try await Self.generate(name: name)
                    // A scan can rename or remove the ingredient while the request is running.
                    let context = container.mainContext
                    let match = FetchDescriptor<PantryIngredient>(predicate: #Predicate { $0.lookupName == key })
                    if let item = try context.fetch(match).first, item.iconPNG == nil {
                        item.iconPNG = png
                        try context.save()
                    }
                    await Task.yield()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @concurrent static func generate(name: String) async throws -> Data {
        let prompt = """
        Create one square cookbook inventory icon representing the ingredient named below.
        Style: naturalistic hand-painted gouache food illustration with a simple strong silhouette,
        warm daylight, crisp edges and accurate botanical or culinary details. Show the actual ingredient:
        rosemary as needles on a woody sprig, thyme as tiny paired leaves, paprika as ground red powder,
        blends as a visibly varied mixture. Depict only the named ingredient. Use a small unmarked scoop
        or dish only when it makes a powder or blend recognizable. Center the subject and fill 86% of
        the canvas. Isolated on transparent background. No lettering, border or emoji glyphs.
        Ingredient name: \(name)
        """
        return try await KitchenImage.generate(prompt: prompt, transparent: true, maxPixels: 160)
    }
}
