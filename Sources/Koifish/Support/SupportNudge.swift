import AppKit
import SwiftUI

/// A small, non-blocking "support Openfish" card, shown once at a value moment after
/// the app has earned its place. It never locks anything — dismiss it and carry on.
/// Non-activating, so it doesn't steal focus from whatever you're typing in.
@MainActor
final class SupportNudge {
    static let shared = SupportNudge()
    private var panel: NSPanel?

    func show() {
        guard panel == nil else { return }   // already on screen — don't stack

        let view = SupportNudgeView(
            onSupport: { [weak self] in SupportStore.shared.openCheckout(); self?.dismiss() },
            onLater:   { [weak self] in SupportStore.shared.declineNudge(); self?.dismiss() },
            onAlready: { [weak self] in SupportStore.shared.markSupported(); self?.dismiss() }
        )
        let hosting = NSHostingView(rootView: view)
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
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

        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        if fit.width > 40, fit.height > 40 { p.setContentSize(fit) }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let s = p.frame.size
            p.setFrameOrigin(NSPoint(x: f.maxX - s.width - 24, y: f.minY + 96))   // bottom-right
        } else {
            p.center()
        }
        p.orderFront(nil)
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct SupportNudgeView: View {
    let onSupport: () -> Void
    let onLater: () -> Void
    let onAlready: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(nsImage: MenuBarIcon.fish)
                    .renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 22, height: 16).foregroundStyle(.primary)
                Text("Enjoying Openfish?").font(.headline)
            }
            Text("It's free and open source — and always will be. If it's earned a spot in your day, \(SupportLinks.price) keeps it going. For people who can afford it.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Support — \(SupportLinks.price)") { onSupport() }.glassButton()
                Button("Maybe later") { onLater() }.glassButton()
                Spacer(minLength: 8)
                Button("I already did") { onAlready() }.buttonStyle(.link)
            }
        }
        .frame(width: 340, alignment: .leading)
        .glassCard()
        .padding(8)
        .fixedSize()
    }
}
