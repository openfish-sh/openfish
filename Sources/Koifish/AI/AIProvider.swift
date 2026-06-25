import Foundation

/// A single text-generation request, provider-agnostic.
struct GenerationRequest: Sendable {
    var systemPrompt: String
    var userPrompt: String
    var model: String
    /// Output ceiling. Generous so replies/rewrites don't clip; for OpenAI GPT-5
    /// this is `max_completion_tokens`, which also covers reasoning tokens.
    var maxTokens: Int = 2048
}

enum AIError: LocalizedError, Sendable {
    case missingAPIKey(ProviderKind)
    case http(status: Int, body: String)
    case malformedResponse(String)
    case network(String)
    /// The request succeeded but the model produced no usable text — there's no
    /// draft to insert, so we say so rather than silently doing nothing.
    case emptyResponse(ProviderKind)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p):
            return "No API key set for \(p.displayName). Add one in Settings → API Keys."
        case .http(let status, let body):
            switch status {
            case 401: return "Invalid API key (HTTP 401). Check it in Settings → API Keys."
            case 429: return "Rate limited or out of quota (HTTP 429). Wait a moment, or switch provider in Settings (e.g. Groq/Custom)."
            case 404: return "Model not found (HTTP 404). Pick a different model in Settings."
            default: return "Couldn't make a draft (HTTP \(status)): \(Self.providerMessage(fromBody: body))"
            }
        case .malformedResponse(let detail):
            return "Unexpected response from the provider: \(detail)"
        case .network(let detail):
            return "Network error: \(detail)"
        case .emptyResponse(let p):
            return "\(p.displayName) returned an empty reply — no draft to insert. Try again, or pick a different model in Settings."
        }
    }

    /// Pull the provider's own explanation out of an error body. Anthropic- and
    /// OpenAI-style APIs both nest it under `error.message`; some (Gemini, custom
    /// servers) put it at the top level. Falls back to the trimmed raw body so we
    /// never show empty, and never dump bare JSON at the user.
    private static func providerMessage(fromBody body: String) -> String {
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = obj["error"] as? [String: Any],
               let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if let message = obj["message"] as? String, !message.isEmpty {
                return message
            }
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "no detail from the provider" : String(trimmed.prefix(300))
    }
}

/// A text-generation backend (Claude, GPT, …). Streams incremental text chunks
/// as an `AsyncThrowingStream`, so consumers iterate in their own isolation
/// domain (no cross-actor callback). The stream finishes on `[DONE]` or throws.
protocol AIProvider: Sendable {
    var kind: ProviderKind { get }
    func stream(_ request: GenerationRequest, apiKey: String) -> AsyncThrowingStream<String, Error>
}

extension AIProvider {
    /// Accumulate the whole reply (for callers that don't render incrementally).
    func complete(_ request: GenerationRequest, apiKey: String) async throws -> String {
        var full = ""
        for try await delta in stream(request, apiKey: apiKey) { full += delta }
        return full
    }
}

/// Speech-to-text backend (any OpenAI-compatible /audio/transcriptions endpoint).
/// `language` is an optional ISO-639-1 hint (nil/empty → auto-detect).
protocol TranscriptionProvider: Sendable {
    func transcribe(wavData: Data, apiKey: String, model: String, language: String?) async throws -> String
}

/// Builds the right provider instance for a given kind.
enum AIProviderFactory {
    static func make(_ kind: ProviderKind, baseURL: URL?) -> AIProvider {
        switch kind {
        case .anthropic:
            return AnthropicProvider()
        case .openai:
            return OpenAIProvider()
        case .gemini:
            // Gemini exposes an OpenAI-compatible API at a fixed address.
            return OpenAIProvider(kind: .gemini,
                                  baseURL: kind.fixedBaseURL ?? URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!)
        case .openAICompatible:
            return OpenAIProvider(kind: .openAICompatible,
                                  baseURL: baseURL ?? URL(string: "https://api.openai.com/v1")!)
        }
    }
}
