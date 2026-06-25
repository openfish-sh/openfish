import AppKit
import Carbon.HIToolbox

/// Synthesizes the keystrokes that place a reply into the focused field — paste
/// (⌘V), select-all (⌘A), and Delete. This is the universal insertion path:
/// Accessibility text-setting silently fails in web views and terminals, but
/// synthesized ⌘-shortcuts work everywhere a paste does.
///
/// We **paste** literal text (never type characters) so smart substitution /
/// autocorrect can't rewrite it on the way in.
enum KeyboardSynth {
    /// Gap between synthesized events so target apps don't drop/coalesce them.
    private static let gap: useconds_t = 9_000          // 9 ms

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

    /// Select all content in the focused field (⌘A) — a single shortcut honored even
    /// in web views (unlike a multi-key selection/delete burst), so a following paste
    /// can overwrite a known placeholder in one shot.
    static func selectAll() {
        post(CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
    }

    /// Press Delete (backspace) `times` times. With a selection active, one press
    /// clears the whole selection.
    static func backspace(times: Int = 1) {
        for _ in 0..<max(0, times) { post(CGKeyCode(kVK_Delete)) }
    }
}
