import MapKit
import SwiftUI

@Observable final class DishMapViewModel {
    var camera: MapCameraPosition = .region(Dish.valley)
    private(set) var selectedDish: Dish?

    func select(_ dish: Dish) {
        selectedDish = dish
        camera = .region(MKCoordinateRegion(
            center: dish.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.085, longitudeDelta: 0.085)
        ))
    }

    func showValley() {
        selectedDish = nil
        camera = .region(Dish.valley)
    }
}
