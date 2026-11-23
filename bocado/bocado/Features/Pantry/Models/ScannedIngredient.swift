import Foundation

nonisolated struct ScannedIngredient: Codable {
    var name: String
    var quantity: String
    var area: PantryArea
    var emoji: String

    var photoIndex = 0
    var x: Double
    var y: Double

    // The app associates the result with the submitted photo.
    enum CodingKeys: String, CodingKey { case name, quantity, area, emoji, x, y }

    var lookupName: String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
