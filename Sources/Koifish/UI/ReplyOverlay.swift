import AppKit
import SwiftUI
import Combine

/// Observable state for the overlay, updated as generation streams in.
@MainActor
final class OverlayModel: ObservableObject {
    @Published var text: String = ""
    @Published var isStreaming: Bool = false
    @Published var status: String = ""
    @Published var contextSummary: String = ""
}

/// A floating panel that shows the streamed reply with Accept / Edit (inline) /
/// Regenerate / Cancel. The text view is editable so the user can tweak before
/// accepting — accepted-vs-edited is what drives style learning.
@MainActor
final class ReplyOverlayController {
    let model = OverlayModel()

    var onAccept: (String) -> Void = { _ in }
    var onRegenerate: () -> Void = {}
    var onCancel: () -> Void = {}

    private var panel: NSPanel?

    func show(contextSummary: String) {
        model.text = ""
        model.status = ""
        model.isStreaming = true
        model.contextSummary = contextSummary

        if panel == nil {
            let view = ReplyOverlayView(
                model: model,
                onAccept: { [weak self] in self?.onAccept(self?.model.text ?? "") },
                onRegenerate: { [weak self] in self?.onRegenerate() },
                onCancel: { [weak self] in self?.onCancel() }
            )
            let hosting = NSHostingController(rootView: view)
            let p = NSPanel(contentViewController: hosting)
            p.styleMask = [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.title = "Openfish"
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isOpaque = false
            p.backgroundColor = .clear
            p.isMovableByWindowBackground = true
            p.setContentSize(NSSize(width: 460, height: 280))
            panel = p
        }

        guard let panel else { return }
        centerNearTop(panel)
        panel.orderFront(nil)
    }

    func appendDelta(_ delta: String) {
        model.text += delta
    }

    func finishStreaming() {
        model.isStreaming = false
    }

    func showError(_ message: String) {
        model.isStreaming = false
        model.status = message
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func centerNearTop(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { panel.center(); return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct ReplyOverlayView: View {
    @ObservedObject var model: OverlayModel
    let onAccept: () -> Void
    let onRegenerate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.contextSummary.isEmpty {
                Text(model.contextSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 140)
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.25))
                )
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty && model.isStreaming {
                        Text("Koifishing…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 14).padding(.leading, 13)
                    }
                }

            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .glassButton()
                Spacer()
                Button("Regenerate", action: onRegenerate)
                    .disabled(model.isStreaming)
                    .glassButton()
                Button("Accept & Insert", action: onAccept)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isStreaming || model.text.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(VisualEffectBackground(material: .hudWindow).ignoresSafeArea())
    }
}
