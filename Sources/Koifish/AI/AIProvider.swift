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
    case malformedAPIKey(ProviderKind, hint: String)
    case http(status: Int, body: String)
    case malformedResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p):
            return "No API key set for \(p.displayName). Add one in Settings → API Keys."
        case .malformedAPIKey(let p, let hint):
            return "That doesn't look like a valid \(p.displayName) key. \(hint)"
        case .http(let status, let body):
            switch status {
            case 401: return "Invalid API key (HTTP 401). Check it in Settings → API Keys."
            case 429: return "Rate limited or out of quota (HTTP 429). Wait a moment, or switch provider in Settings (e.g. Groq/Custom)."
            case 404: return "Model not found (HTTP 404). Pick a different model in Settings."
            default: return "Request failed (HTTP \(status)): \(body.prefix(200))"
            }
        case .malformedResponse(let detail):
            return "Unexpected response from the provider: \(detail)"
        case .network(let detail):
            return "Network error: \(detail)"
        }
    }

    /// Pre-flight shape check on an API key, so an obviously-wrong key fails right
    /// away with a clear message instead of an opaque mid-stream HTTP 401. Catches
    /// the three common mistakes: a missing key, stray whitespace from a paste, and
    /// a key dropped into the wrong provider's field (caught by its prefix). Lenient
    /// by design — it only rejects what's clearly wrong, so a future key-format
    /// change can't lock a valid key out. Pure — unit-testable.
    static func keyShapeProblem(_ apiKey: String, for kind: ProviderKind) -> AIError? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return kind.requiresKey ? .missingAPIKey(kind) : nil
        }
        if trimmed != apiKey || trimmed.contains(where: \.isWhitespace) {
            return .malformedAPIKey(kind, hint: "Remove any spaces or line breaks in it.")
        }
        if let prefix = kind.apiKeyPrefix, !trimmed.hasPrefix(prefix) {
            return .malformedAPIKey(kind, hint: "It should start with “\(prefix)”.")
        }
        return nil
    }
}

extension ProviderKind {
    /// The prefix a well-formed key for this provider carries — used to catch a key
    /// pasted into the wrong provider's field before any request goes out. nil for
    /// custom OpenAI-compatible endpoints, whose keys can take any shape (or be
    /// absent, e.g. a local Ollama/LM Studio server).
    var apiKeyPrefix: String? {
        switch self {
        case .anthropic: return "sk-ant-"
        case .openai: return "sk-"
        case .gemini: return "AIza"
        case .openAICompatible: return nil
        }
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
