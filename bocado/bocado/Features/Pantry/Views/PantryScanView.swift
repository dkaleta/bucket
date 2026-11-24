import AVFoundation
import FactoryKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PantryScanView: View {
    @State var model: PantryScanViewModel
    /// Pushed onto an existing navigation stack instead of presented as a sheet.
    var embedded = false
    let didSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showFiles = false

    var body: some View {
        Group {
            if embedded {
                screen
                    #if os(iOS)
                    .toolbarVisibility(.hidden, for: .tabBar)
                    #endif
            } else {
                NavigationStack { screen }
                    #if os(macOS)
                    .frame(minWidth: 460, idealWidth: 560, minHeight: 520, idealHeight: 640)
                    #endif
            }
        }
        .foregroundStyle(KitchenTheme.text)
        .tint(KitchenTheme.accent)
        .task { await model.loadSource() }
        .onDisappear { model.cancel() }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await model.importPhotos(items) { item in
                    guard let bytes = try await item.loadTransferable(type: Data.self) else {
                        throw KitchenError("A selected photo could not be opened.")
                    }
                    return bytes
                }
                selection = []
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            PantryCamera { bytes in
                showCamera = false
                if let bytes { addPhoto(bytes) }
            }.ignoresSafeArea()
        }
        #elseif os(macOS)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: model.replacing == nil) { result in
            guard case let .success(urls) = result else { return }
            Task { await model.importPhotos(urls, read: Self.readFile) }
        }
        #endif
    }

    private var title: String {
        if model.review != nil { return "Review ingredients" }
        return model.replacing == nil ? "Scan your kitchen" : "Rescan"
    }

    private var subtitle: String {
        model.review == nil ? model.replacing?.name ?? "" : ""
    }

    private var primaryDisabled: Bool {
        model.working || model.importing || (model.review == nil ? model.photos.isEmpty : model.selectedItems.isEmpty)
    }

    private var screen: some View {
        // While working the button stays accent-coloured so the progress label reads as active.
        let inactive = primaryDisabled && !model.working
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.review == nil {
                    collection
                } else {
                    reviewForm
                }
                if let message = model.message {
                    Text(message)
                        .font(.callout)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KitchenTheme.fill, in: .rect(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(KitchenTheme.surface)
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                        dismiss()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: primaryAction) {
                    HStack(spacing: 8) {
                        if model.working { ProgressView().controlSize(.small).tint(.white) }
                        Text(model.primaryTitle)
                    }
                    .font(.headline)
                    .foregroundStyle(inactive ? KitchenTheme.secondary : .white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(inactive ? KitchenTheme.fill : KitchenTheme.accent, in: .rect(cornerRadius: 16))
                    .contentShape(.rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(primaryDisabled)
                if model.review == nil {
                    Text(model.replacing == nil ? "Photos are sent to OpenAI to read your ingredients."
                         : "A close-up around the marker is sent to OpenAI.")
                        .font(.caption2)
                        .foregroundStyle(KitchenTheme.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(KitchenTheme.surface)
        }
    }

    private var busy: Bool { model.working || model.importing }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let replacing = model.replacing, let photo = model.photos.first {
                IngredientSourceImage(image: photo.preview, point: model.focus,
                    name: model.movedMarker ? "Rescan here" : replacing.detectedName ?? replacing.name) { point in
                    model.focus = point
                    model.movedMarker = true
                }
                .allowsHitTesting(!busy)
                .overlay(alignment: .bottom) {
                    if !model.working {
                        Text("Tap the photo to move the marker")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.bottom, 12)
                            .allowsHitTesting(false)
                    }
                }
                .overlay { if model.working { ScanSweep() } }
                .clipShape(.rect(cornerRadius: 24))
                sourceButtons(includeCamera: true)
            } else if model.photos.isEmpty {
                viewfinder
                sourceButtons(includeCamera: false)
            } else {
                HStack {
                    Text("\(model.photos.count) of \(model.limit) photos")
                        .font(.title3.weight(.semibold))
                    if model.importing { ProgressView().controlSize(.small) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(model.photos) { photo in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                            .overlay {
                                Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                            }
                            .overlay { if model.working { ScanSweep() } }
                            .clipped()
                            .clipShape(.rect(cornerRadius: 16))
                            .overlay(alignment: .topTrailing) {
                                Button { model.removePhoto(photo) } label: {
                                    Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                        .font(.title3)
                                        .foregroundStyle(.white, .black.opacity(0.7)).padding(8)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove photo \((model.photos.firstIndex { $0.id == photo.id } ?? 0) + 1)")
                                .disabled(busy)
                            }
                    }
                }
                sourceButtons(includeCamera: true)
            }
        }
    }

    /// The empty state doubles as the camera button: one large target that says what to do.
    @ViewBuilder private var viewfinder: some View {
        let card = VStack(spacing: 14) {
            ZStack {
                Circle().fill(KitchenTheme.accent).frame(width: 84, height: 84)
                if model.importing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.breathe)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(model.replacing == nil ? "Snap a shelf" : "Snap it again")
                    .font(.title.weight(.bold))
                Text(model.replacing == nil ? "One shelf at a time, labels facing you."
                     : "Get close so the label is easy to read.")
                    .font(.subheadline)
                    .foregroundStyle(KitchenTheme.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(KitchenTheme.fill, in: .rect(cornerRadius: 28))
        .overlay {
            ViewfinderCorners()
                .stroke(KitchenTheme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        }
        .contentShape(.rect(cornerRadius: 28))

        #if os(iOS) || os(macOS)
        Button { Task { await openCamera() } } label: { card }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityHint("Opens the camera")
        #else
        card
        #endif
    }

    private func sourceButtons(includeCamera: Bool) -> some View {
        HStack(spacing: 10) {
            #if os(iOS) || os(macOS)
            if includeCamera {
                Button { Task { await openCamera() } } label: {
                    Label(model.replacing == nil ? "Add photo" : "Retake", systemImage: "camera")
                }
            }
            #endif
            PhotosPicker(selection: $selection, maxSelectionCount: max(1, model.available),
                         selectionBehavior: .ordered, matching: .images) {
                Label(includeCamera ? "Library" : "Choose from library", systemImage: "photo.on.rectangle")
            }
            #if os(macOS)
            Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
            #endif
        }
        .buttonStyle(WideOutlineStyle())
        .disabled(model.available == 0 || busy)
    }

    private var reviewForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Back to photos", systemImage: "chevron.left") { model.review = nil; model.message = nil }
                .font(.subheadline.weight(.semibold))
            Text(model.replacing == nil ? "Check each marked item before saving it to your pantry." : "Review the correction before updating this ingredient.")
                .font(.subheadline).foregroundStyle(KitchenTheme.secondary)
            if let rows = Binding($model.review) {
                ForEach(rows) { $row in
                    VStack(alignment: .leading, spacing: 12) {
                        IngredientSourceImage(image: model.photos[row.item.photoIndex].preview,
                            point: CGPoint(x: row.item.x, y: row.item.y), name: row.detectedName)
                        if model.replacing == nil {
                            Toggle("Include ingredient", isOn: $row.included)
                        }
                        TextField("Ingredient name", text: $row.item.name)
                        TextField("Quantity (optional)", text: $row.item.quantity)
                        Picker("Storage", selection: $row.item.area) {
                            ForEach(PantryArea.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(14)
                    .background(KitchenTheme.fill, in: .rect(cornerRadius: 18))
                }
            }
        }
    }

    private func primaryAction() {
        if model.review == nil {
            model.process()
        } else if model.save() {
            didSave()
            dismiss()
        }
    }

    #if os(iOS) || os(macOS)
    private func openCamera() async {
        #if os(iOS)
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            model.message = "This device has no available camera. Choose an image from Photos."
            return
        }
        #endif
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            model.message = "Allow camera access in Settings, or choose an existing photo."
            return
        }
        #if os(iOS)
        showCamera = true
        #else
        if let data = MacPantryCamera.capture() { addPhoto(data) }
        #endif
    }
    #endif

    private func addPhoto(_ data: Data) {
        Task { await model.importPhotos([data]) { $0 } }
    }

    #if os(macOS)
    @concurrent private static func readFile(_ url: URL) async throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
    #endif
}

struct WideOutlineStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(KitchenTheme.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(configuration.isPressed ? KitchenTheme.fill : .clear, in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(KitchenTheme.hairline, lineWidth: 1.5) }
            .contentShape(.rect(cornerRadius: 16))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Four corner brackets, like a camera viewfinder.
private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: 18, dy: 18)
        let leg: CGFloat = 30, radius: CGFloat = 14
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: box.minX, y: box.minY), 1, 1), (CGPoint(x: box.maxX, y: box.minY), -1, 1),
            (CGPoint(x: box.maxX, y: box.maxY), -1, -1), (CGPoint(x: box.minX, y: box.maxY), 1, -1)
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * leg))
            path.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x + dx * leg, y: corner.y), radius: radius)
            path.addLine(to: CGPoint(x: corner.x + dx * leg, y: corner.y))
        }
        return path
    }
}

