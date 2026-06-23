import AppKit

/// Inserts generated text into the focused field of whatever app is frontmost.
/// Uses a clipboard-preserving synthesized paste — the one method that works
/// universally (native apps, web views, terminals). Accessibility text-setting
/// is deliberately not used: it silently no-ops in Chrome/Safari/terminals.
enum TextInserter {
    static func insert(_ text: String, into context: FocusedContext) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        KeyboardSynth.paste(text)
        Log.debug("insert: synthesized ⌘V (\(text.count) chars)")

        // Restore the user's previous clipboard once the paste has landed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
        }
    }
}
