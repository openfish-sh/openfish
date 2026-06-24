import ApplicationServices

/// Gathers the *surrounding* context of the focused field — the visible
/// conversation/page text of the window, with a marker at the cursor and a
/// breadcrumb of ancestor element names. This is what makes replies relevant:
/// the model sees what you're replying to, not just an empty compose box.
enum AXContext {
    struct Result {
        var pageText: String
        var breadcrumb: [String]   // outermost → innermost ancestor names
        var focusedRole: String
    }

    /// Marker inserted at the focused element's position in the page text.
    static let cursorMarker = "⟦▮ cursor — the user is typing here⟧"

    private static let maxChars = 6000
    // The walk's element/time caps are passed in, because the right limit depends on
    // the caller. Each attribute read is a synchronous cross-process AX call that runs
    // on the main thread, and the global hotkey tap lives on the main run loop — so an
    // unbounded walk stalls system-wide input. A *user-initiated* read (pressing the
    // hotkey) can afford a longer budget to capture a heavy page's conversation, since
    // the user is waiting on a reply anyway; the *automatic* activity capture must stay
    // tight so it never freezes input on a routine app switch.

    static func gather(focused: AXUIElement, maxElements: Int = 450, budget: CFTimeInterval = 0.12) -> Result {
        let role = copyString(focused, kAXRoleAttribute) ?? ""
        let breadcrumb = ancestorNames(of: focused)

        var pieces: [String] = []
        var visited = 0
        let deadline = CFAbsoluteTimeGetCurrent() + budget
        if let window = window(of: focused) {
            collect(window, focused: focused, into: &pieces, visited: &visited, maxElements: maxElements, deadline: deadline)
        }
        let joined = dedupedJoin(pieces)
        return Result(pageText: Self.clip(joined, marker: cursorMarker, maxChars: maxChars),
                      breadcrumb: breadcrumb, focusedRole: role)
    }

    // MARK: Tree walk

    private static func collect(_ element: AXUIElement, focused: AXUIElement, into pieces: inout [String], visited: inout Int, maxElements: Int, deadline: CFAbsoluteTime, sender: String? = nil) {
        guard visited < maxElements, CFAbsoluteTimeGetCurrent() < deadline else { return }
        visited += 1

        // Chat apps tag each message bubble's group with an accessibility
        // description like "Speaker, body, time". Pick the speaker up here and
        // carry it down to the text node inside, so we can label who said what.
        let sender = (copyString(element, kAXDescriptionAttribute).flatMap(messageSpeaker(fromDescription:))) ?? sender

        if CFEqual(element, focused) {
            // The focused compose field: drop a cursor marker but DON'T capture its
            // value — that's the user's own unsent draft, which PromptBuilder already
            // sends in its own labeled block. Capturing it here too would duplicate it
            // and, sitting right at the cursor, make the model read the user's own
            // half-typed text as the latest message to reply to.
            pieces.append(cursorMarker)
        } else if let value = copyString(element, kAXValueAttribute), !value.isEmpty, value.count < 2000 {
            pieces.append(label(value, sender: sender))
        } else if copyString(element, kAXRoleAttribute) == "AXStaticText",
                  let title = copyString(element, kAXTitleAttribute), !title.isEmpty {
            pieces.append(label(title, sender: sender))
        }

        for child in children(of: element) {
            if visited >= maxElements || CFAbsoluteTimeGetCurrent() >= deadline { break }
            collect(child, focused: focused, into: &pieces, visited: &visited, maxElements: maxElements, deadline: deadline, sender: sender)
        }
    }

    private static func label(_ text: String, sender: String?) -> String {
        guard let sender else { return text }
        return "\(sender): \(text)"
    }

    /// Parse the speaker from a chat-message accessibility description of the form
    /// "<speaker>, <body>, <time>" (how Messages and similar apps expose each
    /// bubble). Returns "Me" for the user's own messages, the sender's name for
    /// received ones, and nil for anything that isn't a message. Pure + testable.
    static func messageSpeaker(fromDescription desc: String) -> String? {
        let parts = desc.components(separatedBy: ", ")
        guard parts.count >= 3, let last = parts.last, looksLikeTime(last) else { return nil }
        let speaker = parts[0].trimmingCharacters(in: .whitespaces)
        guard !speaker.isEmpty else { return nil }
        // Messages marks the user's own bubbles "Your iMessage" / "Your SMS" /
        // "Your text message". Match those exactly — a loose "Your …" prefix would
        // mislabel a contact named e.g. "Your Mom" as the user.
        let ownMarkers: Set<String> = ["Your iMessage", "Your SMS", "Your text message", "You"]
        return ownMarkers.contains(speaker) ? "Me" : speaker
    }

    /// True only for a real clock time like "14:28" or "9:05 PM": a 1–2 digit hour,
    /// exactly two minute digits, optional AM/PM. Strict on purpose, so aspect
    /// ratios ("16:9"), scores, and version numbers don't read as timestamps.
    static func looksLikeTime(_ s: String) -> Bool {
        let core = s.split(separator: " ").first.map(String.init) ?? s
        let parts = core.split(separator: ":")
        return parts.count == 2
            && (1...2).contains(parts[0].count) && parts[0].allSatisfy(\.isNumber)
            && parts[1].count == 2 && parts[1].allSatisfy(\.isNumber)
    }

    // MARK: Helpers

    private static func window(of element: AXUIElement) -> AXUIElement? {
        if let w = copyElement(element, kAXWindowAttribute) { return w }
        if let w = copyElement(element, kAXTopLevelUIElementAttribute) { return w }
        return element
    }

    private static func ancestorNames(of element: AXUIElement) -> [String] {
        var names: [String] = []
        var current: AXUIElement? = copyElement(element, kAXParentAttribute)
        var hops = 0
        while let el = current, hops < 4 {
            let name = copyString(el, kAXTitleAttribute)
                ?? copyString(el, kAXDescriptionAttribute)
                ?? copyString(el, kAXRoleDescriptionAttribute)
            if let name, !name.isEmpty { names.append(name) }
            current = copyElement(el, kAXParentAttribute)
            hops += 1
        }
        return names.reversed()   // outermost first
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement]
        else { return [] }
        return array
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXUIElementGetTypeID()
        else { return nil }
        return (v as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func dedupedJoin(_ pieces: [String]) -> String {
        var out: [String] = []
        for p in pieces where out.last != p { out.append(p) }
        return out.joined(separator: "\n")
    }

    /// Keep the text bounded, preferring the region around the cursor marker.
    /// Internal + parameterized so it can be unit-tested.
    static func clip(_ text: String, marker: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        if let range = text.range(of: marker) {
            let markerIndex = text.distance(from: text.startIndex, to: range.lowerBound)
            let half = maxChars / 2
            let lower = max(0, markerIndex - half)
            let upper = min(text.count, markerIndex + half)
            let start = text.index(text.startIndex, offsetBy: lower)
            let end = text.index(text.startIndex, offsetBy: upper)
            return "…" + text[start..<end] + "…"
        }
        return String(text.prefix(maxChars)) + "…"
    }
}
