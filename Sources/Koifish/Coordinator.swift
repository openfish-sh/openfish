import AppKit

/// Central orchestrator: owns the hotkey tap and the reply overlay, and runs the
/// core loop — read focused context → generate in the user's voice → let the user
/// accept/edit → insert → record the interaction for style learning.
@MainActor
final class Coordinator {
    private let hotkeys = HotkeyManager()
    private let overlay = ReplyOverlayController()
    private let inline = InlineComposer()
    private let memory = MemoryStore()
    private let recorder = AudioRecorder()
    private let activity = ActivityRecorder()

    private var context = FocusedContext(fieldText: "", selectedText: "", appName: "", windowTitle: "", element: nil, targetApp: nil)
    private var dictationContext = FocusedContext(fieldText: "", selectedText: "", appName: "", windowTitle: "", element: nil, targetApp: nil)
    private var generationTask: Task<Void, Never>?
    private var directGeneration = 0
    private var overlayGeneration = 0
    /// The profile active when the current overlay generation started, so an
    /// accept/reject records against it even if the user switches profile mid-review.
    private var overlayProfileID: UUID?
    private var dictationSession = 0
    private var lastGenerated = ""

    /// Set by AppDelegate to reflect dictation/activity state in the menu-bar icon.
    var onRecordingStateChanged: @MainActor (Bool) -> Void = { _ in }
    var onActivityStateChanged: @MainActor (Bool) -> Void = { _ in }
    /// Reflect "generating a reply" in the menu-bar fish (the working indicator).
    var onThinkingStateChanged: @MainActor (Bool) -> Void = { _ in }

    func start() {
        hotkeys.onGenerate = { [weak self] in self?.triggerGeneration() }
        hotkeys.onDictateToggle = { [weak self] in self?.toggleDictation() }
        hotkeys.onDictateStart = { [weak self] in self?.startDictation() }
        hotkeys.onDictateStop = { [weak self] in self?.stopDictation() }

        overlay.onAccept = { [weak self] text in self?.accept(text) }
        overlay.onRegenerate = { [weak self] in self?.regenerate() }
        overlay.onCancel = { [weak self] in self?.cancel() }

        activity.onStateChanged = { [weak self] on in self?.onActivityStateChanged(on) }
        activity.setWatching(Settings.shared.activityMemoryEnabled)

        if AXPermissions.isTrusted {
            hotkeys.start()
        } else {
            Log.info("Accessibility not yet granted — polling until permission is given.")
            waitForAccessibility()
        }
    }

    /// Re-install the hotkey tap so a changed trigger takes effect immediately,
    /// without relaunching. Called from Settings when the user rebinds a key.
    func reloadHotkeys() {
        permissionTask?.cancel()
        permissionTask = nil
        hotkeys.stop()
        if AXPermissions.isTrusted {
            hotkeys.start()
        } else {
            waitForAccessibility()
        }
    }

    private var permissionTask: Task<Void, Never>?

