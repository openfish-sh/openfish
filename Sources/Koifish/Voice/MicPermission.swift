import AVFoundation
import AppKit

/// Helpers around the Microphone (TCC) permission, used only for voice dictation.
/// Mirrors `AXPermissions` so the settings UI can treat both the same way.
enum MicPermission {
    enum State { case granted, denied, notRequested }

    static var state: State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notRequested
        }
    }

    /// Trigger the system prompt (only fires when not yet decided). Safe to call
    /// from the main thread; the actual request runs in a Task.
    static func request() {
        Task { _ = await AudioRecorder.requestPermission() }
    }

    /// Open the Microphone pane in System Settings (for re-enabling after denial).
    @MainActor
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
