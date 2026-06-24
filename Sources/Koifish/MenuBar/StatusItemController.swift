import AppKit

/// The menu-bar presence: a status item with a dropdown menu. Pure UI — all
/// actions are delivered to the owner via the closures passed at init.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onGenerate: () -> Void
    private let onDictate: () -> Void
    private let onToggleActivity: () -> Void
    private let onSettings: () -> Void
    private let onOpenProfile: () -> Void
    private let onManageProfiles: () -> Void
    private let onQuit: () -> Void

    private var activityItem: NSMenuItem?
    private var profileSubmenu: NSMenu?
    private var recording = false
    private var watching = false
    private var thinking = false
    private var pulseTask: Task<Void, Never>?

    init(
        onGenerate: @escaping () -> Void,
        onDictate: @escaping () -> Void,
        onToggleActivity: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onOpenProfile: @escaping () -> Void,
        onManageProfiles: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onGenerate = onGenerate
        self.onDictate = onDictate
        self.onToggleActivity = onToggleActivity
        self.onSettings = onSettings
        self.onOpenProfile = onOpenProfile
        self.onManageProfiles = onManageProfiles
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.menu = buildMenu()
        updateAppearance()
    }

    /// Reflect hold-to-talk recording state in the menu-bar icon.
    func setRecording(_ recording: Bool) {
        self.recording = recording
        updateAppearance()
    }

    /// Reflect activity-watching state in the icon and the menu checkmark.
    func setActivityWatching(_ watching: Bool) {
        self.watching = watching
        activityItem?.state = watching ? .on : .off
        updateAppearance()
    }

    /// Gently pulse the menu-bar fish's opacity while a reply is generating — the
    /// working indicator, now that the field no longer shows an animated placeholder.
    func setThinking(_ thinking: Bool) {
        guard self.thinking != thinking else { return }
        self.thinking = thinking
        thinking ? startPulse() : stopPulse()
    }

    private func startPulse() {
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            var alpha = 1.0
            var rising = false
            while !Task.isCancelled {
                alpha += rising ? 0.07 : -0.07
                if alpha <= 0.3 { alpha = 0.3; rising = true }
                if alpha >= 1.0 { alpha = 1.0; rising = false }
                // A momentarily-nil button just skips a frame — never break the
                // loop, or the pulse would stay stuck on with no way to restart it.
                self?.statusItem.button?.alphaValue = alpha
                try? await Task.sleep(for: .milliseconds(45))
            }
        }
    }

    private func stopPulse() {
        pulseTask?.cancel()
        pulseTask = nil
        statusItem.button?.alphaValue = 1.0
    }

    /// Icon + tooltip from current state. Recording wins over watching over idle.
    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        let image: NSImage?
        let tip: String
        if recording {
            // Keep a distinct glyph for the active "listening" state.
            image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Openfish — listening")
            image?.isTemplate = true
            tip = "Openfish — listening…"
        } else if watching {
            image = MenuBarIcon.fish
            tip = "Openfish — watching activity"
        } else {
            image = MenuBarIcon.fish
            tip = "Openfish — \(ProfileStore.shared.active.name)"
        }
        button.image = image
        button.toolTip = tip
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let generate = NSMenuItem(title: "Generate Reply", action: #selector(generateAction), keyEquivalent: "")
        generate.target = self
        menu.addItem(generate)

        let dictate = NSMenuItem(title: "Dictate", action: #selector(dictateAction), keyEquivalent: "")
        dictate.target = self
        menu.addItem(dictate)

        menu.addItem(.separator())

        let profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        profileItem.submenu = submenu
        profileSubmenu = submenu
        menu.addItem(profileItem)
        rebuildProfileSubmenu()

        menu.addItem(.separator())

        let activity = NSMenuItem(title: "Watch Activity (cross-window memory)", action: #selector(toggleActivityAction), keyEquivalent: "")
        activity.target = self
        activity.state = watching ? .on : .off
        menu.addItem(activity)
        activityItem = activity

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let profile = NSMenuItem(title: "Open Data Folder", action: #selector(openProfileAction), keyEquivalent: "")
        profile.target = self
        menu.addItem(profile)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Openfish", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func generateAction() { onGenerate() }
    @objc private func dictateAction() { onDictate() }
    @objc private func toggleActivityAction() { onToggleActivity() }
    @objc private func settingsAction() { onSettings() }
    @objc private func openProfileAction() { onOpenProfile() }
    @objc private func quitAction() { onQuit() }

    // MARK: Profiles

    /// The main menu carries this delegate; refresh the dynamic profile list each
    /// time the menu opens so it reflects adds/renames/active changes.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildProfileSubmenu()
    }

    private func rebuildProfileSubmenu() {
        guard let submenu = profileSubmenu else { return }
        submenu.removeAllItems()
        let store = ProfileStore.shared
        for profile in store.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(selectProfileAction(_:)), keyEquivalent: "")
            item.target = self
            item.state = profile.id == store.activeID ? .on : .off
            item.representedObject = profile.id
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let manage = NSMenuItem(title: "Manage Profiles…", action: #selector(manageProfilesAction), keyEquivalent: "")
        manage.target = self
        submenu.addItem(manage)
    }

    @objc private func selectProfileAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        ProfileStore.shared.setActive(id)
        updateAppearance()
    }

    @objc private func manageProfilesAction() { onManageProfiles() }
}