    /// Poll for Accessibility being granted, then install the tap once and stop.
    private func waitForAccessibility() {
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if AXPermissions.isTrusted {
                    self.hotkeys.start()
                    self.permissionTask = nil
                    return
                }
            }
        }
    }

    // MARK: Generate flow

    func triggerGeneration() {
        guard AXPermissions.isTrusted else {
            AXPermissions.prompt()
            return
        }
        context = FocusedFieldReader.read()
        guard context.element != nil else {
            Toast.shared.show("Put your cursor in a text field first.")
            return
        }
        Log.debug("triggerGeneration: app=\(context.appName) pageContext=\(context.pageContext.count) chars breadcrumb=\(context.breadcrumb.joined(separator: ">")) field=\(context.fieldText.count) mode=\(Settings.shared.insertMode.rawValue) provider=\(Settings.shared.provider.rawValue)")
        switch Settings.shared.insertMode {
        case .direct: runGenerationDirect()
        case .overlay: runGenerationOverlay(showOverlayFirst: true)
        }
    }

    private func regenerate() {
        runGenerationOverlay(showOverlayFirst: false)
    }

    /// A user-facing message if the active provider isn't usable yet, else nil.
    private func configProblem() -> String? {
        let s = Settings.shared
        switch s.provider {
        case .openAICompatible:
            if s.activeBaseURL == nil {
                return "Enter a valid endpoint URL in Settings (e.g. a Groq or Ollama base URL)."
            }
            if s.customModel.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Enter a model id in Settings (e.g. llama-3.3-70b-versatile)."
            }
            return nil  // key optional for local endpoints
        case .anthropic, .openai, .gemini:
            return KeychainStore.hasKey(for: s.provider) ? nil : AIError.missingAPIKey(s.provider).localizedDescription
        }
    }

    /// Build the provider + key + request for the current context (config already
    /// validated). Returns the active profile's id from the *same* snapshot used to
    /// build the prompt, so the interaction is recorded against the voice it was
    /// written in even if the user switches profile mid-generation.
    private func makeRequest() -> (provider: ProviderKind, key: String, request: GenerationRequest, profileID: UUID) {
        let settings = Settings.shared
        let profile = ProfileStore.shared.active
        let key = KeychainStore.key(for: settings.provider) ?? ""
        let style = memory.styleDescription(for: profile)
        let recentActivity = activity.recentDigest(excludingApp: context.appName, excludingWindow: context.windowTitle)
        let request = PromptBuilder.build(context: context, styleDescription: style,
                                          model: settings.activeModel, recentActivity: recentActivity,
                                          userBrief: profile.brief, selfName: settings.effectiveSelfName,
                                          selfAliases: settings.selfAliasList)
        return (settings.provider, key, request, profile.id)
    }

    // MARK: Activity memory (opt-in cross-window context)

    func setActivityWatching(_ on: Bool) {
        Settings.shared.activityMemoryEnabled = on
        activity.setWatching(on)
    }

    /// People/places/orgs noticed across the recent activity buffer (on-device,
    /// empty unless watching). Seed of a future entity index.
    func recentEntities() -> [EntityMention] { activity.recentEntities() }

    func toggleActivityWatching() {
        setActivityWatching(!Settings.shared.activityMemoryEnabled)
    }

    // MARK: Direct mode — in-field placeholder (empty field) or floating cue, then the reply

    private func runGenerationDirect() {
        if let problem = configProblem() { Toast.shared.show(problem); return }
        let (provider, key, request, profileID) = makeRequest()
        // Cancel any in-flight run before starting fresh.
        generationTask?.cancel()
        inline.clear()
        inline.begin(fieldEmpty: !context.hasText)
        onThinkingStateChanged(true)
        Log.debug("direct: generation started")

        let ai = AIProviderFactory.make(provider, baseURL: Settings.shared.activeBaseURL)
        let ctx = context
        directGeneration &+= 1
        let gen = directGeneration

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let full = try await ai.complete(request, apiKey: key)
                try Task.checkCancellation()
                Log.debug("direct: generation ok, \(full.count) chars")
                // Only the latest direct generation may touch the field or be recorded.
                guard self.directGeneration == gen else { return }
                self.inline.finish(with: full)
                self.onThinkingStateChanged(false)
                self.memory.record(profileID: profileID, context: ctx, generated: full, final: full, disposition: .accepted)
                self.noteValueMoment()
            } catch is CancellationError {
                if self.directGeneration == gen { self.inline.clear(); self.onThinkingStateChanged(false) }
            } catch {
                Log.error("generation failed: \(error.localizedDescription)")
                guard self.directGeneration == gen else { return }
                self.inline.clear()
                self.onThinkingStateChanged(false)
                Toast.shared.show((error as? AIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    // MARK: Overlay mode — review before inserting

    private func runGenerationOverlay(showOverlayFirst: Bool) {
        if let problem = configProblem() {
            overlay.show(contextSummary: summary())
            overlay.showError(problem)
            return
        }
        let (provider, key, request, profileID) = makeRequest()
        let ai = AIProviderFactory.make(provider, baseURL: Settings.shared.activeBaseURL)

        generationTask?.cancel()
        lastGenerated = ""
        overlayProfileID = profileID
        overlayGeneration &+= 1
        let gen = overlayGeneration
        if showOverlayFirst { overlay.show(contextSummary: summary()) }
        else { overlay.model.text = ""; overlay.model.isStreaming = true }

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                var full = ""
                for try await delta in ai.stream(request, apiKey: key) {
                    try Task.checkCancellation()
                    // A newer run owns the overlay now — drop this one's deltas.
                    guard self.overlayGeneration == gen else { return }
                    full += delta
                    self.overlay.appendDelta(delta)
                }
                try Task.checkCancellation()
                guard self.overlayGeneration == gen else { return }
                self.lastGenerated = full
                self.overlay.finishStreaming()
            } catch is CancellationError {
                // user cancelled — overlay already hidden
            } catch {
                Log.error("generation failed: \(error.localizedDescription)")
                guard self.overlayGeneration == gen else { return }
                self.overlay.showError((error as? AIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func accept(_ text: String) {
        generationTask?.cancel()
        overlay.hide()
        let ctx = context
        ctx.targetApp?.activate()

        // Give the target app a beat to come frontmost before inserting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            TextInserter.insert(text, into: ctx)
        }

        // Record for style learning: edited if the user changed the draft.
        let disposition: Interaction.Disposition = (text == lastGenerated) ? .accepted : .edited
        memory.record(profileID: overlayProfileID ?? ProfileStore.shared.activeID,
                      context: ctx, generated: lastGenerated, final: text, disposition: disposition)
        noteValueMoment()
    }

    /// Count a successfully accepted reply and — if the app has earned its place and
    /// the moment is right — show the one-shot support nudge a beat later, so it
    /// never blocks or covers the insert the user just made.
    private func noteValueMoment() {
        SupportStore.shared.recordValueMoment()
        guard SupportStore.shared.shouldNudge else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            SupportNudge.shared.show()
        }
    }

    private func cancel() {
        generationTask?.cancel()
        if !lastGenerated.isEmpty {
            memory.record(profileID: overlayProfileID ?? ProfileStore.shared.activeID,
                          context: context, generated: lastGenerated, final: "", disposition: .rejected)
        }
        overlay.hide()
    }

    private func summary() -> String {
        var s = context.appName
        if !context.windowTitle.isEmpty { s += " — \(context.windowTitle)" }
        return s
    }

    // MARK: Dictation

    /// Tap-to-start / tap-to-stop.
    func toggleDictation() {
        if recorder.isRecording { stopDictation() } else { startDictation() }
    }

    private func startDictation() {
        guard AXPermissions.isTrusted else { AXPermissions.prompt(); return }
        guard !recorder.isRecording else { return }
        dictationContext = FocusedFieldReader.read()
        let dictate = Settings.shared.dictateHotkey
        let hint: String
        if case .modifierHold(let key) = dictate {
            hint = "Listening… release \(key.displayName) to stop"
        } else {
            hint = "Listening… \(dictate.displayString) to stop"
        }
        Task { [weak self] in
            let granted = await AudioRecorder.requestPermission()
            guard let self else { return }
            self.beginRecording(granted: granted, hint: hint)
        }
    }

    /// Start the recorder and show the HUD. Runs on the main actor (AVAudioEngine,
    /// the status item, and the HUD's NSPanel all require it).
    private func beginRecording(granted: Bool, hint: String) {
        guard granted else {
            Toast.shared.show(AudioRecorder.RecorderError.micPermissionDenied.errorDescription ?? "Microphone denied.")
            return
        }
        do {
            recorder.onLevel = { level in RecordingHUD.shared.update(level: level) }
            try recorder.start()
            dictationSession &+= 1
            onRecordingStateChanged(true)
            RecordingHUD.shared.show(hint: hint)
        } catch {
            recorder.onLevel = nil
            Toast.shared.show((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func stopDictation() {
        guard recorder.isRecording else { return }
        onRecordingStateChanged(false)
        // Remove the tap (stop) before clearing onLevel, so the render thread can't
        // read the callback while the main thread nils it.
        let captured = recorder.stop()
        recorder.onLevel = nil
        guard let wav = captured, !wav.isEmpty else {
            RecordingHUD.shared.hide()
            Log.debug("dictation: no audio captured")
            return
        }

        let source = Settings.shared.voiceSource
        let key = KeychainStore.key(for: source.keyProvider) ?? ""
        // OpenAI Whisper requires a key; a local custom endpoint may not.
        if key.isEmpty && source.keyProvider != .openAICompatible {
            RecordingHUD.shared.hide()
            Toast.shared.show("Voice needs an OpenAI key (or set a Custom provider) in Settings → API Keys.")
            return
        }

        // Keep the same HUD on screen, now showing "Transcribing…".
        RecordingHUD.shared.transcribing()
        let session = dictationSession
        let ctx = dictationContext
        let language = Settings.shared.voiceLanguage
        let transcriber = OpenAIProvider(kind: source.keyProvider, baseURL: source.baseURL)
        Task {
            do {
                let text = try await transcriber.transcribe(wavData: wav, apiKey: key, model: source.model, language: language)
                // A newer dictation may have started while we were transcribing —
                // if so, don't touch its HUD or insert this (stale) text.
                guard self.dictationSession == session else { return }
                RecordingHUD.shared.hide()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { Toast.shared.show("Didn't catch that.", isError: false); return }
                ctx.targetApp?.activate()
                // Give the target app a beat to come frontmost before inserting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    TextInserter.insert(trimmed, into: ctx)
                }
            } catch {
                guard self.dictationSession == session else { return }
                RecordingHUD.shared.hide()
                Log.error("transcription failed: \(error.localizedDescription)")
                Toast.shared.show((error as? AIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.dataFolder])
    }
}
