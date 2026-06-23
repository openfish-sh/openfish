import ApplicationServices

/// Low-level Accessibility helpers for reading/replacing text in the focused
/// element by character range — the basis for the in-field "Koifishing…"
/// indicator and direct insertion.
enum AXText {
    /// Current selection as (location, length), or nil if the element doesn't
    /// expose a selected-range (we then fall back to the review overlay).
    static func selectedRange(_ element: AXUIElement) -> (location: Int, length: Int)? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue((value as! AXValue), .cfRange, &range) else { return nil }
        return (range.location, range.length)
    }

    @discardableResult
    static func setSelectedRange(_ element: AXUIElement, location: Int, length: Int) -> Bool {
        var range = CFRange(location: location, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    @discardableResult
    static func setSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }
}
