import Foundation
import Observation
import SwiftData

@Observable
final class PantryScanViewModel {
    let replacing: PantryIngredient?
    private let scanner: any PantryRecognizing
    private let repository: PantryRepository
    private let icons: PantryIcons
    private var scanTask: Task<Void, Never>?
    private(set) var photos: [ScanPhoto] = []
    var review: [ReviewedIngredient]?
    var message: String?
    private(set) var working = false
    private(set) var importing = false
    var focus = CGPoint(x: 0.5, y: 0.5)
    private var originalPhotoID: UUID?
    var movedMarker = false

    init(replacing: PantryIngredient?, scanner: any PantryRecognizing,
         repository: PantryRepository, icons: PantryIcons) {
        self.replacing = replacing
        self.scanner = scanner
        self.repository = repository
        self.icons = icons
    }

    var limit: Int { replacing == nil ? 8 : 1 }
    var available: Int { replacing == nil ? max(0, limit - photos.count) : 1 }

    func importPhotos<Input>(_ inputs: [Input], read: (Input) async throws -> Data) async {
        guard !importing, !working, review == nil else { return }
        importing = true
        defer { importing = false }

        let capacity = available
        message = inputs.count > capacity ? "Only the first \(capacity) images fit in this scan." : nil
        for input in inputs.prefix(capacity) {
            do {
                let photo = try await ScanPhoto.prepare(read(input))
                try Task.checkCancellation()
                accept(photo)
            } catch {
                if Task.isCancelled { return }
                message = error.localizedDescription
            }
        }
    }

    func removePhoto(_ photo: ScanPhoto) {
        photos.removeAll { $0.id == photo.id }
    }

    private func accept(_ photo: ScanPhoto) {
        if replacing != nil {
            photos = [photo]
            focus = CGPoint(x: 0.5, y: 0.5)
            movedMarker = true
        } else if photos.count < limit {
            photos.append(photo)
        }
    }

    func loadSource() async {
        guard let replacing, let jpeg = replacing.sourcePhoto?.jpeg, photos.isEmpty else { return }
        importing = true
        defer { importing = false }
        do {
            let original = try await ScanPhoto.loadSaved(jpeg)
            photos = [original]
            originalPhotoID = original.id
            focus = CGPoint(x: replacing.sourceX ?? 0.5, y: replacing.sourceY ?? 0.5)
        } catch { message = error.localizedDescription }
    }

    func cancel() {
        scanTask?.cancel()
    }

    var selectedItems: [ScannedIngredient] {
        (review ?? []).filter { $0.included && !$0.item.lookupName.isEmpty }.map(\.item)
    }

    var primaryTitle: String {
        if working { return "Reading ingredients…" }
        if replacing != nil { return review == nil ? "Rescan this item" : "Save correction" }
        if review != nil { return "Save to pantry (\(selectedItems.count))" }
        if photos.isEmpty { return "Find ingredients" }
        return photos.count == 1 ? "Find ingredients in 1 photo" : "Find ingredients in \(photos.count) photos"
    }

    func save() -> Bool {
        guard let review, !selectedItems.isEmpty else { return false }
        do {
            try repository.save(review, photos: photos, replacing: replacing?.persistentModelID,
                                originalPhotoID: originalPhotoID)
            icons.start()
            return true
        } catch {
            message = "Could not save your pantry. \(error.localizedDescription)"
            return false
        }
    }

    func process() {
        guard !working, !importing, review == nil, !photos.isEmpty else { return }
        message = nil
        working = true
        scanTask = Task {
            defer { working = false }
            do {
                let items: [ScannedIngredient]
                if replacing != nil, let photo = photos.first {
                    items = try await scanner.recognize(photo, at: focus)
                } else {
                    items = try await scanner.recognize(photos.map(\.jpeg))
                }
                try Task.checkCancellation()
                if items.isEmpty {
                    message = "No ingredients were clear enough to identify. Try a closer photo of the labels."
                } else {
                    review = items.map { ReviewedIngredient(item: $0, detectedName: $0.name) }
                }
            } catch {
                if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }
}
