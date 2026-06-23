import ApplicationServices
import AppKit

/// Helpers around the Accessibility (AX) permission, which Koifish needs both to
/// read the focused text field and to run a keyboard CGEventTap.
enum AXPermissions {
    /// Whether this process is currently trusted for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Trigger the system prompt that offers to open System Settings and add the app.
    /// Returns the trust state at call time (the user may grant asynchronously).
    @discardableResult
    static func prompt() -> Bool {
        // Literal avoids referencing the imported `kAXTrustedCheckOptionPrompt`
        // global var, which Swift 6 flags as concurrency-unsafe shared state.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Open the Accessibility pane in System Settings directly.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