/// A light bar sweeping over a photo while it is being read.
private struct ScanSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var atBottom = false

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(colors: [KitchenTheme.accent.opacity(0), KitchenTheme.accent.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 64)
                .overlay(alignment: .bottom) { Rectangle().fill(.white).frame(height: 2) }
                .offset(y: atBottom ? geometry.size.height - 64 : 0)
                .opacity(reduceMotion ? 0 : 1)
        }
        .background(.black.opacity(0.15))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { atBottom = true }
        }
    }
}

#Preview("Rescan") {
    let storage = try! ModelContainer(for: PantryIngredient.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ingredient = PantryIngredient(.init(name: "Spinach", quantity: "1 bag", area: .produce,
                                            emoji: "🥬", x: 0.5, y: 0.5))
    storage.mainContext.insert(ingredient)
    let container = AppContainer(storage: storage)
    container.openAI.register { OpenAIClient(session: .shared, apiKey: nil) }

    return NavigationStack {
        PantryScanView(model: container.scanViewModel(ingredient), embedded: true, didSave: {})
    }
    .modelContainer(storage)
    .preferredColorScheme(.light)
}

#Preview("Scan") {
    let storage = try! ModelContainer(for: PantryIngredient.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let container = AppContainer(storage: storage)
    container.openAI.register { OpenAIClient(session: .shared, apiKey: nil) }

    return PantryScanView(model: container.scanViewModel(nil), didSave: {})
        .modelContainer(storage)
        .preferredColorScheme(.light)
}
