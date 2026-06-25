import AppKit
import SwiftUI

/// A small floating `(gone fishing...)` cue, shown next to the pointer while a
/// direct-mode reply generates.
///
/// It is our own borderless, **non-activating** panel — never text in the target
/// field — so it works in every app, including web views (LinkedIn, x.com) where an
/// in-field placeholder can't be reliably removed. Being non-activating + ignoring
/// mouse events, it never steals focus from the field we're about to paste into.
@MainActor
final class FishingHUD {
    static let shared = FishingHUD()
    private var panel: NSPanel?

    /// Show the cue near the current pointer location.
    func show() {
        let p = panel ?? makePanel()
        panel = p
        position(p)
        p.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(rootView: FishingView())
        let p = NSPanel(contentViewController: hosting)
        p.styleMask = [.borderless, .nonactivatingPanel]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        return p
    }

    /// Park the cue just above-right of the pointer, clamped to the visible screen.
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation  // screen coords, bottom-left origin
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var x = mouse.x + 14
        var y = mouse.y + 14
        if let frame = screen?.visibleFrame {
            x = min(max(frame.minX + 8, x), frame.maxX - size.width - 8)
            y = min(max(frame.minY + 8, y), frame.maxY - size.height - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct FishingView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "fish.fill").foregroundStyle(.secondary)
            Text("(gone fishing...)").font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 12)
        .padding(8)
        .fixedSize()
    }
}
