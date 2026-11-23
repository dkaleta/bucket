import Foundation
import ImageIO
import UniformTypeIdentifiers

enum KitchenImage {
    @concurrent static func generate(prompt: String, transparent: Bool, maxPixels: Int) async throws -> Data {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
            throw ScanFailure("Run Bocado from Xcode with OPENAI_API_KEY to generate images.")
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-image-1-mini", "prompt": prompt, "size": transparent ? "1024x1024" : "1536x1024",
            "quality": "low", "background": transparent ? "transparent" : "opaque", "output_format": transparent ? "png" : "jpeg", "n": 1
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            switch status {
            case 401, 403: throw ScanFailure("Check your OpenAI key and image model access.")
            case 429: throw ScanFailure("OpenAI reached a usage limit. Try again later.")
            default: throw ScanFailure("OpenAI could not generate the image (HTTP \(status)).")
            }
        }
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
        else { throw ScanFailure("The generated image could not be opened.") }
        CGImageDestinationAddImage(encoder, icon, nil)
        guard CGImageDestinationFinalize(encoder) else { throw ScanFailure("The image could not be saved.") }
        return bytes as Data
    }
}
