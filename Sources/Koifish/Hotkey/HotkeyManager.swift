import AppKit
import Carbon.HIToolbox

/// Global hotkey handling.
///
/// Most keys go through a `CGEventTap`. "Clean tap" detection reads the **event's
/// own modifier flags** (the OS's authoritative state) rather than a tracked
/// pressed-set, which previously desynced and poisoned the check.
///
/// The **Fn / Globe key is invisible to CGEventTap**, so it's handled separately
/// via an `NSEvent` global monitor that can see the `.function` modifier.
///
/// Triggers:
/// - generate: chord (key-down) or modifier tap → `onGenerate`
/// - dictate: chord/tap → `onDictateToggle`, or hold → `onDictateStart`/`Stop`
@MainActor
final class HotkeyManager {
    var onGenerate: @MainActor () -> Void = {}
    var onDictateToggle: @MainActor () -> Void = {}
    var onDictateStart: @MainActor () -> Void = {}
    var onDictateStop: @MainActor () -> Void = {}

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnMonitor: Any?
    private var fnDown = false

    // Tap detectors for the configured triggers (built at start()); hold state.
    private var genTap: ModifierTapDetector?
    private var dctTap: ModifierTapDetector?
    private var holdActive = false
    /// False when dictate is bound to the same physical key as generate — in that
    /// case generate wins and dictate is disabled, so one tap can't fire both.
    private var dictateActive = true

    private var generate: HotkeyTrigger { Settings.shared.generateHotkey }
    private var dictate: HotkeyTrigger { Settings.shared.dictateHotkey }

    @discardableResult
    func start() -> Bool {
        // Already installed — avoid creating a second tap that could never be torn
        // down (e.g. a key rebind racing the accessibility-permission poll).
        guard eventTap == nil else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                // Pull out the Sendable primitives here (CGEvent itself isn't
                // Sendable). The tap source lives on the main run loop, so the
                // callback always fires on the main thread — safe to assume it.
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                let decision = MainActor.assumeIsolated {
                    manager.handle(type: type, keyCode: keyCode, flags: flags)
                }
                return decision == .swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.error("Failed to create CGEventTap — Accessibility/Input Monitoring not granted?")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source

        // If dictate is bound to the same physical key as generate, generate wins
        // and dictate is disabled — otherwise one tap would fire both.
        dictateActive = keyCode(of: generate) != keyCode(of: dictate)
        if !dictateActive {
            Log.info("Dictate key matches generate — dictation disabled to avoid double-firing.")
        }

        // Fn is invisible to the CGEventTap, so Fn triggers run through the
        // NSEvent monitor instead — don't build tap detectors for them.
        if case let .modifierTap(key) = generate, !key.isFn {
            genTap = ModifierTapDetector(keyCode: key.keyCode, mask: key.cgFlagMask)
        }
        if case let .modifierTap(key) = dictate, !key.isFn, dictateActive {
            dctTap = ModifierTapDetector(keyCode: key.keyCode, mask: key.cgFlagMask)
        }

        startFnMonitorIfNeeded()
        Log.info("Hotkey tap installed: generate=\(generate.displayString) dictate=\(dictate.displayString)")
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let m = fnMonitor { NSEvent.removeMonitor(m) }
        eventTap = nil
        runLoopSource = nil
        fnMonitor = nil
    }

    // MARK: Fn (Globe) — separate path

    private func startFnMonitorIfNeeded() {
        let usesFn = {
            if case .modifierTap(.fn) = generate { return true }
            if dictateActive, case .modifierTap(.fn) = dictate { return true }
            if dictateActive, case .modifierHold(.fn) = dictate { return true }
            return false
        }()
        guard usesFn, fnMonitor == nil else { return }

        // Global monitors deliver on the main thread; assume the main actor so we
        // can touch our state and fire the (main-actor) callbacks directly.
        fnMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let isFn = event.modifierFlags.contains(.function)
                guard isFn != self.fnDown else { return }
                self.fnDown = isFn
                Log.debug("Fn (global monitor) \(isFn ? "down" : "up")")
                if case .modifierTap(.fn) = self.generate, isFn {
                    self.fire(self.onGenerate)   // Fn tap → generate
                }
                if self.dictateActive {
                    if case .modifierTap(.fn) = self.dictate {
                        if isFn { self.onDictateToggle() }   // tap each press → toggle
                    } else if case .modifierHold(.fn) = self.dictate {
                        isFn ? self.onDictateStart() : self.onDictateStop()
                    }
                }
            }
        }
        Log.info("Fn monitor installed (NSEvent global)")
    }

    // MARK: CGEventTap handling

    /// Whether the tap should pass the event through or swallow it (so the trigger
    /// key doesn't also land in the focused field).
    private enum TapDecision { case pass, swallow }

    private func handle(type: CGEventType, keyCode: UInt16, flags: CGEventFlags) -> TapDecision {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return .pass
        }

        switch type {
        case .keyDown:
            let mods = Self.modifierFlags(from: flags)
            if case let .chord(kc, m) = generate, keyCode == kc, mods == m { fire(onGenerate); return .swallow }
            if case let .chord(kc, m) = dictate, keyCode == kc, mods == m { fire(onDictateToggle); return .swallow }
            // A real key during a modifier tap means it wasn't a clean tap.
            genTap?.keyPressed()
            dctTap?.keyPressed()
            return .pass

        case .flagsChanged:
            if genTap?.modifierChanged(keyCode: keyCode, flags: flags) == true { fire(onGenerate) }
            if dctTap?.modifierChanged(keyCode: keyCode, flags: flags) == true { fire(onDictateToggle) }
            if dictateActive, case let .modifierHold(key) = dictate, !key.isFn {
                updateHold(key: key, keyCode: keyCode, flags: flags)
            }
            return .pass

        default:
            return .pass
        }
    }

    private func updateHold(key: ModifierKey, keyCode: UInt16, flags: CGEventFlags) {
        guard keyCode == key.keyCode else { return }
        if flags.contains(key.cgFlagMask) {
            if !holdActive { holdActive = true; fire(onDictateStart) }
        } else if holdActive {
            holdActive = false
            fire(onDictateStop)
        }
    }

    /// Defer the action to the next main-thread runloop pass so we never run app
    /// logic (AX reads, UI, synthesized keystrokes) inside the event-tap callback.
    private func fire(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(action) }
    }

    /// The physical key a trigger fires on, for detecting generate/dictate clashes.
    private func keyCode(of trigger: HotkeyTrigger) -> UInt16 {
        switch trigger {
        case .chord(let kc, _): return kc
        case .modifierTap(let key), .modifierHold(let key): return key.keyCode
        }
    }

    private static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var mods: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { mods.insert(.command) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        if flags.contains(.maskControl) { mods.insert(.control) }
        return mods
    }
}
