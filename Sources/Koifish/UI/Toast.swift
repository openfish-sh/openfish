import AppKit
import SwiftUI

/// A small, auto-dismissing glass HUD near the top of the screen. Used to surface
/// errors in direct mode (where there's no overlay) without stealing focus.
@MainActor
final class Toast {
    static let shared = Toast()
    private var panel: NSPanel?
    private var dismiss: Task<Void, Never>?

    func show(_ message: String, isError: Bool = true) {
        dismiss?.cancel()
        panel?.orderOut(nil)

        let hosting = NSHostingController(rootView: ToastView(message: message, isError: isError))
        let p = NSPanel(contentViewController: hosting)
        p.styleMask = [.borderless, .nonactivatingPanel]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        panel = p

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let s = p.frame.size
            p.setFrameOrigin(NSPoint(x: f.midX - s.width / 2, y: f.maxY - s.height - 60))
        } else {
            p.center()
        }
        p.orderFront(nil)

        let seconds = isError ? 5.0 : 2.5
        dismiss = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }
}

private struct ToastView: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "fish.fill")
                .foregroundStyle(isError ? .orange : .secondary)
            Text(message).font(.callout).lineLimit(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .glassCard(cornerRadius: 12)
        .padding(8)
        .fixedSize()
    }
}
