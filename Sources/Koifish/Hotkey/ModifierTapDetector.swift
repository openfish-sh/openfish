import CoreGraphics

/// Pure state machine for detecting a "clean tap" of a single modifier key — the
/// key goes down and back up with no other key or modifier involved. Reads the
/// event's own flags rather than tracking a pressed-set, so it can't desync.
///
/// Kept free of AppKit/CGEventTap so it can be unit-tested with synthetic events.
struct ModifierTapDetector {
    let keyCode: UInt16
    let mask: CGEventFlags

    private(set) var active = false
    private(set) var dirty = false

    /// All modifier flags we consider "significant" for tap-cleanliness.
    static let significantMasks: [CGEventFlags] =
        [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]

    /// Feed a `flagsChanged` event. Returns true iff a clean tap just completed
    /// (i.e. the target key was released with nothing else involved).
    mutating func modifierChanged(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        if keyCode == self.keyCode {
            if flags.contains(mask) {            // target pressed down
                active = true
                dirty = Self.otherModifiersPresent(flags, except: mask)
                return false
            }
            let fired = active && !dirty         // target released
            active = false
            dirty = false
            return fired
        }
        if active { dirty = true }               // a different modifier moved mid-tap
        return false
    }

    /// Feed a non-modifier key-down — any real key cancels a clean tap.
    mutating func keyPressed() {
        if active { dirty = true }
    }

    static func otherModifiersPresent(_ flags: CGEventFlags, except target: CGEventFlags) -> Bool {
        significantMasks.contains { $0 != target && flags.contains($0) }
    }
}
