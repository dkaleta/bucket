import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScanPhoto: Identifiable {
    let id = UUID()
    let jpeg: Data
    let preview: CGImage

    @concurrent static func loadSaved(_ jpeg: Data) async throws -> Self {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceThumbnailMaxPixelSize: 1280] as CFDictionary
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw KitchenError("Could not open the saved photo. Choose a new photo to rescan this item.")
        }
        return Self(jpeg: jpeg, preview: preview)
    }

    @concurrent static func prepare(_ data: Data) async throws -> Self {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw KitchenError("This photo could not be read. Try a JPEG or HEIC image.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
        ]
        let bytes = NSMutableData()
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let output = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw KitchenError("This photo could not be prepared.") }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw KitchenError("This photo could not be prepared.") }
        return try await loadSaved(bytes as Data)
    }
}
