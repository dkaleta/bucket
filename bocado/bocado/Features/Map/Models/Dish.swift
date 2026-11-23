import MapKit
import SwiftUI

struct Dish: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let category: String
    let village: String
    let description: String
    let symbol: String
    let color: Color
    let coordinate: CLLocationCoordinate2D

    static let valley = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.259, longitude: 11.866),
        span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.20)
    )

    // Representative village coordinates, not restaurants or verified serving locations.
    // Dish reference: https://www.zillertal.at/en/winter/fine-food-drink/recipes.html
    static let samples: [Dish] = [
        Dish(
            id: "krapfen", name: "Zillertaler Krapfen", shortName: "Krapfen",
            category: "Valley classic", village: "Fügen",
            description: "Crisp, golden pastries with a hearty potato and Graukäse filling. A little taste of Zillertal tradition.",
            symbol: "fork.knife", color: Color(red: 0.72, green: 0.35, blue: 0.20),
            coordinate: CLLocationCoordinate2D(latitude: 47.3458, longitude: 11.8490)
        ),
        Dish(
            id: "pressknoedel", name: "Pressknödel", shortName: "Pressknödel",
            category: "Alpine comfort", village: "Zell am Ziller",
            description: "Pan-fried cheese dumplings with a golden crust, often served in a warming bowl of broth.",
            symbol: "carrot", color: Color(red: 0.29, green: 0.43, blue: 0.31),
            coordinate: CLLocationCoordinate2D(latitude: 47.2333, longitude: 11.8817)
        ),
        Dish(
            id: "melchermuas", name: "Melchermuas", shortName: "Melchermuas",
            category: "Mountain tradition", village: "Mayrhofen",
            description: "A rustic pan-cooked dish of flour, milk and butter, traditionally enjoyed on the alpine pastures. Simple, rich and comforting.",
            symbol: "frying.pan", color: Color(red: 0.63, green: 0.43, blue: 0.19),
            coordinate: CLLocationCoordinate2D(latitude: 47.1661, longitude: 11.8628)
        )
    ]
}
