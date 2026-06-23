// Generates a themed placeholder app icon (orange koi on dark water) at
// Resources/AppIcon-1024.png. Replace that PNG with the real logo and re-run
// scripts/make_icon.sh to use your own artwork.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Dark water-blue background with a soft vertical gradient.
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.11, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.19, alpha: 1),
])
gradient?.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 90)

// Orange koi glyph, centered.
let orange = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.2, alpha: 1)
let base = NSImage.SymbolConfiguration(pointSize: size * 0.58, weight: .regular)
let colored = NSImage.SymbolConfiguration(hierarchicalColor: orange)
if let symbol = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(base.applying(colored)) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon render failed\n".utf8))
    exit(1)
}
let out = URL(fileURLWithPath: "Resources/AppIcon-1024.png")
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
try! png.write(to: out)
print("wrote \(out.path)")
