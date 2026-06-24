import Foundation

/// The learned description of the user's writing voice, refined over time from
/// accepted/edited replies. Persisted as JSON in the app's data folder.
struct StyleProfile: Codable {
    /// Second-person, assistant-facing description of how the user writes.
    var description: String = ""
    /// How many accepted/edited samples have informed this profile.
    var sampleCount: Int = 0
    /// When the profile was last refreshed (epoch seconds; nil if never).
    var updatedAtEpoch: Double?

    /// Serializes file access so a background refresh write can't race a main-actor
    /// read (or "Refresh now" / "Forget" running concurrently) and lose an update.
    private static let ioQueue = DispatchQueue(label: "sh.koifish.styleprofile")

    /// Load the learned profile from a profile's data folder (empty if none yet).
    static func load(in dir: URL) -> StyleProfile {
        let url = dir.appendingPathComponent("style-profile.json")
        return ioQueue.sync {
            guard let data = try? Data(contentsOf: url),
                  let profile = try? JSONDecoder().decode(StyleProfile.self, from: data)
            else { return StyleProfile() }
            return profile
        }
    }

    func save(in dir: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let url = dir.appendingPathComponent("style-profile.json")
        Self.ioQueue.sync { try? data.write(to: url, options: .atomic) }
    }
}

extension StyleProfile {
    /// Tolerant decoding: a missing key falls back to its default instead of
    /// throwing, so adding or removing a field in a future version still loads an
    /// existing file (keeping the learned profile) rather than resetting it. Safe
    /// because the file is written atomically — there's never a torn read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        self.sampleCount = (try? c.decodeIfPresent(Int.self, forKey: .sampleCount)) ?? 0
        self.updatedAtEpoch = try? c.decodeIfPresent(Double.self, forKey: .updatedAtEpoch)
    }
}

/// One recorded interaction, appended to the JSONL log.
struct Interaction: Codable {
    enum Disposition: String, Codable {
        case accepted   // inserted the draft unchanged
        case edited     // inserted after editing
        case rejected   // cancelled / discarded
    }

    var epoch: Double
    var appName: String
    var windowTitle: String
    var contextText: String
    var generated: String
    var final: String
    var disposition: Disposition
}
