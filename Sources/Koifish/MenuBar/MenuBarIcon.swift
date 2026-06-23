import AppKit

/// The menu-bar fish glyph, embedded as a base64 PNG. It ships inline because the
/// hand-rolled bundler (scripts/bundle.sh) copies only the binary, Info.plist and
/// AppIcon.icns — not SPM resource bundles — so a file resource wouldn't make it
/// into OpenFish.app. Source art: koifish-website/public/fish.svg, rasterized to a
/// 52x36 @2x bitmap (sized for an 18-pt-tall status item).
enum MenuBarIcon {
    /// A template image: the system tints it for light/dark menu bars, exactly
    /// like the SF Symbol it replaces.
    static let fish: NSImage = {
        if let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
           let image = NSImage(data: data) {
            image.size = NSSize(width: 26, height: 18)   // points; the bitmap is @2x
            image.isTemplate = true
            return image
        }
        // The literal is static, so this shouldn't happen — but a blank menu-bar
        // item is a bad failure mode, so fall back to a system fish glyph.
        let fallback = NSImage(systemSymbolName: "fish", accessibilityDescription: "OpenFish") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }()

    private static let base64 = """
    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
    """
}
