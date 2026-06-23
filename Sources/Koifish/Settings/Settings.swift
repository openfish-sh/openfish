import Foundation
import Combine

/// Which AI backend generates replies.
enum ProviderKind: String, CaseIterable, Codable, Identifiable {
    case anthropic
    case openai
    /// Any OpenAI-compatible endpoint (Groq, OpenRouter, Gemini compat, Ollama,
    /// LM Studio, …) with a user-set base URL + model.
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI (GPT)"
        case .openAICompatible: return "OpenAI-compatible"
        }
    }

    /// Short label for the segmented picker.
    var shortName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "OpenAI"
        case .openAICompatible: return "Custom"
        }
    }

    /// Where the user gets an API key (empty if not applicable).
    var keysURL: String {
        switch self {
        case .anthropic: return "https://console.anthropic.com/settings/keys"
        case .openai: return "https://platform.openai.com/api-keys"
        case .openAICompatible: return ""
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-…"
        case .openai: return "sk-…"
        case .openAICompatible: return "API key (optional for local models)"
        }
    }

    /// Whether a key is mandatory (local endpoints like Ollama need none).
    var requiresKey: Bool { self != .openAICompatible }
}

/// Quick-fill presets for the OpenAI-compatible provider.
struct CompatiblePreset: Identifiable {
    let id = UUID()
    let name: String
    let baseURL: String
    let model: String

    static let all: [CompatiblePreset] = [
        .init(name: "Groq", baseURL: "https://api.groq.com/openai/v1", model: "llama-3.3-70b-versatile"),
        .init(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", model: "anthropic/claude-sonnet-4.5"),
        .init(name: "Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", model: "gemini-2.0-flash"),
        .init(name: "Ollama (local)", baseURL: "http://localhost:11434/v1", model: "llama3.2"),
        .init(name: "LM Studio (local)", baseURL: "http://localhost:1234/v1", model: "local-model"),
    ]
}

/// What happens after a reply is generated.
enum InsertMode: String, CaseIterable, Codable, Identifiable {
    case overlay   // show an Accept/Edit/Regenerate panel first
    case direct    // insert immediately

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .overlay: return "Review in a popup first"
        case .direct: return "Insert immediately"
        }
    }
}

