import FactoryKit
import ImageIO
import SwiftData
import SwiftUI

struct IngredientDetailView: View {
    let ingredient: PantryIngredient
    @Bindable var model: PantryViewModel
    let makeScan: (PantryIngredient?) -> PantryScanViewModel

    @Query private var ingredients: [PantryIngredient]
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editingQuantity: Bool
    @State private var quantity = ""
    @State private var source: CGImage?
    @State private var rescanning = false
    @State private var confirmingRemoval = false
    @State private var removing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                icon
                details
                photo
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(KitchenTheme.surface)
        .navigationTitle(ingredient.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Remove from pantry", systemImage: "trash", role: .destructive) {
                    confirmingRemoval = true
                }
            }
        }
        .navigationDestination(isPresented: $rescanning) {
            PantryScanView(model: makeScan(ingredient), embedded: true, didSave: model.resetFilters)
        }
        .confirmationDialog("Remove \(ingredient.name) from your pantry?", isPresented: $confirmingRemoval,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                removing = true
                dismiss()
            }
        }
        // Delete only once the screen is gone, so nothing still on screen reads a deleted model.
        .onDisappear {
            if removing { model.remove(ingredient) }
        }
        .onAppear { quantity = ingredient.quantity }
        .onChange(of: ingredient.quantity) { _, saved in
            if !editingQuantity { quantity = saved }
        }
        .onChange(of: editingQuantity) { _, editing in
            if !editing { saveQuantity() }
        }
        .task(id: ingredient.sourcePhoto?.persistentModelID) {
            guard let jpeg = ingredient.sourcePhoto?.jpeg else { return source = nil }
            source = try? await ScanPhoto.loadSaved(jpeg).preview
        }
    }

    private var icon: some View {
        Group {
            if let png = ingredient.iconPNG,
               let data = CGImageSourceCreateWithData(png as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(data, 0, nil) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
            } else {
                Text(ingredient.emoji).font(.system(size: 56))
            }
        }
        .frame(width: 120, height: 120)
        .background(KitchenTheme.fill, in: .rect(cornerRadius: 28))
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(spacing: 0) {
            row("Quantity") {
                TextField("Quantity", text: $quantity,
                          prompt: Text("Add").foregroundStyle(KitchenTheme.accent))
                    .multilineTextAlignment(.trailing)
                    .focused($editingQuantity)
                    .submitLabel(.done)
                    .onSubmit { editingQuantity = false }
            }
            divider
            row("Stored in") {
                Picker("Stored in", selection: Binding(
                    get: { ingredient.area },
                    set: { model.update(ingredient, quantity: quantity, area: $0) }
                )) {
                    ForEach(PantryArea.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .tint(KitchenTheme.text)
            }
            divider
            row("Use soon") {
                Toggle("Use soon", isOn: Binding(
                    get: { ingredient.useSoon },
                    set: { _ in model.toggleUseSoon(ingredient, in: ingredients) }
                ))
                .labelsHidden()
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(KitchenTheme.hairline).frame(height: 1)
    }

    private func row(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(KitchenTheme.secondary)
            Spacer(minLength: 8)
            value()
        }
        .frame(minHeight: 52)
    }

    @ViewBuilder private var photo: some View {
        if let source {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where we found it")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                IngredientSourceImage(image: source,
                                      point: CGPoint(x: ingredient.sourceX ?? 0.5, y: ingredient.sourceY ?? 0.5),
                                      name: ingredient.detectedName ?? ingredient.name)
                    .clipShape(.rect(cornerRadius: 20))
                Button { rescanning = true } label: {
                    Label("Wrong item? Rescan", systemImage: "arrow.trianglehead.2.clockwise")
                }
                .buttonStyle(WideOutlineStyle())
            }
        } else if ingredient.sourcePhoto == nil {
            // A missing photo is fixable, but it is not what this screen is about.
            Button { rescanning = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "camera")
                        .font(.body.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(KitchenTheme.fill, in: .rect(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add a photo").font(.body.weight(.medium))
                        Text("Scan it to check the name and details")
                            .font(.subheadline)
                            .foregroundStyle(KitchenTheme.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KitchenTheme.secondary.opacity(0.55))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func saveQuantity() {
        guard quantity.trimmingCharacters(in: .whitespacesAndNewlines) != ingredient.quantity else { return }
        model.update(ingredient, quantity: quantity, area: ingredient.area)
    }
}

#Preview("Ingredient") {
    let storage = try! ModelContainer(for: PantryIngredient.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ingredient = PantryIngredient(.init(name: "Spinach", quantity: "", area: .produce,
                                            emoji: "🥬", x: 0.5, y: 0.5))
    storage.mainContext.insert(ingredient)
    let container = AppContainer(storage: storage)
    container.openAI.register { OpenAIClient(session: .shared, apiKey: nil) }

    return NavigationStack {
        IngredientDetailView(ingredient: ingredient, model: container.pantryViewModel(),
                             makeScan: { container.scanViewModel($0) })
    }
    .modelContainer(storage)
    .foregroundStyle(KitchenTheme.text)
    .tint(KitchenTheme.accent)
    .preferredColorScheme(.light)
}
