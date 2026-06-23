import Foundation

/// Standing facts the user has written about themselves — their role, the
/// projects/people/tools they deal with, and how they like things handled.
///
/// Where `StyleProfile` learns *how* the user writes, the brief is *what the
/// model should know* about them, authored by the user and folded into every
/// reply as background. Plain text, user-owned, edited in Settings; it only
/// leaves the Mac inside the replies the user generates.
///
/// This is OpenFish's own notion — not tied to any earlier project's idea of an
/// identity file — so it carries its own name and prompt wording.
struct UserBrief {
    var text: String

    init(_ text: String) { self.text = text }

    /// The trimmed brief, or nil when the user hasn't written one.
    var content: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Upper bound on how much of the brief we fold into a prompt, so a pathologically
    /// long entry can't dominate the context window or balloon token cost.
    static let maxPromptChars = 4000

    /// The block to fold into the system prompt, or "" when there's nothing to add.
    var promptBlock: String {
        guard let content else { return "" }
        let bounded = content.count > Self.maxPromptChars
            ? String(content.prefix(Self.maxPromptChars)) + "…"
            : content
        return """
        What the user has told you about themselves and their world. Treat it as \
        standing background: lean on it only where it actually bears on this reply, \
        and never paste it in wholesale or mention that you have it.
        \"\"\"
        \(bounded)
        \"\"\"
        """
    }
}
