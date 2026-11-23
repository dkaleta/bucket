import SwiftData
import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            KitchenPrototypeView()
        }
        .modelContainer(for: PantryIngredient.self)
    }
}
