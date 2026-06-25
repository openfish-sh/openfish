import Foundation

/// OpenAI Chat Completions (streaming) + Whisper transcription. The base URL is
/// configurable so the exact same code drives any OpenAI-compatible endpoint —
/// OpenAI, Groq, OpenRouter, Gemini's compat API, Ollama, LM Studio, …
struct OpenAIProvider: AIProvider, TranscriptionProvider {
    let kind: ProviderKind

    /// e.g. https://api.openai.com/v1 or https://api.groq.com/openai/v1
    private let baseURL: URL

    init(kind: ProviderKind = .openai, baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.kind = kind
        self.baseURL = baseURL
    }

    private var chatEndpoint: URL { baseURL.appendingPathComponent("chat/completions") }
    private var transcribeEndpoint: URL { baseURL.appendingPathComponent("audio/transcriptions") }

    // MARK: Generation

    func stream(_ request: GenerationRequest, apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: chatEndpoint)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }

                    // OpenAI's own GPT-5 models reject `max_tokens` and require
                    // `max_completion_tokens`. The OpenAI-compatible endpoints we also
                    // drive here (Gemini, Groq, OpenRouter, Ollama, …) still expect
                    // `max_tokens`, so pick the field by provider.
                    let useCompletionTokens = (kind == .openai)
                    let effort = Self.reasoningEffort(for: kind)
                    let body = RequestBody(
                        model: request.model,
                        maxTokens: useCompletionTokens ? nil : request.maxTokens,
                        maxCompletionTokens: useCompletionTokens ? request.maxTokens : nil,
                        reasoningEffort: effort,
                        messages: [
                            .init(role: "system", content: request.systemPrompt),
                            .init(role: "user", content: request.userPrompt),
                        ]
                    )
                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    req.httpBody = try encoder.encode(body)

                    try await StreamingHTTP.stream(req) { payload in
                        guard let text = Self.textDelta(fromSSE: payload) else { return false }
                        continuation.yield(text)
                        return true
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The `reasoning_effort` to send, by provider. GPT-5 and Gemini "think" before
    /// answering; for short inline replies that's slow and can spill the model's
    /// scratchpad into the output, so we hold reasoning to the minimum. The gpt-5.4
    /// family renamed the old `"minimal"` tier to `"none"` (and rejects `"minimal"`).
    /// nil for endpoints that may reject the param outright (a custom OpenAI-compatible
    /// server, which could be any model).
    static func reasoningEffort(for kind: ProviderKind) -> String? {
        switch kind {
        case .openai: "none"
        case .gemini: "low"
        default: nil
        }
    }

    private struct RequestBody: Encodable {
        let model: String
        // Exactly one of these is set; nil Optionals are omitted from the JSON.
        let maxTokens: Int?
        let maxCompletionTokens: Int?
        let reasoningEffort: String?
        let stream = true
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    /// Pull `choices[0].delta.content` from a chat-completions SSE payload (nil
    /// for role-only deltas, finish chunks, …). Pure — unit-tested.
    static func textDelta(fromSSE payload: String) -> String? {
        guard let obj = StreamingHTTP.jsonObject(payload),
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let text = delta["content"] as? String
        else { return nil }
        return text
    }

    // MARK: Transcription (Whisper)

    func transcribe(wavData: Data, apiKey: String, model: String, language: String?) async throws -> String {
        let boundary = "koifish-\(UUID().uuidString)"
        var req = URLRequest(url: transcribeEndpoint)
        req.httpMethod = "POST"
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = multipartBody(boundary: boundary, wavData: wavData, model: model, language: language)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            if error is CancellationError { throw error }
            throw AIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIError.malformedResponse("no HTTP response")
        }
        guard http.statusCode == 200 else {
            throw AIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String
        else {
            throw AIError.malformedResponse("transcription response had no `text`")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func multipartBody(boundary: String, wavData: Data, model: String, language: String?) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        if let language, !language.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            append("\(language)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }
}