/// App configuration, persisted in UserDefaults. API keys live in the Keychain,
/// NOT here. Observable so SwiftUI settings views update live.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var provider: ProviderKind {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }
    @Published var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: Keys.anthropicModel) }
    }
    @Published var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: Keys.openAIModel) }
    }
    /// Base URL for the OpenAI-compatible provider (Groq, OpenRouter, Ollama, …).
    @Published var customBaseURL: String {
        didSet { defaults.set(customBaseURL, forKey: Keys.customBaseURL) }
    }
    /// Model id for the OpenAI-compatible provider (free-form).
    @Published var customModel: String {
        didSet { defaults.set(customModel, forKey: Keys.customModel) }
    }
    @Published var insertMode: InsertMode {
        didSet { defaults.set(insertMode.rawValue, forKey: Keys.insertMode) }
    }
    /// Trigger that generates a reply (default: tap Right Option).
    @Published var generateHotkey: HotkeyTrigger {
        didSet { defaults.set(generateHotkey.encoded, forKey: Keys.generateHotkey) }
    }
    /// Trigger held down to dictate (default: hold Fn).
    @Published var dictateHotkey: HotkeyTrigger {
        didSet { defaults.set(dictateHotkey.encoded, forKey: Keys.dictateHotkey) }
    }
    /// Whether auto-learning of writing style is enabled.
    @Published var learningEnabled: Bool {
        didSet { defaults.set(learningEnabled, forKey: Keys.learningEnabled) }
    }
    /// Opt-in cross-window activity memory (text-only, in-memory). Off by default.
    @Published var activityMemoryEnabled: Bool {
        didSet { defaults.set(activityMemoryEnabled, forKey: Keys.activityMemoryEnabled) }
    }
    /// Optional seed description of the user's voice, editable in settings.
    @Published var styleSeed: String {
        didSet { defaults.set(styleSeed, forKey: Keys.styleSeed) }
    }
    /// Standing facts about the user (role, projects, people, preferences) that the
    /// user authors, folded into every reply as background. Distinct from styleSeed,
    /// which is about voice. Empty by default.
    @Published var userBrief: String {
        didSet { defaults.set(userBrief, forKey: Keys.userBrief) }
    }
    /// Transcription model for dictation (empty → sensible default per source).
    @Published var voiceModel: String {
        didSet { defaults.set(voiceModel, forKey: Keys.voiceModel) }
    }
    /// ISO-639-1 language hint for dictation (empty → Whisper auto-detects).
    @Published var voiceLanguage: String {
        didSet { defaults.set(voiceLanguage, forKey: Keys.voiceLanguage) }
    }

    private init() {
        provider = ProviderKind(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .anthropic
        anthropicModel = defaults.string(forKey: Keys.anthropicModel) ?? AIModels.defaultAnthropic
        openAIModel = defaults.string(forKey: Keys.openAIModel) ?? AIModels.defaultOpenAI
        customBaseURL = defaults.string(forKey: Keys.customBaseURL) ?? ""
        customModel = defaults.string(forKey: Keys.customModel) ?? ""
        insertMode = InsertMode(rawValue: defaults.string(forKey: Keys.insertMode) ?? "") ?? .direct
        generateHotkey = HotkeyTrigger(encoded: defaults.string(forKey: Keys.generateHotkey) ?? "") ?? .defaultGenerate
        dictateHotkey = HotkeyTrigger(encoded: defaults.string(forKey: Keys.dictateHotkey) ?? "") ?? .defaultDictate
        learningEnabled = defaults.object(forKey: Keys.learningEnabled) as? Bool ?? true
        activityMemoryEnabled = defaults.object(forKey: Keys.activityMemoryEnabled) as? Bool ?? false
        styleSeed = defaults.string(forKey: Keys.styleSeed) ?? ""
        userBrief = defaults.string(forKey: Keys.userBrief) ?? ""
        voiceModel = defaults.string(forKey: Keys.voiceModel) ?? ""
        voiceLanguage = defaults.string(forKey: Keys.voiceLanguage) ?? ""
    }

    /// Transcription source: the OpenAI-compatible custom endpoint when that's the
    /// active provider, otherwise OpenAI Whisper (so Claude users can still dictate
    /// with an OpenAI key).
    var voiceSource: (baseURL: URL, keyProvider: ProviderKind, model: String) {
        if provider == .openAICompatible, let base = activeBaseURL {
            let model = voiceModel.isEmpty ? "whisper-large-v3" : voiceModel
            return (base, .openAICompatible, model)
        }
        let model = voiceModel.isEmpty ? AIModels.whisperModel : voiceModel
        return (URL(string: "https://api.openai.com/v1")!, .openai, model)
    }

    /// The model id to use for the currently selected provider.
    var activeModel: String {
        switch provider {
        case .anthropic: return anthropicModel
        case .openai: return openAIModel
        case .openAICompatible: return customModel
        }
    }

    /// Base URL for the active provider's OpenAI-compatible endpoint (custom only).
    /// nil unless it's a valid http(s) URL, so a schemeless entry is caught early.
    var activeBaseURL: URL? {
        guard provider == .openAICompatible,
              let url = URL(string: customBaseURL.trimmingCharacters(in: .whitespaces)),
              url.scheme == "http" || url.scheme == "https"
        else { return nil }
        return url
    }

    private enum Keys {
        static let provider = "provider"
        static let anthropicModel = "anthropicModel"
        static let openAIModel = "openAIModel"
        static let customBaseURL = "customBaseURL"
        static let customModel = "customModel"
        static let insertMode = "insertMode"
        static let generateHotkey = "generateHotkey"
        static let dictateHotkey = "dictateHotkey"
        static let learningEnabled = "learningEnabled"
        static let activityMemoryEnabled = "activityMemoryEnabled"
        static let styleSeed = "styleSeed"
        static let userBrief = "userBrief"
        static let voiceModel = "voiceModel"
        static let voiceLanguage = "voiceLanguage"
    }
}

/// Default + selectable model identifiers. Anthropic defaults to Sonnet for a
/// good latency/quality balance on short inline replies; Opus is available for
/// higher quality, Haiku for cheap background style summaries.
enum AIModels {
    static let defaultAnthropic = "claude-sonnet-4-6"
    static let summaryAnthropic = "claude-haiku-4-5"
    static let anthropicChoices = [
        "claude-sonnet-4-6",
        "claude-opus-4-8",
        "claude-haiku-4-5",
    ]

    static let defaultOpenAI = "gpt-4o"
    static let summaryOpenAI = "gpt-4o-mini"
    static let openAIChoices = [
        "gpt-4o",
        "gpt-4o-mini",
        "gpt-4.1",
    ]

    static let whisperModel = "whisper-1"
}
