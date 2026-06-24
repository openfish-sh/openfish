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
        // A custom endpoint with no model set can't be called — don't fire (and log) a
        // doomed request every refresh cycle.
        if provider == .openAICompatible,
           config.customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

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
    You analyze how a person writes and produce a concise, second-person description of \
    their style, for an assistant that drafts messages in their voice. You get two kinds \
    of evidence:
    1. Messages they sent as-is — their natural voice.
    2. Cases where the assistant drafted something and they rewrote it before sending — \
    the change from draft to sent is the strongest signal of what they actually want.

    Cover tone, formality, sentence length, greetings and sign-offs, punctuation/emoji \
    habits, and recurring phrasings. From the rewrites, call out what they consistently \
    change — e.g. cuts the greeting, shortens, drops hedging, swaps formal words for \
    plain ones. Be specific and actionable. Output only the description (4-8 short bullet \
    points), no preamble.
    """

    private static func userPrompt(samples: [Interaction]) -> String {
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var sections: [String] = []

        // Sent as-is: positive examples of the user's natural voice.
        let asIs = samples
            .filter { $0.disposition == .accepted }
            .map { clean($0.final.isEmpty ? $0.generated : $0.final) }
            .filter { !$0.isEmpty }
            .suffix(sampleWindow)
        if !asIs.isEmpty {
            let list = asIs.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n")
            sections.append("Messages the person sent as-is:\n\n\(list)")
        }

        // Edited: the assistant's draft vs what the person actually sent. The change is
        // the strongest signal of their preferences.
        let edits = samples
            .filter { $0.disposition == .edited }
            .map { (draft: clean($0.generated), sent: clean($0.final)) }
            .filter { !$0.draft.isEmpty && !$0.sent.isEmpty && $0.draft != $0.sent }
            .suffix(sampleWindow)
        if !edits.isEmpty {
            let list = edits.enumerated().map {
                "\($0.offset + 1). Draft: \($0.element.draft)\n   They sent: \($0.element.sent)"
            }.joined(separator: "\n\n")
            sections.append("Drafts the person rewrote before sending (learn what they change):\n\n\(list)")
        }

        return sections.isEmpty ? "(no samples)" : sections.joined(separator: "\n\n---\n\n")
    }
}
