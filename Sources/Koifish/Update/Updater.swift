import AppKit
import Sparkle

/// Wraps Sparkle's standard updater: automatic background checks (per the
/// `SUEnableAutomaticChecks` Info.plist key) plus a manual "Check for Updates…"
/// action. The feed URL and the EdDSA public key live in Info.plist
/// (`SUFeedURL` / `SUPublicEDKey`); updates are verified against both that key and
/// the app's Developer ID before they install.
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    /// User-initiated check (shows Sparkle's UI: up-to-date, or an update prompt).
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
