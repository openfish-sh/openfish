import Foundation

/// Facade the Coordinator talks to: supplies a profile's style description for
/// prompt building and records interactions against that profile, refreshing its
/// learned style as samples accumulate. Each profile learns in isolation.
@MainActor
final class MemoryStore {
    /// Trigger a profile's style refresh after this many new accepted/edited samples.
    private let refreshEvery = 5
    private var samplesSince: [UUID: Int] = [:]
    /// In-flight refresh, so we never run two concurrent StyleProfile writes.
    private var refreshTask: Task<Void, Never>?

    /// The style text to feed into prompts for `profile`: its learned profile if we
    /// have one, combined with the user's manual seed.
    func styleDescription(for profile: Profile) -> String {
        let dir = AppPaths.profileDir(profile.id)
        let learned = StyleProfile.load(in: dir).description.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = profile.styleSeed.trimmingCharacters(in: .whitespacesAndNewlines)

        if !learned.isEmpty && !seed.isEmpty {
            return "\(seed)\n\nObserved style:\n\(learned)"
        }
        return learned.isEmpty ? seed : learned
    }

    /// Record an interaction against a specific profile. Once enough new
    /// accepted/edited samples accumulate *for that profile*, refresh its style.
    func record(profileID: UUID, context: FocusedContext, generated: String, final: String, disposition: Interaction.Disposition) {
        let dir = AppPaths.profileDir(profileID)
        let interaction = Interaction(
            epoch: Date().timeIntervalSince1970,
            appName: context.appName,
            windowTitle: context.windowTitle,
            contextText: context.hasSelection ? context.selectedText : context.fieldText,
            generated: generated,
            final: final,
            disposition: disposition
        )
        InteractionLog.append(interaction, in: dir)

        guard Settings.shared.learningEnabled,
              disposition == .accepted || disposition == .edited else { return }

        samplesSince[profileID, default: 0] += 1
        guard samplesSince[profileID, default: 0] >= refreshEvery else { return }
        // Only reset the counter once we actually launch the refresh — otherwise a
        // refresh already in flight (for any profile) would swallow this one and the
        // profile would have to re-accumulate all over again.
        guard refreshTask == nil else { return }   // a refresh is running; retry next sample
        samplesSince[profileID] = 0
        refreshTask = Task(priority: .utility) { [weak self] in
            await Personalizer.refresh(in: dir)
            self?.refreshTask = nil
        }
    }
}
