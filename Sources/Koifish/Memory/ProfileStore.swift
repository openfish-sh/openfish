import Foundation
import Combine

/// One switchable personality: a name plus the two things that shape its voice —
/// the user-authored "About you" brief and the manual style seed. Each profile's
/// *learned* style and interaction log live on disk under its own id (see
/// `AppPaths.profileDir`), so learning in one voice never bleeds into another.
struct Profile: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var brief: String
    var styleSeed: String

    init(id: UUID = UUID(), name: String, brief: String = "", styleSeed: String = "") {
        self.id = id
        self.name = name
        self.brief = brief
        self.styleSeed = styleSeed
    }
}

/// The list of profiles and which one is active. Persisted as one atomic JSON file
/// (`profiles.json`); the active id lives in UserDefaults. On first run it migrates
/// the pre-profiles global brief/seed/learned-style into a "Default" profile so no
/// existing data is lost.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var profiles: [Profile]
    @Published private(set) var activeID: UUID

    private let defaults = UserDefaults.standard
    private static let activeKey = "activeProfileID"

    /// The active profile (falls back to the first if the id ever dangles).
    var active: Profile { profiles.first { $0.id == activeID } ?? profiles[0] }

    private init() {
        // Compute into locals first — Swift forbids touching `self` until every
        // stored property is initialized.
        let loaded = Self.loadProfiles().flatMap { $0.isEmpty ? nil : $0 }
            ?? [Self.migrateLegacyIntoDefault()]
        let savedActive = UserDefaults.standard.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))

        self.profiles = loaded
        self.activeID = Self.resolveActiveID(in: loaded, saved: savedActive) ?? loaded[0].id
        persist()
    }

    /// Pick the active profile id: the saved one if it still exists, else the first.
    /// nil only for an empty list. Pure — unit-tested.
    nonisolated static func resolveActiveID(in profiles: [Profile], saved: UUID?) -> UUID? {
        guard !profiles.isEmpty else { return nil }
        if let saved, profiles.contains(where: { $0.id == saved }) { return saved }
        return profiles[0].id
    }

    // MARK: Mutations

    func setActive(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        defaults.set(id.uuidString, forKey: Self.activeKey)
    }

    @discardableResult
    func add(name: String) -> Profile {
        let profile = Profile(name: name)
        profiles.append(profile)
        persist()
        return profile
    }

    @discardableResult
    func duplicate(_ id: UUID) -> Profile? {
        guard let source = profiles.first(where: { $0.id == id }) else { return nil }
        let copy = Profile(name: "\(source.name) copy", brief: source.brief, styleSeed: source.styleSeed)
        // Starts with a fresh learned style — the duplicate re-learns from its own use.
        profiles.append(copy)
        persist()
        return copy
    }

    func rename(_ id: UUID, to name: String) {
        mutate(id) { $0.name = name }
    }

    func setBrief(_ id: UUID, _ brief: String) {
        mutate(id) { $0.brief = brief }
    }

    func setStyleSeed(_ id: UUID, _ seed: String) {
        mutate(id) { $0.styleSeed = seed }
    }

    /// Delete a profile (never the last one). Its on-disk data is removed too; if it
    /// was active, the first remaining profile takes over.
    func delete(_ id: UUID) {
        guard profiles.count > 1, profiles.contains(where: { $0.id == id }) else { return }
        profiles.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: AppPaths.profileDir(id))
        if activeID == id { setActive(profiles[0].id) }
        persist()
    }

    // MARK: Persistence

    private func mutate(_ id: UUID, _ change: (inout Profile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        change(&profiles[index])
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: AppPaths.profilesFile, options: .atomic)
    }

    private static func loadProfiles() -> [Profile]? {
        guard let data = try? Data(contentsOf: AppPaths.profilesFile) else { return nil }
        return try? JSONDecoder().decode([Profile].self, from: data)
    }

    /// First-run migration: fold the old global brief/seed into a "Default" profile
    /// and move the legacy learned-style + interaction log into its folder.
    private static func migrateLegacyIntoDefault() -> Profile {
        let d = UserDefaults.standard
        let profile = Profile(name: "Default",
                              brief: d.string(forKey: "userBrief") ?? "",
                              styleSeed: d.string(forKey: "styleSeed") ?? "")
        let dir = AppPaths.profileDir(profile.id)
        let fm = FileManager.default
        for (legacy, name) in [(AppPaths.legacyStyleProfile, "style-profile.json"),
                               (AppPaths.legacyInteractionLog, "interactions.jsonl")] {
            if fm.fileExists(atPath: legacy.path) {
                try? fm.moveItem(at: legacy, to: dir.appendingPathComponent(name))
            }
        }
        return profile
    }
}
