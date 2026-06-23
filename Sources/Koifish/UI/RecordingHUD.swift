import AppKit
import SwiftUI

/// A single floating HUD shown near the bottom of the screen for the whole
/// dictation flow: live soundwave while listening, then a "Transcribing…" state
/// in the *same* box (no second panel elsewhere on screen).
@MainActor
final class RecordingHUD {
    static let shared = RecordingHUD()

    let model = RecordingModel()
    private var panel: NSPanel?

    /// Show the live soundwave and start listening.
    func show(hint: String) {
        model.reset(hint: hint)
        if panel == nil {
            let hosting = NSHostingView(rootView: RecordingHUDView(model: model))
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 56),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.contentView = hosting
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .floating
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            panel = p
        }
        layout()
    }

    func update(level: Float) {
        model.push(level)
    }

    /// Switch the same HUD into its "Transcribing…" state (spinner + label),
    /// keeping it where it is rather than spawning a separate status box.
    func transcribing(hint: String = "Transcribing…") {
        guard panel != nil else { return }
        model.beginTranscribing(hint: hint)
        // The @Published change doesn't re-render the hosting view synchronously,
        // so re-fit on the next runloop once SwiftUI has laid out the new content.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            self.layout()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Re-fit the panel to the current content and re-center it near the bottom.
    private func layout() {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let fit = content.fittingSize
        if fit.width > 40, fit.height > 20 { panel.setContentSize(fit) }
        position(panel)
        panel.orderFront(nil)
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { panel.center(); return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 90))
    }
}

@MainActor
final class RecordingModel: ObservableObject {
    static let barCount = 28
    @Published var levels: [Float] = Array(repeating: 0, count: barCount)
    @Published var hint = "Listening…"
    @Published var isTranscribing = false

    func reset(hint: String) {
        self.hint = hint
        isTranscribing = false
        levels = Array(repeating: 0, count: Self.barCount)
    }

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    func beginTranscribing(hint: String) {
        isTranscribing = true
        self.hint = hint
    }
}

private struct RecordingHUDView: View {
    @ObservedObject var model: RecordingModel

    var body: some View {
        Group {
            if model.isTranscribing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text(model.hint).font(.callout).foregroundStyle(.white.opacity(0.85))
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "mic.fill").foregroundStyle(.red)
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(model.levels.indices, id: \.self) { i in
                            Capsule()
                                .fill(.white)
                                .frame(width: 3, height: max(3, CGFloat(model.levels[i]) * 26))
                        }
                    }
                    .frame(height: 28)
                    .animation(.linear(duration: 0.08), value: model.levels)
                    Text(model.hint).font(.callout).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .darkGlassCard(cornerRadius: 14)
        .padding(8)
        .fixedSize()
    }
}
