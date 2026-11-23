import SwiftData
import Foundation

enum PantryArea: String, Codable, CaseIterable, Identifiable {
    case produce = "Produce"
    case fridge = "Fridge"
    case cupboard = "Cupboard"

    var id: Self { self }
}

@Model
final class PantrySourcePhoto {
    @Attribute(.externalStorage) var jpeg: Data
    @Relationship(deleteRule: .nullify, inverse: \PantryIngredient.sourcePhoto)
    var ingredients: [PantryIngredient] = []

    init(jpeg: Data) { self.jpeg = jpeg }
}

@Model
final class PantryIngredient {
    @Attribute(.unique) var lookupName: String
    var name: String
    var quantity: String
    var emoji: String
    @Attribute(.externalStorage) var iconPNG: Data?
    var storageArea: String
    var useSoon = false
    var sourcePhoto: PantrySourcePhoto?
    var sourceX: Double?
    var sourceY: Double?
    var detectedName: String?

    func releaseSource(in context: ModelContext) {
        guard let photo = sourcePhoto else { return }
        sourcePhoto = nil
        if !photo.ingredients.contains(where: { $0 !== self && !$0.isDeleted }) {
            context.delete(photo)
        }
    }

    var area: PantryArea { PantryArea(rawValue: storageArea) ?? .cupboard }

    init(_ item: ScannedIngredient) {
        lookupName = item.lookupName
        name = item.name
        quantity = item.quantity
        emoji = item.emoji
        storageArea = item.area.rawValue
    }
}
