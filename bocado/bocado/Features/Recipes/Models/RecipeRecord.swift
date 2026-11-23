import Foundation

nonisolated struct PantryFood: Codable, Equatable {
    let name: String
    let quantity: String
    let useSoon: Bool
}

nonisolated struct RecipeIdea: Codable {
    let name: String
    let summary: String
    let minutes: Int
    var pantryNames: [String]
    var extras: [String]
}

nonisolated struct RecipeMethod: Codable {
    let amounts: [String]
    let steps: [String]
}

nonisolated struct RecipeRecord: Codable {
    let id: UUID
    let idea: RecipeIdea
    let foods: [PantryFood]
    var photo: Data?
    var method: RecipeMethod?
}
