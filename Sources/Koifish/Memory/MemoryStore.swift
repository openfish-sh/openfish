import Foundation

/// Facade the Coordinator talks to: supplies the current style description for
/// prompt building and records interactions, periodically refreshing the profile.
@MainActor
final class MemoryStore {
    /// Trigger a profile refresh after this many new accepted/edited samples.
    private let refreshEvery = 5
    private var newSamplesSinceRefresh = 0
    /// In-flight refresh, so we never run two concurrent StyleProfile writes.
    private var refreshTask: Task<Void, Never>?

    /// The style text to feed into prompts: the learned profile if we have one,
    /// otherwise the user's manual seed from Settings.
    func styleDescription(seed: String) -> String {
        let profile = StyleProfile.load()
        let learned = profile.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let seedTrimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)

        if !learned.isEmpty && !seedTrimmed.isEmpty {
            return "\(seedTrimmed)\n\nObserved style:\n\(learned)"
        }
        return learned.isEmpty ? seedTrimmed : learned
    }

    func record(context: FocusedContext, generated: String, final: String, disposition: Interaction.Disposition) {
        let interaction = Interaction(
            epoch: Date().timeIntervalSince1970,
            appName: context.appName,
            windowTitle: context.windowTitle,
            contextText: context.hasSelection ? context.selectedText : context.fieldText,
            generated: generated,
            final: final,
            disposition: disposition
        )
        InteractionLog.append(interaction)

        guard Settings.shared.learningEnabled else { return }
        guard disposition == .accepted || disposition == .edited else { return }

        newSamplesSinceRefresh += 1
        if newSamplesSinceRefresh >= refreshEvery {
            newSamplesSinceRefresh = 0
            guard refreshTask == nil else { return }   // coalesce: one refresh at a time
            refreshTask = Task(priority: .utility) { [weak self] in
                await Personalizer.refresh()
                self?.refreshTask = nil
            }
        }
    }
}
