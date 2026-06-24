import AppKit

/// Owns the app's long-lived controllers and wires the core loop together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private(set) var coordinator: Coordinator!
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("Openfish launching (v\(Bundle.main.shortVersion))")
        Log.info("On-device model: \(OnDeviceModel.status)")

        // Accessory apps have no menu bar by default, which means standard
        // editing shortcuts (⌘C/⌘V/⌘X/⌘A/⌘Z) don't work in text fields. Install
        // a minimal main menu so the key equivalents route to the focused field.
        installMainMenu()

        coordinator = Coordinator()

        statusItemController = StatusItemController(
            onGenerate: { [weak self] in self?.coordinator.triggerGeneration() },
            onDictate: { [weak self] in self?.coordinator.toggleDictation() },
            onToggleActivity: { [weak self] in self?.coordinator.toggleActivityWatching() },
            onSettings: { [weak self] in self?.showSettings() },
            onOpenProfile: { [weak self] in self?.coordinator.revealDataFolder() },
            onManageProfiles: { [weak self] in self?.showSettings(tab: .style) },
            onQuit: { NSApp.terminate(nil) }
        )

        coordinator.onRecordingStateChanged = { [weak self] recording in
            self?.statusItemController.setRecording(recording)
        }
        coordinator.onActivityStateChanged = { [weak self] watching in
            self?.statusItemController.setActivityWatching(watching)
        }
        coordinator.onThinkingStateChanged = { [weak self] thinking in
            self?.statusItemController.setThinking(thinking)
        }

        coordinator.start()

        // First-run: if Accessibility isn't granted yet, open settings (the
        // General tab leads with the permission banner).
        if !AXPermissions.isTrusted {
            showSettings(tab: .general)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App menu (not shown in the system bar for an accessory app, but its
        // key equivalents — e.g. ⌘Q, ⌘, — still fire).
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Openfish", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu — provides the responder-chain editing shortcuts.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    func showSettings(tab: SettingsTab = .general) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(coordinator: coordinator)
        }
        settingsWindowController?.show(tab: tab)
    }
}
