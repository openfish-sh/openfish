import AppKit

/// Direct-mode field feedback, chosen per field so it's reliable everywhere:
///
/// * **Empty field** (a fresh reply box — the common case): paste the static
///   `(gone fishing...)` placeholder into the field, then swap it for the reply with
///   **⌘A + paste**. ⌘A is a single shortcut, honored even in web views (it's the
///   same kind of event as the ⌘V that already inserts the reply), so it overwrites
///   the lone placeholder in one shot — no fragile multi-key delete burst, which is
///   what web views drop and what stranded the reply inside the placeholder before.
/// * **Field already holds the user's draft**: ⌘A would select their text too, so we
///   never touch the field for feedback — we show the floating `(gone fishing...)`
///   cue (`FishingHUD`) instead and paste only the reply at the cursor.
///
/// We **paste** (never type) so smart substitution can't rewrite the text, and we
/// save/restore the user's clipboard around the pastes.
@MainActor
final class InlineComposer {
    private(set) var isActive = false
    /// Whether this run put the placeholder *in* the field (empty field) vs. used the
    /// floating cue (field already had the user's text).
    private var usePlaceholder = false
    private var savedClipboard: String?
    /// The scheduled clipboard restore, kept so a superseding run can cancel it
    /// before it clobbers the saved original.
    private var pendingRestore: DispatchWorkItem?

    private static let placeholder = "(gone fishing...)"

    /// Begin a run. `fieldEmpty` decides the feedback: in-field placeholder when the
    /// field is empty, floating cue when it already holds the user's draft.
    func begin(fieldEmpty: Bool) {
        guard !isActive else { return }
        isActive = true
        usePlaceholder = fieldEmpty

        // If a previous run's clipboard restore is still pending, the real clipboard
        // hasn't been put back yet — keep the original we already saved and cancel that
        // restore so it can't fire mid-run. Only sample afresh when nothing of ours is
        // outstanding (otherwise we'd save our own placeholder).
        if let pending = pendingRestore {
            pending.cancel()
            pendingRestore = nil
        } else {
            savedClipboard = NSPasteboard.general.string(forType: .string)
        }

        if usePlaceholder {
            KeyboardSynth.paste(Self.placeholder)
        } else {
            FishingHUD.shared.show()
        }
    }

    /// Replace the placeholder (or insert at the cursor) with the final reply and stop.
    func finish(with reply: String) { stop(insert: reply) }

    /// Stop without inserting (error / cancel), removing any placeholder we added.
    func clear() { stop(insert: nil) }

    private func stop(insert reply: String?) {
        guard isActive else { return }
        isActive = false

        if usePlaceholder {
            // The placeholder is the field's only content (it was empty), so select all
            // of it with ⌘A and overwrite in one shot.
            KeyboardSynth.selectAll()
            usleep(40_000)  // 40 ms — let the selection register before the overwrite
            if let reply, !reply.isEmpty {
                KeyboardSynth.paste(reply)          // paste replaces the selected placeholder
            } else {
                KeyboardSynth.backspace(times: 1)   // error / cancel: clear the selection
            }
        } else {
            FishingHUD.shared.hide()
            if let reply, !reply.isEmpty {
                KeyboardSynth.paste(reply)          // insert at the cursor
            }
        }
        usePlaceholder = false

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
