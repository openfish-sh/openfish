import AppKit

/// Entry point. OpenFish is a menu-bar (accessory) app: no Dock icon, no main
/// window. We drive the AppKit lifecycle directly rather than using the SwiftUI
/// `App` protocol so we have full control over the status item, global event tap,
/// and activation policy.
@main
enum OpenFishApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        // NSApplication.delegate is a weak reference, so keep a strong one.
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        // .accessory = agent app: runs without a Dock icon or menu bar of its own.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Strong reference to the app delegate (NSApplication.delegate is weak).
    @MainActor private static var delegate: AppDelegate?
}
