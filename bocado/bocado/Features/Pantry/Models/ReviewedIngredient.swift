import Foundation

struct ReviewedIngredient: Identifiable {
    let id = UUID()
    var included = true
    var item: ScannedIngredient
    let detectedName: String
}
