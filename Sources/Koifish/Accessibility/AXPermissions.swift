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

    /// Quit and relaunch the app. A fresh launch is the reliable way to pick up a
    /// just-fixed Accessibility grant — after the user re-adds the app, macOS can
    /// keep handing the stale "not trusted" answer to the running process.
    @MainActor
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this instance to exit, then reopen the bundle.
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
