import AppKit

/// One captured window: what app/window the user was in and the visible text.
/// Text-only — no screenshots are ever taken.
struct ActivitySnapshot: Sendable, Equatable {
    let epoch: TimeInterval
    let appName: String
    let windowTitle: String
    let text: String
}

/// Pure buffer/digest logic for the activity memory, split out so it's unit-tested
/// without AppKit. `now` is injected rather than read from the clock.
enum ActivityMemory {
    /// Append `snapshot`, coalescing repeated captures of the same window (keep the
    /// newest text) and pruning by age then count. Pure.
    static func appending(
        _ snapshot: ActivitySnapshot,
        to buffer: [ActivitySnapshot],
        now: TimeInterval,
        maxAge: TimeInterval,
        maxCount: Int
    ) -> [ActivitySnapshot] {
        var out = buffer
        if let last = out.last, last.appName == snapshot.appName, last.windowTitle == snapshot.windowTitle {
            out[out.count - 1] = snapshot           // same window in a row → replace
        } else {
            out.append(snapshot)
        }
        out = out.filter { now - $0.epoch <= maxAge }
        if out.count > maxCount { out = Array(out.suffix(maxCount)) }
        return out
    }

    /// Compact digest of recent *other* windows, newest first, for grounding a
    /// reply. Excludes the window currently being replied to and empty snapshots.
    /// Pure.
    static func digest(
        from buffer: [ActivitySnapshot],
        excludingApp: String,
        excludingWindow: String,
        now: TimeInterval,
        maxAge: TimeInterval,
        maxItems: Int,
        maxChars: Int
    ) -> String {
        let recent = buffer
            .filter { now - $0.epoch <= maxAge }
            .filter { !($0.appName == excludingApp && $0.windowTitle == excludingWindow) }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(maxItems)
            .reversed()
        guard !recent.isEmpty else { return "" }
        return recent.map { snap in
            let header = snap.windowTitle.isEmpty ? snap.appName : "\(snap.appName) — \(snap.windowTitle)"
            let clipped = snap.text.count > maxChars ? String(snap.text.prefix(maxChars)) + "…" : snap.text
            return "[\(header)]\n\(clipped)"
        }.joined(separator: "\n\n")
    }
}

/// Opt-in, off-by-default capture of recent window text, for cross-window context.
///
/// Privacy by design: **text only** (never screenshots), **in memory only** (never
/// written to disk), skips Openfish's own windows, and the buffer is **dropped the
/// moment watching is turned off**. Captures on app activation, debounced.
@MainActor
final class ActivityRecorder {
    private(set) var isWatching = false
    private var buffer: [ActivitySnapshot] = []
    private var observer: NSObjectProtocol?
    private var captureTask: Task<Void, Never>?

    /// Notified when watching starts/stops, so the menu-bar UI can show it.
    var onStateChanged: @MainActor (Bool) -> Void = { _ in }

    private let maxCount = 40
    private let maxAge: TimeInterval = 30 * 60   // 30 minutes
    private let snapshotChars = 1200

    func setWatching(_ on: Bool) { on ? start() : stop() }

    private func start() {
        guard !isWatching else { return }
        isWatching = true
        // App activation is the cheap, reliable signal for "the user moved windows".
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCapture() }
        }
        scheduleCapture()   // grab the current window right away
        onStateChanged(true)
        Log.info("Activity memory: watching")
    }

    private func stop() {
        guard isWatching else { return }
        isWatching = false
        captureTask?.cancel(); captureTask = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        buffer.removeAll()   // privacy: nothing lingers once you stop watching
        onStateChanged(false)
        Log.info("Activity memory: stopped (buffer cleared)")
    }

    /// Capture shortly after activation, once focus has settled.
    private func scheduleCapture() {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            self.capture()
        }
    }

    private func capture() {
        guard isWatching,
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier   // never record ourselves
        else { return }

        let ctx = FocusedFieldReader.read()
        let raw = ctx.pageContext.isEmpty ? ctx.fieldText : ctx.pageContext
        // The cursor marker is only meaningful live, not as stored context.
        let text = raw.replacingOccurrences(of: AXContext.cursorMarker, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let snapshot = ActivitySnapshot(
            epoch: Date().timeIntervalSince1970,
            appName: ctx.appName,
            windowTitle: ctx.windowTitle,
            text: String(text.prefix(snapshotChars))
        )
        buffer = ActivityMemory.appending(snapshot, to: buffer, now: snapshot.epoch, maxAge: maxAge, maxCount: maxCount)
        // Char counts only (never the text) — lets you confirm capture is working.
        Log.debug("activity: captured \(snapshot.text.count) chars from \(snapshot.appName) — \(snapshot.windowTitle); buffer=\(buffer.count)")
    }

    /// Digest of recent *other* windows to ground the current reply (empty unless
    /// watching). Excludes the window being replied to.
    func recentDigest(excludingApp: String, excludingWindow: String) -> String {
        guard isWatching else { return "" }
        let digest = ActivityMemory.digest(
            from: buffer, excludingApp: excludingApp, excludingWindow: excludingWindow,
            now: Date().timeIntervalSince1970, maxAge: maxAge, maxItems: 4, maxChars: 600
        )
        Log.debug("activity: digest \(digest.count) chars from buffer=\(buffer.count) (excluding \(excludingApp))")
        return digest
    }

    /// On-device tally of the people, places, and organizations named across the
    /// recent buffer (window titles + captured text), ranked by mentions. Empty
    /// unless watching. The seed of a future entity index — see `EntityExtractor`.
    func recentEntities() -> [EntityMention] {
        guard isWatching else { return [] }
        var rollup = EntityRollup()
        for snapshot in buffer {
            rollup.add(snapshot.windowTitle)
            rollup.add(snapshot.text)
        }
        return rollup.ranked
    }
}
