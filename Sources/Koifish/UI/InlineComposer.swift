import AppKit

/// Direct-mode field feedback: pastes a short, static `(gone fishing...)` placeholder
/// into the focused field while generating, then swaps it for the reply in place.
///
/// The working *animation* lives on the menu-bar fish (see `StatusItemController`);
/// the field just holds a fixed, known string so you can see where the reply will
/// land. When the reply arrives we **select** the placeholder (Shift+←) and paste the
/// reply *over the selection* — one atomic overwrite.
///
/// The old design deleted the placeholder with a burst of backspaces first, but web
/// views (LinkedIn, x.com) and Electron apps silently swallow part of that burst,
/// which left the placeholder half-deleted with the reply lodged inside it
/// (`(go` + reply + `ne fishing...)`). Overwriting a selection can't interleave:
/// the worst a dropped Shift+← can do is leave a small *visible* scrap, never a
/// hidden scramble.
///
/// We **paste** (never type) so smart substitution can't rewrite the text, and we
/// save/restore the user's clipboard around the pastes.
@MainActor
final class InlineComposer {
    private(set) var isActive = false
    private var placeholderLength = 0
    private var savedClipboard: String?
    /// The scheduled clipboard restore, kept so a superseding run can cancel it
    /// before it clobbers the saved original.
    private var pendingRestore: DispatchWorkItem?

    /// Static, un-animated placeholder — a fixed, known string to select and overwrite.
    private static let placeholder = "(gone fishing...)"

    func begin() {
        guard !isActive else { return }
        isActive = true
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
        KeyboardSynth.paste(Self.placeholder)
        placeholderLength = Self.placeholder.count
    }

    /// Replace the placeholder with the final reply and stop.
    func finish(with reply: String) { stop(replaceWith: reply) }

    /// Remove the placeholder (error / cancel) and stop.
    func clear() { stop(replaceWith: nil) }

    private func stop(replaceWith reply: String?) {
        guard isActive else { return }
        isActive = false

        // Select the placeholder, then overwrite it in one edit (see the type comment).
        if placeholderLength > 0 {
            KeyboardSynth.selectLeft(times: placeholderLength)
            usleep(60_000)  // 60 ms — let the selection settle before the overwrite
        }
        if let reply, !reply.isEmpty {
            KeyboardSynth.paste(reply)          // paste replaces the selected placeholder
        } else if placeholderLength > 0 {
            KeyboardSynth.backspace(times: 1)   // error / cancel: one Delete clears the selection
        }
        placeholderLength = 0

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
