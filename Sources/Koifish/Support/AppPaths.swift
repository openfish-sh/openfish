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

    static var styleProfile: URL { dataFolder.appendingPathComponent("style-profile.json") }
    static var interactionLog: URL { dataFolder.appendingPathComponent("interactions.jsonl") }
}
