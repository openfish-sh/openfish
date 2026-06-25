import AppKit
import Carbon.HIToolbox

/// Synthesizes the keystrokes that place a reply into the focused field — paste
/// (⌘V) plus the Shift+← selection and Delete used to swap out the placeholder.
/// This is the universal insertion path: Accessibility text-setting silently fails
/// in web views and terminals, but synthesized keystrokes work everywhere.
///
/// We **paste** literal text (never type characters) so smart substitution /
/// autocorrect can't rewrite it on the way in.
enum KeyboardSynth {
    /// Gap between synthesized events so target apps don't drop/coalesce them.
    private static let gap: useconds_t = 9_000          // 9 ms
    /// Selection / delete keys are posted in a burst and are the most drop-prone —
    /// web views and Electron apps swallow them when they arrive too fast. Go slower.
    private static let deleteGap: useconds_t = 16_000   // 16 ms

    private static func post(_ keyCode: CGKeyCode, flags: CGEventFlags = [], gap g: useconds_t = gap) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        usleep(g)
        up?.post(tap: .cghidEventTap)
        usleep(g)
    }

    /// Put `text` on the pasteboard and synthesize ⌘V. Caller manages clipboard
    /// save/restore around a sequence of pastes.
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        post(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    /// Extend the selection left by `times` characters (Shift+←). Used to select a
    /// just-pasted placeholder so a following paste overwrites it in one edit — far
    /// more robust in web views than clearing it with a backspace burst.
    static func selectLeft(times: Int = 1) {
        for _ in 0..<max(0, times) { post(CGKeyCode(kVK_LeftArrow), flags: .maskShift, gap: deleteGap) }
    }

    /// Press Delete (backspace) `times` times. With a selection active, a single
    /// press clears the whole selection.
    static func backspace(times: Int = 1) {
        for _ in 0..<max(0, times) { post(CGKeyCode(kVK_Delete), gap: deleteGap) }
    }
}
