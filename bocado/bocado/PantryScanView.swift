import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PantryScanView: View {
    var replacing: PantryIngredient? = nil
    let didSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var photos: [ScanPhoto] = []
    @State private var selection: [PhotosPickerItem] = []
    @State private var review: [ReviewItem]?
    @State private var message: String?
    @State private var working = false
    @State private var importing = false
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var scanTask: Task<Void, Never>?

    @State private var focus = CGPoint(x: 0.5, y: 0.5)
    @State private var originalPhotoID: UUID?
    @State private var movedMarker = false

    private var limit: Int { replacing == nil ? 8 : 1 }
    private var available: Int { replacing == nil ? max(0, limit - photos.count) : 1 }

    private func accept(_ photo: ScanPhoto) {
        if replacing != nil {
            photos = [photo]
            focus = CGPoint(x: 0.5, y: 0.5)
            movedMarker = true
        } else if photos.count < limit {
            photos.append(photo)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if review == nil {
                        collection
                    } else {
                        reviewForm
                    }
                    if let message {
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
            .navigationTitle(review == nil ? (replacing == nil ? "Scan your kitchen" : "Ingredient source") : "Review ingredients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(replacing != nil && review == nil && !working ? "Done" : "Cancel") {
                        scanTask?.cancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: primaryAction) {
                    HStack {
                        if working { ProgressView().controlSize(.small) }
                        Text(primaryTitle)
                    }
                    .foregroundStyle(KitchenTheme.cream)
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                .disabled(working || importing || (review == nil ? photos.isEmpty : selectedItems.isEmpty))
                .padding()
                .background(KitchenTheme.paper)
            }
        }
        .tint(KitchenTheme.ink)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 520, idealHeight: 640)
        #endif
        .task {
            guard let replacing, let jpeg = replacing.sourcePhoto?.jpeg, photos.isEmpty else { return }
            importing = true
            defer { importing = false }
            do {
                let original = try await ScanPhoto.loadSaved(jpeg)
                photos = [original]
                originalPhotoID = original.id
                focus = CGPoint(x: replacing.sourceX ?? 0.5, y: replacing.sourceY ?? 0.5)
            } catch { message = error.localizedDescription }
        }
        .onDisappear { scanTask?.cancel() }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            importing = true
            Task {
                message = nil
                for item in items.prefix(available) {
                    do {
                        guard let bytes = try await item.loadTransferable(type: Data.self) else {
                            throw ScanFailure("A selected photo could not be opened.")
                        }
                        accept(try await ScanPhoto.prepare(bytes))
                    } catch { message = error.localizedDescription }
                }
                selection = []
                importing = false
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
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: replacing == nil) { result in
            guard case let .success(urls) = result else { return }
            importing = true
            Task {
                let available = self.available
                message = urls.count > available ? "Only the first \(available) images fit in this scan." : nil
                for url in urls.prefix(available) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do { accept(try await ScanPhoto.prepare(Data(contentsOf: url, options: .mappedIfSafe))) }
                    catch { message = error.localizedDescription }
                }
                importing = false
            }
        }
        #endif
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let replacing {
                Text(replacing.name).font(.title2.bold())
                if let photo = photos.first {
                    IngredientSourceImage(image: photo.preview, point: focus,
                        name: movedMarker ? "Rescan here" : replacing.detectedName ?? replacing.name) { point in
                        focus = point
                        movedMarker = true
                    }
                    .allowsHitTesting(!working && !importing)
                    Text("Tap the item to position the marker, or choose a closer photo.")
                        .foregroundStyle(KitchenTheme.muted)
                } else if !importing {
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
                PhotosPicker(selection: $selection, maxSelectionCount: max(1, available),
                             selectionBehavior: .ordered, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                #if os(macOS)
                Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
                #endif
            }
            .buttonStyle(.bordered)
            .disabled(available == 0 || working || importing)
            if replacing == nil {
                HStack {
                    Text("\(photos.count) of \(limit) photos").font(.subheadline.weight(.semibold))
                    if importing { ProgressView().controlSize(.small) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(photos) { photo in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                            .overlay {
                                Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                            }
                            .clipped()
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay(alignment: .topTrailing) {
                                Button { photos.removeAll { $0.id == photo.id } } label: {
                                    Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.7)).padding(10)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove photo \((photos.firstIndex { $0.id == photo.id } ?? 0) + 1)")
                                .disabled(working || importing)
                            }
                    }
                }
            }
            Text(replacing == nil ? "Processing sends these photos to OpenAI. You can review the results before saving."
                 : "Rescanning sends a close-up around the marker to OpenAI.")
                .font(.footnote).foregroundStyle(KitchenTheme.muted)
        }
    }

    private var reviewForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Back to photos") { review = nil; message = nil }
            Text(replacing == nil ? "Check each marked item before saving it to your pantry." : "Review the correction before updating this ingredient.")
                .font(.subheadline).foregroundStyle(KitchenTheme.muted)
            if let rows = Binding($review) {
                ForEach(rows) { $row in
                    VStack(alignment: .leading, spacing: 10) {
                        IngredientSourceImage(image: photos[row.item.photoIndex].preview,
                            point: CGPoint(x: row.item.x, y: row.item.y), name: row.detectedName)
                        if replacing == nil {
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

    private var selectedItems: [ScannedIngredient] {
        (review ?? []).filter { $0.included && !$0.item.lookupName.isEmpty }.map(\.item)
    }

    private var primaryTitle: String {
        if working { return "Reading ingredients…" }
        if replacing != nil { return review == nil ? "Rescan this item" : "Save correction" }
        if review != nil { return "Save to pantry (\(selectedItems.count))" }
        return "Process photos"
    }

    private func primaryAction() {
        message = nil
        if review != nil {
            do {
                try saveReviewedItems()
                didSave()
                dismiss()
            } catch { message = "Could not save your pantry. \(error.localizedDescription)" }
            return
        }
        working = true
        scanTask = Task {
            defer { working = false }
            do {
                let items: [ScannedIngredient]
                if replacing != nil, let photo = photos.first {
                    items = try await photo.recognize(at: focus)
                } else {
                    items = try await PantryScanner.recognize(photos.map(\.jpeg))
                }
                try Task.checkCancellation()
                if items.isEmpty {
                    message = "No ingredients were clear enough to identify. Try a closer photo of the labels."
                } else {
                    review = items.map { ReviewItem(item: $0, detectedName: $0.name) }
                }
            } catch {
                if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }

    private func saveReviewedItems() throws {
        // Use an isolated context so a failed save leaves the visible pantry intact.
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        let existing = try writer.fetch(FetchDescriptor<PantryIngredient>())
        var byName = Dictionary(uniqueKeysWithValues: existing.map { ($0.lookupName, $0) })
        let target = existing.first { $0.persistentModelID == replacing?.persistentModelID }
        if replacing != nil && target == nil {
            throw ScanFailure("This ingredient was removed. Close this scan and open your pantry again.")
        }
        guard Set(selectedItems.map(\.lookupName)).count == selectedItems.count else {
            throw ScanFailure("Two selected items have the same name. Rename one or deselect it before saving.")
        }
        var sources: [UUID: PantrySourcePhoto] = [:]
        for row in review ?? [] where row.included && !row.item.lookupName.isEmpty {
            var item = row.item
            item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            item.quantity = item.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
            if let target, let match = byName[item.lookupName], target !== match {
                throw ScanFailure("Your pantry already contains \(match.name). Choose a distinct name before saving.")
            }
            let stored = target ?? byName[item.lookupName] ?? PantryIngredient(item)
            if stored.modelContext == nil { writer.insert(stored) }
            let photo = photos[item.photoIndex]
            let source: PantrySourcePhoto
            if photo.id == originalPhotoID, let original = target?.sourcePhoto, original.jpeg == photo.jpeg {
                source = original
            } else if let shared = sources[photo.id] {
                source = shared
            } else {
                source = PantrySourcePhoto(jpeg: photo.jpeg)
                writer.insert(source)
                sources[photo.id] = source
            }
            if stored.sourcePhoto !== source {
                stored.releaseSource(in: writer)
                stored.sourcePhoto = source
            }
            stored.sourceX = item.x
            stored.sourceY = item.y
            stored.detectedName = row.detectedName
            stored.name = item.name
            if stored.lookupName != item.lookupName { stored.iconPNG = nil }
            stored.lookupName = item.lookupName
            stored.storageArea = item.area.rawValue
            stored.emoji = item.emoji
            if replacing != nil || !item.quantity.isEmpty { stored.quantity = item.quantity }
            byName[item.lookupName] = stored
        }
        try writer.save()
        PantryIcons.shared.start(in: context.container)
    }

    #if os(iOS) || os(macOS)
    private func openCamera() async {
        #if os(iOS)
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            message = "This device has no available camera. Choose an image from Photos."
            return
        }
        #endif
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            message = "Allow camera access in Settings, or choose an existing photo."
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
        importing = true
        Task {
            defer { importing = false }
            do { accept(try await ScanPhoto.prepare(data)); message = nil }
            catch { message = error.localizedDescription }
        }
    }
}

private struct ReviewItem: Identifiable {
    let id = UUID()
    var included = true
    var item: ScannedIngredient
    let detectedName: String
}
