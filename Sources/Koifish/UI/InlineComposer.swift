import AppKit

/// Direct-mode field feedback: drops a short, **static** placeholder into the
/// focused field while generating, then replaces it in place with the reply.
///
/// The "working" animation lives on the menu-bar fish (see `StatusItemController`),
/// NOT in the field. The field only ever holds one fixed, known string — so we
/// delete it by an exact, constant count. The old animated "Concocting…" loader
/// changed length over time and was cleared with a long backspace burst whose tail
/// drop-prone apps (iMessage, Slack, web views) swallowed, leaving ghost leading
/// letters ("Co…"). A fixed placeholder + a settle before the paste removes both
/// causes.
///
/// We **paste** the placeholder (never type it) so smart substitution can't rewrite
/// it — e.g. typed "..." would autocorrect to "…" and throw the character count off.
@MainActor
final class InlineComposer {
    private(set) var isActive = false
    private var placeholderLength = 0
    private var savedClipboard: String?
    /// The scheduled clipboard restore, kept so a superseding run can cancel it
    /// before it clobbers the saved original.
    private var pendingRestore: DispatchWorkItem?

    /// Static, un-animated placeholder. Fixed length → exact deletion count.
    private static let placeholder = "(hang on...)"

    func begin() {
        guard !isActive else { return }
        isActive = true
        // If a previous run's clipboard restore is still pending, the real clipboard
        // hasn't been put back yet — keep the original we already saved and cancel
        // that restore so it can't fire mid-run. Only sample the clipboard afresh
        // when nothing of ours is outstanding (otherwise we'd save our own placeholder).
        if let pending = pendingRestore {
            pending.cancel()
            pendingRestore = nil
        } else {
            savedClipboard = NSPasteboard.general.string(forType: .string)
        }
        KeyboardSynth.paste(Self.placeholder)
        placeholderLength = Self.placeholder.count
    }

    /// Replace the placeholder with the final reply and stop.
    func finish(with reply: String) { stop(replaceWith: reply) }

    /// Remove the placeholder (error/cancel) and stop.
    func clear() { stop(replaceWith: nil) }

    private func stop(replaceWith reply: String?) {
        guard isActive else { return }
        isActive = false

        if placeholderLength > 0 {
            KeyboardSynth.backspace(times: placeholderLength)
            // Let the target finish draining the deletes before ⌘V's Command
            // modifier arrives — posting the paste too soon can flush the tail of
            // the backspace burst, which is what used to leave leading letters.
            usleep(60_000)  // 60 ms
        }
        placeholderLength = 0
        if let reply, !reply.isEmpty {
            KeyboardSynth.paste(reply)
        }

        // Restore the user's clipboard once the paste has landed. Cancellable so a
        // superseding run can't clobber the saved original (see begin()).
        let saved = savedClipboard
        let restore = DispatchWorkItem { [weak self] in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
            self?.pendingRestore = nil
            self?.savedClipboard = nil
        }
        pendingRestore = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: restore)
    }
}
