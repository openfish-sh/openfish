import Foundation

/// Refreshes the StyleProfile by asking a cheap model to summarize the user's
/// voice from their recent accepted/edited replies. Runs in the background.
enum Personalizer {
    /// Number of accepted/edited samples to feed into a refresh.
    static let sampleWindow = 20

    /// Generate an updated style description for the profile whose data lives in
    /// `dir`, from that profile's recent samples, and persist it there.
    static func refresh(in dir: URL) async {
        // Snapshot main-actor settings once, then run entirely off the main actor.
        let config = await MainActor.run {
            let s = Settings.shared
            return Config(learningEnabled: s.learningEnabled, provider: s.provider,
                          baseURL: s.activeBaseURL, customModel: s.customModel)
        }
        guard config.learningEnabled else { return }
        let provider = config.provider
        guard let apiKey = KeychainStore.key(for: provider), !apiKey.isEmpty else { return }

        let samples = InteractionLog.recent(limit: sampleWindow, dispositions: [.accepted, .edited], in: dir)
        guard samples.count >= 3 else { return } // not enough signal yet

        let request = GenerationRequest(
            systemPrompt: Self.systemPrompt,
            userPrompt: Self.userPrompt(samples: samples),
            model: summaryModel(for: provider, customModel: config.customModel),
            maxTokens: 600
        )

        let ai = AIProviderFactory.make(provider, baseURL: config.baseURL)
        do {
            let description = try await ai.complete(request, apiKey: apiKey)
            var profile = StyleProfile.load(in: dir)
            profile.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.sampleCount = samples.count
            profile.updatedAtEpoch = Date().timeIntervalSince1970
            profile.save(in: dir)
            Log.info("Style profile refreshed from \(samples.count) samples.")
        } catch {
            Log.error("Style refresh failed: \(error.localizedDescription)")
        }
    }

    /// Settings values read once on the main actor, then used off-main.
    private struct Config: Sendable {
        let learningEnabled: Bool
        let provider: ProviderKind
        let baseURL: URL?
        let customModel: String
    }

    private static func summaryModel(for provider: ProviderKind, customModel: String) -> String {
        switch provider {
        case .anthropic: return AIModels.summaryAnthropic
        case .openai: return AIModels.summaryOpenAI
        case .gemini: return AIModels.summaryGemini
        case .openAICompatible: return customModel  // no cheaper tier; reuse the chosen model
        }
    }

    private static let systemPrompt = """
    You analyze writing samples and produce a concise, second-person description of \
    the author's writing style, for use by an assistant that drafts messages in their \
    voice. Cover tone, formality, sentence length, punctuation/emoji habits, greetings \
    and sign-offs, and any recurring phrasings. Be specific and actionable. Output only \
    the description (4-8 short bullet points), no preamble.
    """

    private static func userPrompt(samples: [Interaction]) -> String {
        // Prefer the final (possibly edited) text — that's what the user actually wanted.
        let texts = samples
            .map { $0.final.isEmpty ? $0.generated : $0.final }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(sampleWindow)
            .enumerated()
            .map { "Example \($0.offset + 1):\n\($0.element)" }
            .joined(separator: "\n\n")
        return "Here are messages the user has written or approved:\n\n\(texts)"
    }
}
