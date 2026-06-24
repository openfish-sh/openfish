import SwiftUI

struct SettingsView: View {
    let coordinator: Coordinator
    @ObservedObject var selectedTab: SelectedTab
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab.tab) {
                Text("General").tag(SettingsTab.general)
                Text("Style").tag(SettingsTab.style)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 14) {
                    switch selectedTab.tab {
                    case .general:
                        PermissionsCard()
                        ProviderConfigCard(settings: settings)
                        BehaviorCard(settings: settings, coordinator: coordinator)
                        VoiceCard(settings: settings)
                        MemoryCard(settings: settings, coordinator: coordinator)
                    case .style:
                        StyleCards(settings: settings)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(width: 560, height: 560)
        .background(VisualEffectBackground().ignoresSafeArea())
    }
}

// MARK: - Permissions (first thing the user sees)

/// One card for every permission Openfish uses, each with live status and a single
/// obvious action. Accessibility is required; Microphone is only for dictation.
private struct PermissionsCard: View {
    @State private var axTrusted = AXPermissions.isTrusted
    @State private var micState = MicPermission.state
    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    private var allSet: Bool { axTrusted }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Permissions").font(.headline)
                Spacer()
                if allSet {
                    Label("Ready", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }

            PermissionRow(
                title: "Accessibility",
                detail: "Read the field you're typing in, insert replies, and use the global hotkey.",
                required: true,
                granted: axTrusted,
                denied: false,
                primaryTitle: "Grant Access",
                primary: { AXPermissions.prompt() },
                openSettings: { AXPermissions.openSystemSettings() },
                // The grant is tied to the app's code signature, so after an update
                // macOS may still list Openfish as enabled while reporting it as not
                // trusted. Give the user the exact recovery + a one-click relaunch.
                recoveryHint: "Already enabled in the list but this still says it's not? That happens after an update. In System Settings ▸ Privacy & Security ▸ Accessibility, remove Openfish with “–”, add it back with “+” and switch it on — then:",
                onRelaunch: { AXPermissions.relaunch() }
            )

            Divider().opacity(0.3)

            PermissionRow(
                title: "Microphone",
                detail: "Only for voice dictation — not needed for text replies.",
                required: false,
                granted: micState == .granted,
                denied: micState == .denied,
                primaryTitle: "Allow Microphone",
                primary: { MicPermission.request() },
                openSettings: { MicPermission.openSystemSettings() }
            )
        }
        .glassCard()
        .onReceive(timer) { _ in
            axTrusted = AXPermissions.isTrusted
            micState = MicPermission.state
        }
    }
}

/// A single permission line: green check when granted, otherwise an explanation
/// and the one button that resolves it.
private struct PermissionRow: View {
    let title: String
    let detail: String
    let required: Bool
    let granted: Bool
    let denied: Bool
    let primaryTitle: String
    let primary: () -> Void
    let openSettings: () -> Void
    /// Extra guidance shown when the permission appears granted in System Settings
    /// but isn't recognized (e.g. after an update changes the code signature).
    var recoveryHint: String? = nil
    /// When set, shows a "Quit & Reopen" button — the reliable way to pick up a
    /// just-fixed grant.
    var onRelaunch: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: granted ? "checkmark.circle.fill" : (required ? "exclamationmark.circle.fill" : "circle"))
                    .foregroundStyle(granted ? .green : (required ? .orange : .secondary))
                Text(title).font(.subheadline).bold()
                if !required { Text("optional").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
            }
            Text(granted ? "Granted." : detail)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !granted {
                HStack {
                    // After a denial the system won't re-prompt, so go straight to Settings.
                    if denied {
                        Button("Open System Settings", action: openSettings).glassButton()
                    } else {
                        Button(primaryTitle, action: primary).glassButton()
                        Button("Open System Settings", action: openSettings).glassButton()
                    }
                }
                if let recoveryHint {
                    Text(recoveryHint)
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    if let onRelaunch {
                        Button("Quit & Reopen Openfish", action: onRelaunch).glassButton()
                    }
                }
            }
        }
    }
}

// MARK: - Provider + key + model, all on one card

private struct ProviderConfigCard: View {
    @ObservedObject var settings: Settings
    @State private var keyInput = ""
    @State private var savedFlash = false
    @State private var hasKey = false
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Provider").font(.headline)

