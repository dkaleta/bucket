import Foundation

nonisolated struct OpenAIClient: Sendable {
    let session: URLSession
    let apiKey: String?

    func post(_ endpoint: String, body: [String: Any], timeout: TimeInterval) async throws -> Data {
        guard let apiKey, !apiKey.isEmpty else {
            throw KitchenError("Run Bocado from Xcode with OPENAI_API_KEY enabled in the Run scheme.")
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/")!.appending(path: endpoint))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401, 403: throw KitchenError("OpenAI declined the API key. Check the key and model access in Xcode.")
        case 429: throw KitchenError("OpenAI reached a usage limit. Try again later.")
        default: throw KitchenError("OpenAI could not complete the request (HTTP \(status)). Try again.")
        }
    }

    func completion<T: Decodable>(content: Any, schema: [String: Any], name: String,
                                  timeout: TimeInterval, incomplete: String) async throws -> T {
        let data = try await post("chat/completions", body: [
            "model": "gpt-4.1-mini", "store": false,
            "messages": [["role": "user", "content": content]],
            "response_format": ["type": "json_schema", "json_schema": [
                "name": name, "strict": true, "schema": schema
            ]]
        ], timeout: timeout)
        let decoder = JSONDecoder()
        let completion = try decoder.decode(Completion.self, from: data)
        guard let choice = completion.choices.first, choice.finish_reason == "stop",
              let text = choice.message.content else { throw KitchenError(incomplete) }
        return try decoder.decode(T.self, from: Data(text.utf8))
    }

    private struct Completion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
            let finish_reason: String
        }
        let choices: [Choice]
    }
}
