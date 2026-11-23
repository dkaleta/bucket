import FactoryKit
import Foundation
import SwiftData
import XCTest
@testable import bocado

@MainActor
final class FeatureTests: XCTestCase {
    private func makeContainer() throws -> AppContainer {
        let storage = try ModelContainer(for: PantryIngredient.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let container = AppContainer(storage: storage)
        container.images.register { TestImages() }
        return container
    }

    func testFeatureLifetimes() throws {
        let first = try makeContainer()
        let other = try makeContainer()
        XCTAssertTrue(first.pantryIcons() === first.pantryViewModel().icons)
        XCTAssertFalse(first.pantryViewModel() === first.pantryViewModel())
        XCTAssertFalse(first.scanViewModel(nil) === first.scanViewModel(nil))
        XCTAssertFalse(first.pantryIcons() === other.pantryIcons())
    }

    func testScanReviewCorrectionAndSourceLifetime() async throws {
        let container = try makeContainer()
        container.scanner.register { TestScanner() }
        let scan = container.scanViewModel(nil)
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aV1sAAAAASUVORK5CYII="))
        await scan.importPhotos([png]) { $0 }
        let photo = try XCTUnwrap(scan.photos.first)
        scan.process()
        try await waitUntil { !scan.working }
        XCTAssertEqual(scan.review?.count, 2)
        let context = container.storage.mainContext
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PantryIngredient>()), 0)

        scan.review?[1].item.name = "Thyme"
        XCTAssertFalse(scan.save(), "A duplicate review must leave the store untouched")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PantrySourcePhoto>()), 0)
        scan.review?[1].item.name = "Oregano"
        XCTAssertTrue(scan.save())
        let rows = try context.fetch(FetchDescriptor<PantryIngredient>())
        let oregano = try XCTUnwrap(rows.first { $0.name == "Oregano" })
        let thyme = try XCTUnwrap(rows.first { $0.name == "Thyme" })
        XCTAssertEqual(oregano.sourcePhoto?.persistentModelID, thyme.sourcePhoto?.persistentModelID)

        let correction = container.scanViewModel(oregano)
        await correction.loadSource()
        correction.process()
        try await waitUntil { !correction.working }
        XCTAssertEqual(correction.review?.first?.detectedName, "Marjoram")
        XCTAssertTrue(correction.save())
        let reader = ModelContext(container.storage)
        let corrected = try XCTUnwrap(reader.fetch(FetchDescriptor<PantryIngredient>()).first { $0.name == "Marjoram" })
        XCTAssertEqual(corrected.persistentModelID, oregano.persistentModelID)
        XCTAssertEqual(corrected.sourcePhoto?.jpeg, photo.jpeg)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<PantrySourcePhoto>()), 1)

        let pantry = container.pantryViewModel()
        pantry.toggleUseSoon(thyme, in: rows)
        pantry.filter = .useSoon
        pantry.searchText = " thyme "
        XCTAssertEqual(pantry.filteredIngredients(rows).map(\.name), ["Thyme"])
        pantry.remove(thyme)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PantrySourcePhoto>()), 1)
        pantry.remove(oregano)
        XCTAssertNil(pantry.error)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PantrySourcePhoto>()), 0)
    }

    func testRecipesGenerateDetailsOnDemandAndRestoreCache() async throws {
        let container = try makeContainer()
        let generator = TestRecipes()
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        container.recipeCache.register { RecipeCache(url: url) }
        container.recipeGenerator.register { generator }
        let menu = container.recipesViewModel()
        let foods = [PantryFood(name: "Rice", quantity: "1 cup", useSoon: true)]
        menu.load(foods)
        try await waitUntil { menu.recipes.count == 3 && menu.recipes.allSatisfy { $0.record.photo != nil } }
        XCTAssertTrue(menu.recipes.allSatisfy { $0.record.method == nil })
        let first = try XCTUnwrap(menu.recipes.first)
        await first.loadMethod()
        await first.loadMethod()
        let requests = await generator.methodRequests
        XCTAssertEqual(requests, 1)
        let restored = RecipesViewModel(generator: generator, images: TestImages(), cache: RecipeCache(url: url))
        XCTAssertEqual(restored.pantry, foods)
        XCTAssertEqual(restored.recipes.first?.id, first.id)
        XCTAssertEqual(restored.recipes.first?.record.method?.steps, ["Cook the rice."])
        XCTAssertNil(restored.recipes.last?.record.method)
    }

    private func waitUntil(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !ready() {
            guard ContinuousClock.now < deadline else { throw KitchenError("Timed out waiting for the view model.") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct TestScanner: PantryRecognizing {
    func recognize(_ photos: [Data]) async throws -> [ScannedIngredient] {
        ["Thyme", "Oregano"].map(ingredient)
    }

    func recognize(_ photo: ScanPhoto, at point: CGPoint) async throws -> [ScannedIngredient] {
        [ingredient("Marjoram")]
    }

    private func ingredient(_ name: String) -> ScannedIngredient {
        ScannedIngredient(name: name, quantity: "", area: .cupboard, emoji: "🌿", x: 0.5, y: 0.5)
    }
}

private struct TestImages: ImageGenerating {
    func generate(prompt: String, transparent: Bool, maxPixels: Int) async throws -> Data { Data([1]) }
}

private actor TestRecipes: RecipeGenerating {
    private(set) var methodRequests = 0

    func ideas(for foods: [PantryFood], previous: [String]) async throws -> [RecipeIdea] {
        ["Rice bowl", "Rice soup", "Rice cakes"].map {
            RecipeIdea(name: $0, summary: "Made with rice", minutes: 20, pantryNames: ["Rice"], extras: [])
        }
    }

    func method(for recipe: RecipeRecord) async throws -> RecipeMethod {
        methodRequests += 1
        return RecipeMethod(amounts: ["1 cup"], steps: ["Cook the rice."])
    }
}
