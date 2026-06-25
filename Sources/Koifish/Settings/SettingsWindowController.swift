import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case style
}

/// Hosts the SwiftUI settings UI in a standard window. Because Koifish is an
/// accessory app, we explicitly activate and front the window when shown.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let coordinator: Coordinator
    private let selectedTab = SelectedTab()

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        // Size to show the full settings without scrolling where the display allows,
        // clamped to the visible screen so it never runs off a small one (the inner
        // ScrollView still handles any overflow). Resizable so the user can adjust.
        let desired = NSSize(width: 560, height: 900)
        let visible = NSScreen.main?.visibleFrame.size ?? desired
        let size = NSSize(width: min(desired.width, visible.width),
                          height: min(desired.height, visible.height))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Openfish"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        let root = SettingsView(coordinator: coordinator, selectedTab: selectedTab)
        window.contentView = NSHostingView(rootView: root)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(tab: SettingsTab) {
        selectedTab.tab = tab
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Small observable box so the controller can drive the SwiftUI tab selection.
@MainActor
final class SelectedTab: ObservableObject {
    @Published var tab: SettingsTab = .general
}
