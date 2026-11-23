import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated protocol ImageGenerating: Sendable {
    func generate(prompt: String, transparent: Bool, maxPixels: Int) async throws -> Data
}

nonisolated struct OpenAIImageGenerator: ImageGenerating {
    let client: OpenAIClient

    @concurrent func generate(prompt: String, transparent: Bool, maxPixels: Int) async throws -> Data {
        let data = try await client.post("images/generations", body: [
            "model": "gpt-image-1-mini", "prompt": prompt, "size": transparent ? "1024x1024" : "1536x1024",
            "quality": "low", "background": transparent ? "transparent" : "opaque", "output_format": transparent ? "png" : "jpeg", "n": 1
        ], timeout: 180)
        struct Result: Decodable {
            struct Item: Decodable { let b64_json: String }
            let data: [Item]
        }
        let result = try JSONDecoder().decode(Result.self, from: data)
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceThumbnailMaxPixelSize: maxPixels] as CFDictionary
        let bytes = NSMutableData()
        guard let base64 = result.data.first?.b64_json, let original = Data(base64Encoded: base64),
              let source = CGImageSourceCreateWithData(original as CFData, nil),
              let icon = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              let encoder = CGImageDestinationCreateWithData(bytes, (transparent ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil)
        else { throw KitchenError("The generated image could not be opened.") }
        CGImageDestinationAddImage(encoder, icon, nil)
        guard CGImageDestinationFinalize(encoder) else { throw KitchenError("The image could not be saved.") }
        return bytes as Data
    }
}