            Picker("", selection: $settings.provider) {
                ForEach(ProviderKind.allCases) { Text($0.shortName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: settings.provider) { _, _ in refresh() }

            // Endpoint picker for the OpenAI-compatible provider.
            if settings.provider == .openAICompatible {
                endpointSection
                Divider().opacity(0.3)
            }

            // Contextual API key for the selected provider.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(settings.provider.displayName) API key").font(.subheadline).bold()
                    Spacer()
                    if let url = URL(string: settings.provider.keysURL), !settings.provider.keysURL.isEmpty {
                        Link("Get a key ↗", destination: url).font(.caption)
                    }
                }
                HStack {
                    SecureField(settings.provider.keyPlaceholder, text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .glassButton()
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Test Connection", action: testKey)
                    .glassButton()
                    .disabled(testing)
                statusLine
                if testing {
                    Label("Testing the connection…", systemImage: "ellipsis.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let testResult {
                    Label(testResult, systemImage: testOK ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .font(.caption).foregroundStyle(testOK ? .green : .red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider().opacity(0.3)

            // Model for the selected provider.
            HStack {
                Text("Model").font(.subheadline).bold()
                Spacer()
                modelPicker.labelsHidden().frame(maxWidth: 240)
            }
        }
        .glassCard()
        .onAppear(perform: refresh)
    }

    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Endpoint").font(.subheadline).bold()
                Spacer()
                Menu("Presets") {
                    ForEach(CompatiblePreset.all) { preset in
                        Button(preset.name) {
                            settings.customBaseURL = preset.baseURL
                            settings.customModel = preset.model
                        }
                    }
                }
                .frame(maxWidth: 110)
            }
            TextField("https://api.groq.com/openai/v1", text: $settings.customBaseURL)
                .textFieldStyle(.roundedBorder)
            Text("Any OpenAI-compatible API: Groq, OpenRouter, Gemini, Ollama, LM Studio… Use a preset or paste a base URL.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var modelPicker: some View {
        switch settings.provider {
        case .anthropic:
            Picker("Model", selection: $settings.anthropicModel) {
                ForEach(AIModels.anthropicChoices, id: \.self) { Text($0).tag($0) }
            }
        case .openai:
            Picker("Model", selection: $settings.openAIModel) {
                ForEach(AIModels.openAIChoices, id: \.self) { Text($0).tag($0) }
            }
        case .gemini:
            Picker("Model", selection: $settings.geminiModel) {
                ForEach(AIModels.geminiChoices, id: \.self) { Text($0).tag($0) }
            }
        case .openAICompatible:
            TextField("model id", text: $settings.customModel)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder private var statusLine: some View {
        if savedFlash {
            Label("Saved to Keychain", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        } else if hasKey {
            HStack(spacing: 8) {
                Label("Key saved in Keychain", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary).font(.caption)
                Button("Remove") { KeychainStore.deleteKey(for: settings.provider); refresh() }
                    .buttonStyle(.link).font(.caption)
            }
        } else if settings.provider.requiresKey {
            Label("No key yet — paste one above to start", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange).font(.caption)
        } else {
            Label("Optional — local endpoints (Ollama, LM Studio) need no key.", systemImage: "info.circle")
                .foregroundStyle(.secondary).font(.caption)
        }
    }

    private func refresh() {
        keyInput = ""
        savedFlash = false
        testResult = nil
        hasKey = KeychainStore.hasKey(for: settings.provider)
    }

    /// Make a tiny real request with the current key so a wrong/expired key (or a
    /// bad endpoint/model) is caught here, not silently at generation time.
    private func testKey() {
        testResult = nil
        testing = true
        let provider = settings.provider
        let typed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = typed.isEmpty ? (KeychainStore.key(for: provider) ?? "") : typed
        let baseURL = settings.activeBaseURL
        let model = settings.activeModel
        Task {
            let ai = AIProviderFactory.make(provider, baseURL: baseURL)
            let req = GenerationRequest(
                systemPrompt: "You are a connection test.",
                userPrompt: "Reply with the single word OK.",
                model: model, maxTokens: 16
            )
            do {
                _ = try await ai.complete(req, apiKey: key)
                testing = false; testOK = true; testResult = "Connection works ✓"
            } catch {
                testing = false; testOK = false
                testResult = (error as? AIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.setKey(trimmed, for: settings.provider)
        keyInput = ""
        hasKey = true
        savedFlash = true
    }
}

// MARK: - Behavior

private struct BehaviorCard: View {
    @ObservedObject var settings: Settings
    let coordinator: Coordinator

    /// Keys offered as triggers. Left ⌘/⌃/⇧ are omitted — they're heavily used by
    /// the system and apps, so tapping them alone is unreliable.
    private static let keyChoices: [ModifierKey] = [
        .rightOption, .leftOption, .rightCommand, .rightControl, .rightShift, .fn,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Behavior").font(.headline)
            Picker("After generating", selection: $settings.insertMode) {
                ForEach(InsertMode.allCases) { Text($0.displayName).tag($0) }
            }

            Divider().opacity(0.3)

            HStack {
                Text("Generate key (tap)").font(.subheadline).bold()
                Spacer()
                keyPicker(generateKey)
            }
            HStack {
                Text("Dictate key").font(.subheadline).bold()
                Spacer()
                Picker("", selection: dictateIsHold) {
                    Text("Tap").tag(false)
                    Text("Hold").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 116)
                keyPicker(dictateKey)
            }

            Text("Tap a modifier on its own to trigger (so ⌥e for accents still works). Dictation \u{201C}Tap\u{201D} toggles on/off; \u{201C}Hold\u{201D} records only while held. For Fn, set System Settings → Keyboard → \u{201C}Press 🌐 key to\u{201D} → Do Nothing.")
                .font(.caption).foregroundStyle(.secondary)
            if key(of: settings.generateHotkey, fallback: .rightOption) == key(of: settings.dictateHotkey, fallback: .fn) {
                Label("Generate and Dictate are on the same key, so Dictate is turned off. Pick different keys.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard()
    }

    private func keyPicker(_ selection: Binding<ModifierKey>) -> some View {
        Picker("", selection: selection) {
            ForEach(Self.keyChoices, id: \.self) { Text($0.displayName).tag($0) }
        }
        .labelsHidden()
        .frame(maxWidth: 150)
    }

    /// The configured key for a trigger (falling back if it's a raw chord).
    private func key(of trigger: HotkeyTrigger, fallback: ModifierKey) -> ModifierKey {
        switch trigger {
        case .modifierTap(let k), .modifierHold(let k): return k
        case .chord: return fallback
        }
    }

    private var generateKey: Binding<ModifierKey> {
        Binding(
            get: { key(of: settings.generateHotkey, fallback: .rightOption) },
            set: { settings.generateHotkey = .modifierTap($0); coordinator.reloadHotkeys() }
        )
    }

    private var dictateKey: Binding<ModifierKey> {
        Binding(
            get: { key(of: settings.dictateHotkey, fallback: .fn) },
            set: { newKey in
                let hold = dictateIsHold.wrappedValue
                settings.dictateHotkey = hold ? .modifierHold(newKey) : .modifierTap(newKey)
                coordinator.reloadHotkeys()
            }
        )
    }

    private var dictateIsHold: Binding<Bool> {
        Binding(
            get: { if case .modifierHold = settings.dictateHotkey { return true }; return false },
            set: { hold in
                let k = key(of: settings.dictateHotkey, fallback: .fn)
                settings.dictateHotkey = hold ? .modifierHold(k) : .modifierTap(k)
                coordinator.reloadHotkeys()
            }
        )
    }
}

// MARK: - Voice / dictation

private struct VoiceCard: View {
    @ObservedObject var settings: Settings

    private var sourceLabel: String {
        settings.provider == .openAICompatible
            ? "your Custom endpoint (\(settings.customBaseURL.isEmpty ? "set a base URL" : settings.customBaseURL))"
            : "OpenAI Whisper (uses your OpenAI key)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice").font(.headline)
            // Dictation transcribes through OpenAI Whisper unless a Custom endpoint is
            // active, so Claude/Gemini users need an OpenAI key specifically. Surface
            // that here instead of failing silently the first time they dictate.
            if settings.provider != .openAICompatible, !KeychainStore.hasKey(for: .openai) {
                Label("Dictation transcribes via OpenAI — add an OpenAI key (switch the provider above to OpenAI to paste one).", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("Transcription model").font(.subheadline).bold()
                Spacer()
                TextField(settings.provider == .openAICompatible ? "whisper-large-v3" : "whisper-1",
                          text: $settings.voiceModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            HStack {
                Text("Language").font(.subheadline).bold()
                Spacer()
                TextField("auto-detect", text: $settings.voiceLanguage)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            Text("Transcribes through \(sourceLabel). Leave model blank for the default. Language is auto-detected unless you set a code (e.g. en, sv, de).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .glassCard()
    }
}

// MARK: - Activity memory (cross-window context)

private struct MemoryCard: View {
    @ObservedObject var settings: Settings
    let coordinator: Coordinator
    @State private var entities: [EntityMention] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity memory").font(.headline)
            Toggle("Watch recent windows for cross-window context", isOn: Binding(
                get: { settings.activityMemoryEnabled },
                set: { coordinator.setActivityWatching($0); refresh() }
            ))
            Text("Off by default. When on, Openfish keeps the text of windows you recently visited so a reply can reference something from another app. Text only — never screenshots — kept in memory only, never written to disk, and cleared the moment you turn this off. Openfish's own windows and password fields are skipped.")
                .font(.caption).foregroundStyle(.secondary)

            if settings.activityMemoryEnabled {
                Divider().opacity(0.3)
                HStack {
                    Text("People & organizations noticed").font(.subheadline).bold()
                    Spacer()
                    Button("Refresh", action: refresh).glassButton()
                }
                if entities.isEmpty {
                    Text("Nothing yet — switch between a few windows that name real people or companies, then Refresh. Extracted on-device (Apple's NaturalLanguage); it leans on capitalization, so it catches well-formed text better than lowercase chat.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(entities.prefix(12), id: \.entity) { mention in
                        HStack(spacing: 6) {
                            Text(mention.entity.name).font(.callout)
                            Text(mention.entity.kind.label).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("×\(mention.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .glassCard()
        .onAppear(perform: refresh)
    }

    private func refresh() { entities = coordinator.recentEntities() }
}

// MARK: - Style tab

private struct StyleCards: View {
    @ObservedObject var settings: Settings
    @ObservedObject private var profiles = ProfileStore.shared
    @State private var selectedID: UUID = ProfileStore.shared.activeID
    @State private var learned = StyleProfile()
    @State private var note = ""

    /// The profile currently being edited (falls back to active if it vanishes).
    private var selected: Profile {
        profiles.profiles.first { $0.id == selectedID } ?? profiles.active
    }

    var body: some View {
        VStack(spacing: 14) {
            profilesCard
            aboutYouCard
            voiceCard
            learnedStyleCard
        }
        .onAppear(perform: reloadLearned)
        .onChange(of: selectedID) { _, _ in note = ""; reloadLearned() }
    }

    private var profilesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profiles").font(.headline)
            Text("Separate personalities — e.g. Personal, Work — Sales, Internal comms. Each learns its own voice. Switch the active one from the menu-bar fish; edit any of them here.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Editing", selection: $selectedID) {
                ForEach(profiles.profiles) { p in
                    Text(p.id == profiles.activeID ? "\(p.name) — active" : p.name).tag(p.id)
                }
            }.labelsHidden()
            TextField("Profile name", text: nameBinding).textFieldStyle(.roundedBorder)
            HStack {
                Button(selectedID == profiles.activeID ? "Active" : "Make active") { profiles.setActive(selectedID) }
                    .glassButton().disabled(selectedID == profiles.activeID)
                Button("New") { selectedID = profiles.add(name: "New profile").id }.glassButton()
                Button("Duplicate") { if let p = profiles.duplicate(selectedID) { selectedID = p.id } }.glassButton()
                Button("Delete") { profiles.delete(selectedID); selectedID = profiles.activeID }
                    .glassButton().disabled(profiles.profiles.count <= 1)
            }
        }
        .glassCard()
    }

    private var aboutYouCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About you — \(selected.name)").font(.headline)
            Text("Standing facts for this profile — your role, the people and projects involved, how you like things handled. Folded into every reply in this profile. Stays on your Mac.")
                .font(.caption).foregroundStyle(.secondary)
            editor(briefBinding)
        }
        .glassCard()
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your voice — \(selected.name)").font(.headline)
            Toggle("Learn my style from accepted replies", isOn: $settings.learningEnabled)
            Text("Optional: describe this voice, or paste a couple of example messages. Openfish refines it automatically as you accept replies in this profile.")
                .font(.caption).foregroundStyle(.secondary)
            editor(seedBinding)
        }
        .glassCard()
    }

    private var learnedStyleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Learned style — \(selected.name)").font(.headline)
            if learned.description.isEmpty {
                Text("Nothing learned yet — accept a few replies in this profile and Openfish will build one.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView { Text(learned.description).font(.callout).textSelection(.enabled) }
                    .frame(maxHeight: 120)
                Text("Based on \(learned.sampleCount) sample(s).").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Refresh now") {
                    let id = selectedID
                    let dir = AppPaths.profileDir(id)
                    // Only reflect the result if the user hasn't switched profiles meanwhile.
                    Task { await Personalizer.refresh(in: dir); if selectedID == id { reloadLearned(); note = "Refreshed." } }
                }.glassButton()
                Button("Forget learned style") {
                    StyleProfile().save(in: AppPaths.profileDir(selectedID)); reloadLearned(); note = "Cleared."
                }.glassButton()
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .glassCard()
    }

    private func editor(_ text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(.body)
            .frame(minHeight: 80)
            .scrollContentBackground(.hidden)
            .padding(6)
            // `.primary` adapts to light/dark; a hardcoded tint vanishes on one of them.
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var nameBinding: Binding<String> {
        Binding(get: { selected.name }, set: { profiles.rename(selectedID, to: $0) })
    }
    private var briefBinding: Binding<String> {
        Binding(get: { selected.brief }, set: { profiles.setBrief(selectedID, $0) })
    }
    private var seedBinding: Binding<String> {
        Binding(get: { selected.styleSeed }, set: { profiles.setStyleSeed(selectedID, $0) })
    }

    private func reloadLearned() {
        learned = StyleProfile.load(in: AppPaths.profileDir(selectedID))
    }
}
