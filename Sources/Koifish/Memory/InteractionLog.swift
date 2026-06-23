import Foundation

/// Append-only JSONL log of interactions. One JSON object per line so it stays
/// human-readable and cheap to append without rewriting the whole file.
///
/// Bounded: once the file passes `maxBytes` it's rewritten with only the most
/// recent `keepWhenTrimming` lines, so it can't grow without limit over months of
/// use. All file access goes through `queue`, so appends, trims, and reads never
/// race. Reads tolerate a torn final line (an append interrupted mid-write) by
/// skipping anything that doesn't decode.
enum InteractionLog {
    private static let queue = DispatchQueue(label: "sh.koifish.interactionlog")
    private static let maxBytes = 2_000_000          // ~2 MB before we trim
    private static let keepWhenTrimming = 1000       // most-recent entries retained

    static func append(_ interaction: Interaction) {
        queue.async {
            guard let line = try? JSONEncoder().encode(interaction),
                  var text = String(data: line, encoding: .utf8)
            else { return }
            text += "\n"
            let url = AppPaths.interactionLog

            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(text.utf8))
            } else {
                try? Data(text.utf8).write(to: url, options: .atomic)
            }
            trimIfNeeded(url)
        }
    }

    /// Read the most recent `limit` interactions matching `dispositions`.
    static func recent(limit: Int, dispositions: Set<Interaction.Disposition>) -> [Interaction] {
        queue.sync {
            guard let content = try? String(contentsOf: AppPaths.interactionLog, encoding: .utf8) else {
                return []
            }
            let decoder = JSONDecoder()
            let all: [Interaction] = content
                .split(separator: "\n")
                .compactMap { line in
                    guard let data = line.data(using: .utf8) else { return nil }
                    return try? decoder.decode(Interaction.self, from: data)
                }
                .filter { dispositions.contains($0.disposition) }
            return Array(all.suffix(limit))
        }
    }

    /// Rewrite the log with only its most recent lines once it exceeds the size
    /// cap. Called on `queue` so it never races an append. The atomic write means a
    /// concurrent reader sees either the whole old file or the whole new one.
    private static func trimIfNeeded(_ url: URL) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > maxBytes,
              let content = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        let kept = keepingLast(keepWhenTrimming, of: content)
        try? Data(kept.utf8).write(to: url, options: .atomic)
    }

    /// The text of the last `n` non-empty lines, newline-terminated; the content
    /// unchanged when it already has `n` or fewer lines. Pure — unit-tested.
    static func keepingLast(_ n: Int, of content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > n else { return content }
        return lines.suffix(n).joined(separator: "\n") + "\n"
    }
}
