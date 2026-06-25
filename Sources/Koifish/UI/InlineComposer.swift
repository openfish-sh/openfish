import AppKit

/// Direct-mode insertion: paste the final reply into the focused field in a single
/// step, with **no in-field placeholder**. Progress is shown by a floating
/// `(gone fishing...)` cue beside the pointer (`FishingHUD`) and the menu-bar fish —
/// never as text in the field, which is touched exactly once, when the reply lands.
///
/// That single touch is the whole point. The previous design pasted a
/// `(gone fishing...)` placeholder and then deleted it with a burst of synthesized
/// backspaces before pasting the reply. Drop-prone targets — web views (LinkedIn,
/// x.com), Electron apps (Slack), terminals — silently swallow part of that
/// backspace burst, so the placeholder was left half-deleted and the reply landed
/// *inside* it: `(go` + reply + `ne fishing...)`. With no placeholder there is
/// nothing to delete, so nothing can be half-deleted: the field can only ever
/// receive the exact reply text, in every app.
///
/// We **paste** (never type) so smart substitution / autocorrect can't rewrite the
/// text, and we save/restore the user's clipboard around the paste.
@MainActor
final class InlineComposer {
    private(set) var isActive = false
    private var savedClipboard: String?
    /// The scheduled clipboard restore, kept so a superseding run can cancel it
    /// before it clobbers the saved original.
    private var pendingRestore: DispatchWorkItem?

    /// Begin a run: snapshot the clipboard so we can put it back after pasting the
    /// reply. Nothing is written to the field here.
    func begin() {
        guard !isActive else { return }
        isActive = true
        // If a previous run's clipboard restore is still pending, the real clipboard
        // hasn't been put back yet — keep the original we already saved and cancel
        // that restore so it can't fire mid-run. Only sample the clipboard afresh
        // when nothing of ours is outstanding (otherwise we'd save our own paste).
        if let pending = pendingRestore {
            pending.cancel()
            pendingRestore = nil
        } else {
            savedClipboard = NSPasteboard.general.string(forType: .string)
        }
        FishingHUD.shared.show()
    }

    /// Insert the final reply and stop.
    func finish(with reply: String) { stop(insert: reply) }

    /// Stop without inserting (error / cancel). Nothing was placed in the field, so
    /// there is nothing to undo.
    func clear() { stop(insert: nil) }

    private func stop(insert reply: String?) {
        guard isActive else { return }
        isActive = false

        FishingHUD.shared.hide()
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
