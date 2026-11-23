import MapKit
import SwiftUI

struct DishMapView: View {
    @Bindable var state: DishMapViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ink = Color(red: 0.15, green: 0.24, blue: 0.20)

    var body: some View {
        Map(position: $state.camera) {
            ForEach(Dish.samples) { dish in
                Annotation(dish.name, coordinate: dish.coordinate, anchor: .bottom) {
                    Button {
                        select(dish)
                    } label: {
                        DishPin(dish: dish, isSelected: state.selectedDish?.id == dish.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(dish.name), near \(dish.village)")
                    .accessibilityHint("Show dish details")
                    .accessibilityIdentifier("dish-pin-\(dish.id)")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("bocado")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                    Label("ZILLERTAL · AUSTRIA", systemImage: "mountain.2")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(2)
                }
                Spacer()
                Button(action: showValley) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(0.8), in: Circle())
                }
                .accessibilityLabel("Show all three dishes")
                .accessibilityIdentifier("show-valley")
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.regularMaterial)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                if let dish = state.selectedDish {
                    detail(for: dish)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A taste of the valley")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Three local dishes. Tap a pin to discover one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(Dish.samples) { dish in
                        Button {
                            select(dish)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: dish.symbol)
                                    .font(.system(size: 19))
                                Text(dish.shortName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(state.selectedDish?.id == dish.id ? .white : ink)
                            .background(state.selectedDish?.id == dish.id ? ink : ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Explore \(dish.name)")
                        .accessibilityAddTraits(state.selectedDish?.id == dish.id ? [.isSelected] : [])
                    }
                }
            }
            .foregroundStyle(ink)
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .background(Color(red: 0.99, green: 0.98, blue: 0.95), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.8)))
            .shadow(color: .black.opacity(0.1), radius: 20, y: 5)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .preferredColorScheme(.light)
    }

    private func detail(for dish: Dish) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(dish.category.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(dish.color)
                    Text(dish.name)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
                Button(action: showValley) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(ink.opacity(0.06), in: Circle())
                }
                .accessibilityLabel("Close dish details")
            }
            Text(dish.description)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Label("Near \(dish.village) · illustrative location", systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("dish-details-\(dish.id)")
    }

    private func select(_ dish: Dish) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            state.select(dish)
        }
    }

    private func showValley() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            state.showValley()
        }
    }
}

private struct DishPin: View {
    let dish: Dish
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: dish.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(dish.color, in: Circle())
                Text(dish.shortName)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.24, blue: 0.20))
                    .padding(.trailing, 9)
            }
            .padding(5)
            .background(.white, in: Capsule())
            .overlay(Capsule().strokeBorder(dish.color, lineWidth: isSelected ? 3 : 0))
            Image(systemName: "triangle.fill")
                .font(.system(size: 12))
                .rotationEffect(.degrees(180))
                .foregroundStyle(.white)
                .offset(y: -3)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .padding(.top, 4)
    }
}

#Preview {
    DishMapView(state: DishMapViewModel())
}
