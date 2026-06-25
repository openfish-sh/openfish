import AppKit

/// Direct-mode insertion: paste the final reply into the focused field in a single
/// step, with **no in-field placeholder**. Progress is shown only by the floating
/// `(gone fishing...)` cue beside the pointer (`FishingHUD`) and the menu-bar fish —
/// never as text in the field, which is touched exactly once, when the reply lands.
///
/// That single touch is the whole point. Anything we put *into* a field has to be
/// taken back out, and web views (LinkedIn, x.com) drop the synthesized keystrokes
/// that removal needs — which left placeholders half-deleted with the reply lodged
/// inside them. With nothing in the field to remove, nothing can go wrong: the field
/// can only ever receive the exact reply text, in every app.
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

    /// Begin a run: snapshot the clipboard (we reuse it to paste the reply) and show
    /// the floating cue. Nothing is written to the field here.
    func begin() {
        guard !isActive else { return }
        isActive = true
        // If a previous run's clipboard restore is still pending, the real clipboard
        // hasn't been put back yet — keep the original we already saved and cancel
        // that restore so it can't fire mid-run. Only sample afresh when nothing of
        // ours is outstanding (otherwise we'd save our own paste).
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
