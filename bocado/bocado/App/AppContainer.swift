import FactoryKit
import Foundation
import SwiftData

/// Each running app, preview, or test owns a dependency graph for one pantry.
@MainActor final class AppContainer: ManagedContainer {
    nonisolated let manager = ContainerManager()
    let storage: ModelContainer

    init(storage: ModelContainer) {
        self.storage = storage
    }

    var openAI: Factory<OpenAIClient> {
        self { OpenAIClient(session: .shared, apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]) }
    }

    var images: Factory<any ImageGenerating> {
        self { OpenAIImageGenerator(client: self.openAI()) }
    }

    var scanner: Factory<any PantryRecognizing> {
        self { PantryScanner(client: self.openAI()) }
    }

    var recipeGenerator: Factory<any RecipeGenerating> {
        self { RecipeGenerator(client: self.openAI()) }
    }

    var recipeCache: Factory<RecipeCache> {
        self { RecipeCache(url: URL.cachesDirectory.appending(path: "pantry-recipes-v1.json")) }
    }

    var pantryRepository: Factory<PantryRepository> {
        self { PantryRepository(container: self.storage) }
    }

    var pantryIcons: Factory<PantryIcons> {
        self { PantryIcons(container: self.storage, images: self.images()) }.cached
    }

    var recipesViewModel: Factory<RecipesViewModel> {
        self { RecipesViewModel(generator: self.recipeGenerator(), images: self.images(), cache: self.recipeCache()) }.cached
    }

    var pantryViewModel: Factory<PantryViewModel> {
        self { PantryViewModel(repository: self.pantryRepository(), icons: self.pantryIcons()) }
    }

    var scanViewModel: ParameterFactory<PantryIngredient?, PantryScanViewModel> {
        self { ingredient in
            PantryScanViewModel(replacing: ingredient, scanner: self.scanner(),
                                repository: self.pantryRepository(), icons: self.pantryIcons())
        }
    }
}
