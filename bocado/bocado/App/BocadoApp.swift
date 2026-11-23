import SwiftData
import SwiftUI

@main
struct BocadoApp: App {
    private let dependencies = Result {
        AppContainer(storage: try ModelContainer(for: PantryIngredient.self))
    }

    var body: some Scene {
        WindowGroup {
            switch dependencies {
            case .success(let container):
                KitchenRootView(dependencies: container)
                    .modelContainer(container.storage)
            case .failure(let error):
                ContentUnavailableView("Couldn’t open your pantry", systemImage: "basket",
                                       description: Text(error.localizedDescription))
            }
        }
    }
}
