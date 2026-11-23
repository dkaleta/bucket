import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PantryScanView: View {
    @State var model: PantryScanViewModel
    let didSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showFiles = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.review == nil {
                        collection
                    } else {
                        reviewForm
                    }
                    if let message = model.message {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(KitchenTheme.ink)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(KitchenTheme.butter, in: .rect(cornerRadius: 12))
                    }
                }
                .padding(22)
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(KitchenTheme.paper)
            .navigationTitle(model.review == nil ? (model.replacing == nil ? "Scan your kitchen" : "Ingredient source") : "Review ingredients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.replacing != nil && model.review == nil && !model.working ? "Done" : "Cancel") {
                        model.cancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: primaryAction) {
                    HStack {
                        if model.working { ProgressView().controlSize(.small) }
                        Text(model.primaryTitle)
                    }
                    .foregroundStyle(KitchenTheme.cream)
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.working || model.importing || (model.review == nil ? model.photos.isEmpty : model.selectedItems.isEmpty))
                .padding()
                .background(KitchenTheme.paper)
            }
        }
        .tint(KitchenTheme.ink)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 520, idealHeight: 640)
        #endif
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

    private var collection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let replacing = model.replacing {
                Text(replacing.name).font(.title2.bold())
                if let photo = model.photos.first {
                    IngredientSourceImage(image: photo.preview, point: model.focus,
                        name: model.movedMarker ? "Rescan here" : replacing.detectedName ?? replacing.name) { point in
                        model.focus = point
                        model.movedMarker = true
                    }
                    .allowsHitTesting(!model.working && !model.importing)
                    Text("Tap the item to position the marker, or choose a closer photo.")
                        .foregroundStyle(KitchenTheme.muted)
                } else if !model.importing {
                    Text("No source photo is available. Add a photo to rescan this ingredient.")
                        .foregroundStyle(KitchenTheme.muted)
                }
            } else {
                Text("Photograph one shelf at a time. For spices, turn the labels toward the camera.")
                    .foregroundStyle(KitchenTheme.muted)
            }
            HStack {
                #if os(iOS) || os(macOS)
                Button { Task { await openCamera() } } label: { Label("Camera", systemImage: "camera") }
                #endif
                PhotosPicker(selection: $selection, maxSelectionCount: max(1, model.available),
                             selectionBehavior: .ordered, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                #if os(macOS)
                Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
                #endif
            }
            .buttonStyle(.bordered)
            .disabled(model.available == 0 || model.working || model.importing)
            if model.replacing == nil {
                HStack {
                    Text("\(model.photos.count) of \(model.limit) photos").font(.subheadline.weight(.semibold))
                    if model.importing { ProgressView().controlSize(.small) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(model.photos) { photo in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                            .overlay {
                                Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                            }
                            .clipped()
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay(alignment: .topTrailing) {
                                Button { model.removePhoto(photo) } label: {
                                    Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.7)).padding(10)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove photo \((model.photos.firstIndex { $0.id == photo.id } ?? 0) + 1)")
                                .disabled(model.working || model.importing)
                            }
                    }
                }
            }
            Text(model.replacing == nil ? "Processing sends these photos to OpenAI. You can review the results before saving."
                 : "Rescanning sends a close-up around the marker to OpenAI.")
                .font(.footnote).foregroundStyle(KitchenTheme.muted)
        }
    }

    private var reviewForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Back to photos") { model.review = nil; model.message = nil }
            Text(model.replacing == nil ? "Check each marked item before saving it to your pantry." : "Review the correction before updating this ingredient.")
                .font(.subheadline).foregroundStyle(KitchenTheme.muted)
            if let rows = Binding($model.review) {
                ForEach(rows) { $row in
                    VStack(alignment: .leading, spacing: 10) {
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
                    .padding()
                    .background(KitchenTheme.cream, in: .rect(cornerRadius: 14))
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
