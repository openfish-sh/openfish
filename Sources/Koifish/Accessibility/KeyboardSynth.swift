import AppKit
import Carbon.HIToolbox

/// Synthesizes the paste (⌘V) that inserts a reply into the focused field. This is
/// the universal insertion path: Accessibility text-setting silently fails in web
/// views and terminals, but a synthesized ⌘V works everywhere.
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
}
