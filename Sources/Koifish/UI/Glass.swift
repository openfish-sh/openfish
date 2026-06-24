import SwiftUI
import AppKit

/// Behind-window blur for translucent windows and panels (the base layer the
/// Liquid Glass cards float over).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .windowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

extension View {
    /// A card surface: real Liquid Glass on macOS 26+, frosted material below.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        if #available(macOS 26.0, *) {
            self.padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.08))
                )
        }
    }

    /// A solid black card for the dictation HUD — white content (fish, soundwave,
    /// labels) reads cleanly over it.
    func darkGlassCard(cornerRadius: CGFloat = 16) -> some View {
        self.padding(16)
            .background(.black, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.14))
            )
            .environment(\.colorScheme, .dark)
    }

    /// Glass button styling on macOS 26+, bordered below.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
