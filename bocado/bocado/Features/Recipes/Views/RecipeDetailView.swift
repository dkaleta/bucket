import SwiftUI

struct RecipeDetailView: View {
    let recipe: RecipeDetailViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RecipePhoto(recipe: recipe, height: 230)
                    .clipShape(.rect(cornerRadius: 20))

                KitchenHeading(title: Text(recipe.name), subtitle: recipe.summary)

                HStack(spacing: 18) {
                    Label("\(recipe.minutes) min", systemImage: "clock")
                    Label("2 servings", systemImage: "person.2")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(KitchenTheme.muted)

                if let method = recipe.record.method {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionTitle("Ingredients")
                            .padding(.bottom, 8)
                        let names = recipe.record.foods.map(\.name) + recipe.record.idea.extras
                        ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                            let onHand = index < recipe.record.foods.count
                            Label("\(method.amounts[index]) \(name)\(onHand ? "" : " · to buy")",
                                  systemImage: onHand ? "checkmark.circle" : "cart")
                                .font(.body)
                                .padding(.vertical, 6)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Method")
                        ForEach(Array(method.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(index + 1).")
                                    .font(.body.weight(.semibold))
                                Text(step)
                                    .font(.body)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                } else if let error = recipe.methodError {
                    Text(error)
                    Button("Retry recipe") { Task { await recipe.loadMethod() } }
                } else {
                    ProgressView("Writing your recipe…").padding(.vertical)
                }
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .onAppear { Task { await recipe.loadMethod() } }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(KitchenTheme.paper)
        }
        .foregroundStyle(KitchenTheme.ink)
        .background(KitchenTheme.paper.ignoresSafeArea())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.title2, design: .serif, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }
}
