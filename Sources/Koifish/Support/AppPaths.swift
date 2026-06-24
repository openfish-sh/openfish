import Foundation

/// Canonical on-disk locations for Koifish's local data.
enum AppPaths {
    /// ~/Library/Application Support/Koifish — created on first access.
    static let dataFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Folder name stays "Koifish" so existing local data (style profile,
        // interaction log) carries over across the OpenFish rename.
        let folder = base.appendingPathComponent("Koifish", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// The list of personalities and which is active.
    static var profilesFile: URL { dataFolder.appendingPathComponent("profiles.json") }

    /// Per-profile data folder (`profiles/<id>/`), holding that profile's learned
    /// `style-profile.json` and `interactions.jsonl`. Created on first access.
    static func profileDir(_ id: UUID) -> URL {
        let dir = dataFolder
            .appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Pre-profiles (flat) locations, read once by `ProfileStore` migration.
    static var legacyStyleProfile: URL { dataFolder.appendingPathComponent("style-profile.json") }
    static var legacyInteractionLog: URL { dataFolder.appendingPathComponent("interactions.jsonl") }
}
