import Foundation

/// Append-only JSONL log of interactions. One JSON object per line so it stays
/// human-readable and cheap to append without rewriting the whole file.
enum InteractionLog {
    private static let queue = DispatchQueue(label: "sh.koifish.interactionlog")

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
        }
    }

    /// Read the most recent `limit` interactions matching `dispositions`.
    static func recent(limit: Int, dispositions: Set<Interaction.Disposition>) -> [Interaction] {
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
