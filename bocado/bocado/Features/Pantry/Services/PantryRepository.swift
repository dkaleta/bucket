import Foundation
import SwiftData

struct PantryRepository {
    let container: ModelContainer

    func toggleUseSoon(_ ingredient: PantryIngredient) throws {
        ingredient.useSoon.toggle()
        try saveChanges()
    }

    func update(_ ingredient: PantryIngredient, quantity: String, area: PantryArea) throws {
        ingredient.quantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        ingredient.storageArea = area.rawValue
        try saveChanges()
    }

    func remove(_ ingredient: PantryIngredient) throws {
        let context = container.mainContext
        ingredient.releaseSource(in: context)
        context.delete(ingredient)
        try saveChanges()
    }

    private func saveChanges() throws {
        do { try container.mainContext.save() }
        catch {
            container.mainContext.rollback()
            throw error
        }
    }

    func save(_ rows: [ReviewedIngredient], photos: [ScanPhoto],
              replacing ingredientID: PersistentIdentifier?, originalPhotoID: UUID?) throws {
        // Use an isolated context so a failed save leaves the visible pantry intact.
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let existing = try writer.fetch(FetchDescriptor<PantryIngredient>())
        var byName = Dictionary(uniqueKeysWithValues: existing.map { ($0.lookupName, $0) })
        let target = existing.first { $0.persistentModelID == ingredientID }
        if ingredientID != nil && target == nil {
            throw KitchenError("This ingredient was removed. Close this scan and open your pantry again.")
        }
        let selected = rows.filter { $0.included && !$0.item.lookupName.isEmpty }
        guard selected.allSatisfy({ photos.indices.contains($0.item.photoIndex) }) else {
            throw KitchenError("A source photo is missing. Process the photos again.")
        }
        let selectedItems = selected.map(\.item)
        guard Set(selectedItems.map(\.lookupName)).count == selectedItems.count else {
            throw KitchenError("Two selected items have the same name. Rename one or deselect it before saving.")
        }
        var sources: [UUID: PantrySourcePhoto] = [:]
        for row in selected {
            var item = row.item
            item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            item.quantity = item.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
            if let target, let match = byName[item.lookupName], target !== match {
                throw KitchenError("Your pantry already contains \(match.name). Choose a distinct name before saving.")
            }
            let stored = target ?? byName[item.lookupName] ?? PantryIngredient(item)
            if stored.modelContext == nil { writer.insert(stored) }
            let photo = photos[item.photoIndex]
            let source: PantrySourcePhoto
            if photo.id == originalPhotoID, let original = target?.sourcePhoto, original.jpeg == photo.jpeg {
                source = original
            } else if let shared = sources[photo.id] {
                source = shared
            } else {
                source = PantrySourcePhoto(jpeg: photo.jpeg)
                writer.insert(source)
                sources[photo.id] = source
            }
            if stored.sourcePhoto !== source {
                stored.releaseSource(in: writer)
                stored.sourcePhoto = source
            }
            stored.sourceX = item.x
            stored.sourceY = item.y
            stored.detectedName = row.detectedName
            stored.name = item.name
            if stored.lookupName != item.lookupName { stored.iconPNG = nil }
            stored.lookupName = item.lookupName
            stored.storageArea = item.area.rawValue
            stored.emoji = item.emoji
            if ingredientID != nil || !item.quantity.isEmpty { stored.quantity = item.quantity }
            byName[item.lookupName] = stored
        }
        try writer.save()
    }
}
