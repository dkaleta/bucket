import ImageIO
import SwiftData
import SwiftUI

struct RecipeCarousel: View {
    let width: CGFloat
    @Binding var recipeID: RecipeDetailViewModel.ID?
    let isActive: Bool
    let openPantry: () -> Void
    let openRecipe: (RecipeDetailViewModel) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @Query(sort: \PantryIngredient.lookupName) private var ingredients: [PantryIngredient]
    let shelf: RecipesViewModel

    private var foods: [PantryFood] {
        ingredients.map { PantryFood(name: $0.name, quantity: $0.quantity, useSoon: $0.useSoon) }
    }

    private var recipes: [RecipeDetailViewModel] { foods == shelf.pantry ? shelf.recipes : [] }
    private let inset: CGFloat = 24

    private var currentIndex: Int {
        recipes.firstIndex { $0.id == recipeID } ?? 0
    }

    private var cardWidth: CGFloat {
        max(1, min(610, width - (typeSize.isAccessibilitySize ? 2 * inset : 65)))
    }

    private var photoHeight: CGFloat {
        min(360, cardWidth * 0.69)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                KitchenHeading(
                    title: Text("What’s \(Text("cooking?").italic())"),
                    subtitle: "Ideas from your pantry, with up to two extras per dish."
                )
                .padding(.horizontal, inset)
                .padding(.bottom, 24)

                if foods.isEmpty {
                    ContentUnavailableView {
                        Label("Start with your pantry", systemImage: "basket")
                    } description: {
                        Text("Add your ingredients to get three recipe ideas.")
                    } actions: {
                        Button("Open pantry", action: openPantry).buttonStyle(.bordered)
                    }
                } else {
                    if shelf.loading || (recipes.isEmpty && shelf.error == nil) {
                        ProgressView("Finding three dishes…").padding()
                    }
                    if let error = shelf.error {
                        VStack(spacing: 8) {
                            Text(error).multilineTextAlignment(.center)
                            Button("Try again") { shelf.load(foods, refresh: true) }
                        }.padding()
                    }
                    if !recipes.isEmpty {
                        cards
                        Button {
                            shelf.load(foods, refresh: true)
                        } label: {
                            Label("New ideas", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(shelf.loading)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 12)
            .frame(width: width)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.top)
        .task(id: isActive ? foods : nil) {
            if isActive { shelf.load(foods) }
        }
        .onChange(of: recipes.map(\.id)) {
            if !recipes.contains(where: { $0.id == recipeID }) { recipeID = recipes.first?.id }
        }
    }

    private var cards: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(recipes) { recipe in
                        RecipeCard(recipe: recipe, photoHeight: photoHeight) {
                            openRecipe(recipe)
                        }
                        .frame(width: cardWidth)
                        .id(recipe.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.leading, inset, for: .scrollContent)
            .contentMargins(.trailing, width - cardWidth - inset, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $recipeID, anchor: .leading)
            .accessibilityIdentifier("recipe-carousel")

            pagination
                .frame(width: cardWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, inset)
                .padding(.top, 10)
        }
    }

    private var pagination: some View {
        HStack {
            pageButton("Previous recipe", symbol: "arrow.left", offset: -1)
            Spacer()
            HStack(spacing: 5) {
                ForEach(recipes.indices, id: \.self) { index in
                    Capsule()
                        .fill(currentIndex == index ? KitchenTheme.ink : KitchenTheme.line)
                        .frame(width: currentIndex == index ? 20 : 6, height: 6)
                }
            }
            .accessibilityRepresentation {
                Text("Recipe \(currentIndex + 1) of \(recipes.count)")
            }
            Spacer()
            pageButton("Next recipe", symbol: "arrow.right", offset: 1)
        }
    }

    private func pageButton(_ label: String, symbol: String, offset: Int) -> some View {
        let target = currentIndex + offset
        let enabled = recipes.indices.contains(target)
        return Button {
            guard recipes.indices.contains(target) else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                recipeID = recipes[target].id
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? KitchenTheme.ink : KitchenTheme.muted.opacity(0.5))
                .frame(width: 34, height: 34)
                .background(KitchenTheme.cream, in: Circle())
                .overlay(Circle().strokeBorder(KitchenTheme.line))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

private struct RecipeCard: View {
    let recipe: RecipeDetailViewModel
    let photoHeight: CGFloat
    let open: () -> Void

    @ScaledMetric(relativeTo: .title) private var titleSize = 31

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                RecipePhoto(recipe: recipe, height: photoHeight)
                    .overlay(alignment: .topLeading) {
                        Label("\(recipe.minutes) min", systemImage: "clock")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(KitchenTheme.cream, in: Capsule())
                            .padding(14)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.name)
                        .font(.system(size: titleSize, weight: .medium, design: .serif))
                        .tracking(-0.85)
                        .accessibilityAddTraits(.isHeader)
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(KitchenTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("From pantry: " + recipe.record.foods.map(\.name).joined(separator: ", "), systemImage: "basket")
                        .font(.footnote)
                    Label(recipe.record.idea.extras.isEmpty ? "Everything is in your pantry"
                          : "To add: " + recipe.record.idea.extras.joined(separator: ", "),
                          systemImage: recipe.record.idea.extras.isEmpty ? "checkmark.circle" : "cart")
                        .font(.footnote.weight(.semibold))
                    HStack {
                        Text("View recipe").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .padding(.horizontal, 15)
                    .frame(minHeight: 44)
                    .foregroundStyle(KitchenTheme.cream)
                    .background(KitchenTheme.ink, in: .rect(cornerRadius: 12))
                    .padding(.top, 8)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(KitchenTheme.cream, in: .rect(cornerRadius: 23))
            .clipShape(.rect(cornerRadius: 23))
            .overlay {
                RoundedRectangle(cornerRadius: 23)
                    .strokeBorder(KitchenTheme.line)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recipe-idea-card")
        .accessibilityHint("Open the full recipe")
        .overlay(alignment: .topTrailing) {
            if recipe.photoError != nil {
                Button("Retry photo") { Task { await recipe.loadPhoto() } }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .padding(14)
            }
        }
    }
}

struct RecipePhoto: View {
    let recipe: RecipeDetailViewModel
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(KitchenTheme.sage)
            .frame(height: height)
            .overlay {
                if let data = recipe.record.photo,
                   let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else if recipe.photoError == nil {
                    ProgressView("Preparing photo…")
                } else {
                    Label("Photo unavailable", systemImage: "photo")
                }
            }
            .clipped()
    }
}
