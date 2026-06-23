import Foundation

/// Claude via the Anthropic Messages API (streaming).
/// Endpoint, headers, and SSE event shapes per the Anthropic API reference.
struct AnthropicProvider: AIProvider {
    let kind: ProviderKind = .anthropic

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    func stream(_ request: GenerationRequest, apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: endpoint)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

                    let body = RequestBody(
                        model: request.model,
                        maxTokens: request.maxTokens,
                        system: request.systemPrompt,
                        messages: [.init(role: "user", content: request.userPrompt)]
                    )
                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    req.httpBody = try encoder.encode(body)

                    try await StreamingHTTP.stream(req) { payload in
                        if let text = Self.textDelta(fromSSE: payload) { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct RequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let stream = true
        let system: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    /// Pull the text from a `content_block_delta` SSE payload (nil for other
    /// events: message_start, ping, content_block_stop, …). Pure — unit-tested.
    static func textDelta(fromSSE payload: String) -> String? {
        guard let obj = StreamingHTTP.jsonObject(payload),
              obj["type"] as? String == "content_block_delta",
              let delta = obj["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta",
              let text = delta["text"] as? String
        else { return nil }
        return text
    }
}
