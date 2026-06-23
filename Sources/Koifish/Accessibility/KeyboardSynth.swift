import AppKit
import Carbon.HIToolbox

/// Synthesizes keyboard input that every app understands — paste (⌘V) and
/// backspace. This is the universal insertion path: Accessibility text-setting
/// silently fails in web views and terminals, but synthesized keystrokes work
/// everywhere.
///
/// We only ever **paste** literal text (never type characters), so smart
/// substitution / autocorrect can't rewrite it — important for the dot loader,
/// where typed "..." would become a single "…" and desync the character count.
enum KeyboardSynth {
    /// Gap between synthesized events so target apps don't drop/coalesce them.
    private static let gap: useconds_t = 9_000          // 9 ms
    /// Backspaces are posted in a tight burst and are the most drop-prone — web
    /// views / Electron apps (Slack, browsers) silently swallow them when they
    /// arrive too fast, which left ghost letters of the loader word. Go slower.
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

    static func backspace(times: Int = 1) {
        for _ in 0..<max(0, times) { post(CGKeyCode(kVK_Delete), gap: deleteGap) }
    }
}
