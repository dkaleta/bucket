import Foundation
import XCTest
@testable import bocado

final class OpenAIServiceTests: XCTestCase {
    func testScannerAndImagesUseInjectedTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KitchenAPIStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = OpenAIClient(session: session, apiKey: "test-key")
        let scanner = PantryScanner(client: client)
        let items = try await scanner.recognize([Data([0]), Data([1])])
        XCTAssertEqual(items.map(\.name), ["Oregano"])
        XCTAssertEqual(items.first?.photoIndex, 0)
        XCTAssertEqual(items.first?.x, 0.25)

        let generator = OpenAIImageGenerator(client: client)
        let png = try await generator.generate(prompt: "Oregano", transparent: true, maxPixels: 160)
        XCTAssertEqual(Array(png.prefix(4)), [137, 80, 78, 71])
    }
}

private final class KitchenAPIStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.host == "api.openai.com",
              request.httpMethod == "POST", request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let body: [String: Any]
        switch url.path {
        case "/v1/chat/completions":
            let inventory = #"{"ingredients":[{"name":"Oregano","quantity":"","area":"Cupboard","emoji":"🌿","x":0.25,"y":0.5}]}"#
            body = ["choices": [["finish_reason": "stop", "message": ["content": inventory]]]]
        case "/v1/images/generations":
            body = ["data": [["b64_json": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aV1sAAAAASUVORK5CYII="]]]
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}
}
