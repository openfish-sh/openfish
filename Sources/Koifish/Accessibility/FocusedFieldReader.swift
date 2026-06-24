import ApplicationServices
import AppKit

/// What we managed to read from the field the user is currently typing in.
/// `@unchecked Sendable`: the AX handle and `NSRunningApplication` aren't Sendable,
/// but they're only ever touched on the main thread (read here, used in inserts) —
/// the struct is passed to background tasks only to carry its value fields.
struct FocusedContext: @unchecked Sendable {
    /// Full text of the focused element (may be empty).
    var fieldText: String
    /// Currently selected text, if any.
    var selectedText: String
    /// Frontmost application name (e.g. "Mail", "Slack").
    var appName: String
    /// Focused window title, if available.
    var windowTitle: String
    /// The AX element we read from, kept so we can insert back into it.
    var element: AXUIElement?
    /// The app that was frontmost when we read — re-activated before inserting,
    /// since showing our own UI can steal focus.
    var targetApp: NSRunningApplication?
    /// Visible text of the surrounding window (the conversation/page being
    /// replied to), with a marker at the cursor. The key to relevant replies.
    var pageContext: String = ""
    /// Ancestor element names (outermost → innermost) — "which thread/field".
    var breadcrumb: [String] = []
    /// AX role of the focused element (e.g. "AXTextArea", "AXTextField").
    var focusedRole: String = ""

    var hasText: Bool { !fieldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasSelection: Bool { !selectedText.isEmpty }
}

/// Reads the focused text element of the frontmost app via the Accessibility API.
enum FocusedFieldReader {
    /// Defaults are generous because the common caller is the user pressing the
    /// hotkey — they're waiting on a reply, so a longer read to capture the full
    /// conversation is worth it. The automatic activity capture passes tight limits.
    static func read(maxElements: Int = 2500, budget: CFTimeInterval = 0.8) -> FocusedContext {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "the app"
        let systemWide = AXUIElementCreateSystemWide()
        // Cap how long any single AX message may block. These calls are synchronous
        // cross-process IPC on the main thread; a wedged target app must not be able
        // to hang us (and, via the main-run-loop event tap, system-wide input).
        AXUIElementSetMessagingTimeout(systemWide, 0.25)

        guard let focused = copyElement(systemWide, kAXFocusedUIElementAttribute) else {
            return FocusedContext(fieldText: "", selectedText: "", appName: appName, windowTitle: "", element: nil, targetApp: frontApp)
        }
        AXUIElementSetMessagingTimeout(focused, 0.25)

        let fieldText = copyString(focused, kAXValueAttribute) ?? ""
        let selectedText = copyString(focused, kAXSelectedTextAttribute) ?? ""
        let windowTitle = focusedWindowTitle(focused)
        let context = AXContext.gather(focused: focused, maxElements: maxElements, budget: budget)

        return FocusedContext(
            fieldText: fieldText,
            selectedText: selectedText,
            appName: appName,
            windowTitle: windowTitle,
            element: focused,
            targetApp: frontApp,
            pageContext: context.pageText,
            breadcrumb: context.breadcrumb,
            focusedRole: context.focusedRole
        )
    }

    // MARK: AX helpers

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let v = value else { return nil }
        // AXUIElement is a CFType; bridge by checking the type id.
        guard CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private static func focusedWindowTitle(_ element: AXUIElement) -> String {
        // Walk up to the containing window and read its title.
        if let window = copyElement(element, kAXWindowAttribute),
           let title = copyString(window, kAXTitleAttribute) {
            return title
        }
        return ""
    }
}
