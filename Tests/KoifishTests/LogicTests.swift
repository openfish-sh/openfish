import XCTest
import AppKit
import Carbon.HIToolbox
@testable import Koifish

final class HotkeyTriggerTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(HotkeyTrigger.defaultGenerate, .modifierTap(.rightOption))
        XCTAssertEqual(HotkeyTrigger.defaultDictate, .modifierHold(.fn))
    }

    func testTapRoundTrip() {
        let t = HotkeyTrigger.modifierTap(.rightOption)
        XCTAssertEqual(HotkeyTrigger(encoded: t.encoded), t)
    }

    func testHoldRoundTrip() {
        let t = HotkeyTrigger.modifierHold(.fn)
        XCTAssertEqual(HotkeyTrigger(encoded: t.encoded), t)
    }

    func testChordRoundTrip() {
        let t = HotkeyTrigger.chord(keyCode: 49, modifiers: [.option, .shift])
        XCTAssertEqual(HotkeyTrigger(encoded: t.encoded), t)
    }

    func testRejectsGarbage() {
        XCTAssertNil(HotkeyTrigger(encoded: ""))
        XCTAssertNil(HotkeyTrigger(encoded: "garbage"))
        XCTAssertNil(HotkeyTrigger(encoded: "tap:notakey"))
        XCTAssertNil(HotkeyTrigger(encoded: "chord:notanumber:0"))
    }

    func testDisplayStrings() {
        XCTAssertEqual(HotkeyTrigger.modifierTap(.rightOption).displayString, "Right ⌥ (tap)")
        XCTAssertEqual(HotkeyTrigger.modifierHold(.fn).displayString, "Fn (hold)")
    }

    func testRightVsLeftOptionDistinctKeyCodes() {
        XCTAssertNotEqual(ModifierKey.leftOption.keyCode, ModifierKey.rightOption.keyCode)
    }

    func testModifierFlagMapping() {
        XCTAssertEqual(ModifierKey.rightOption.cgFlagMask, .maskAlternate)
        XCTAssertEqual(ModifierKey.leftOption.cgFlagMask, .maskAlternate)
        XCTAssertEqual(ModifierKey.fn.cgFlagMask, .maskSecondaryFn)
        XCTAssertEqual(ModifierKey.rightCommand.cgFlagMask, .maskCommand)
        XCTAssertEqual(ModifierKey.rightShift.cgFlagMask, .maskShift)
        XCTAssertTrue(ModifierKey.fn.isFn)
        XCTAssertFalse(ModifierKey.rightOption.isFn)
    }

    func testChordDisplay() {
        let chord = HotkeyTrigger.chord(keyCode: UInt16(kVK_Space), modifiers: [.command, .shift])
        XCTAssertEqual(chord.displayString, "⇧⌘Space")
    }
}

final class PromptBuilderTests: XCTestCase {
    private func ctx(field: String = "", selected: String = "", page: String = "") -> FocusedContext {
        FocusedContext(fieldText: field, selectedText: selected, appName: "TestApp",
                       windowTitle: "Win", element: nil, targetApp: nil,
                       pageContext: page, breadcrumb: [], focusedRole: "")
    }

    func testSelectionAsksForRewrite() {
        let r = PromptBuilder.build(context: ctx(selected: "hello world"), styleDescription: "casual", model: "m")
        XCTAssertTrue(r.userPrompt.contains("rewritten"))
        XCTAssertTrue(r.userPrompt.contains("hello world"))
        XCTAssertTrue(r.systemPrompt.contains("casual"))
        XCTAssertEqual(r.model, "m")
    }

    func testExistingTextHandled() {
        let r = PromptBuilder.build(context: ctx(field: "Dear team,"), styleDescription: "", model: "m")
        XCTAssertTrue(r.userPrompt.contains("Dear team,"))
        XCTAssertTrue(r.userPrompt.lowercased().contains("continue") || r.userPrompt.lowercased().contains("instruction"))
    }

    func testEmptyFieldOpening() {
        let r = PromptBuilder.build(context: ctx(), styleDescription: "", model: "m")
        XCTAssertTrue(r.userPrompt.contains("empty"))
    }

    func testPageContextIsIncluded() {
        let r = PromptBuilder.build(context: ctx(page: "Alice: are we still on for Friday?"), styleDescription: "", model: "m")
        XCTAssertTrue(r.userPrompt.contains("Alice: are we still on for Friday?"))
        XCTAssertTrue(r.userPrompt.contains("Visible context"))
    }

    func testSystemPromptGroundsAndRepliesToOther() {
        let r = PromptBuilder.build(context: ctx(), styleDescription: "", model: "m")
        XCTAssertTrue(r.systemPrompt.contains("person they're talking to"))
        XCTAssertTrue(r.systemPrompt.lowercased().contains("fabricate"))
    }

    func testEmptyStyleNotInjected() {
        let r = PromptBuilder.build(context: ctx(field: "x"), styleDescription: "", model: "m")
        XCTAssertFalse(r.systemPrompt.contains("writing style"))
    }

    func testSelfNameStatesTheWriter() {
        let r = PromptBuilder.build(context: ctx(), styleDescription: "", model: "m", selfName: "Ruben Flam")
        XCTAssertTrue(r.systemPrompt.contains("writing as Ruben Flam"))
    }

    func testNoSelfNameDoesNotClaimAWriter() {
        // The base prompt always says "writing as the user"; a set name adds a
        // second, specific "writing as <Name>" line. No name → no specific claim.
        let withName = PromptBuilder.build(context: ctx(), styleDescription: "", model: "m", selfName: "Ruben Flam")
        let without = PromptBuilder.build(context: ctx(), styleDescription: "", model: "m", selfName: "")
        XCTAssertTrue(withName.systemPrompt.contains("writing as Ruben Flam"))
        XCTAssertFalse(without.systemPrompt.contains("writing as Ruben Flam"))
    }

    func testAliasesAreListedAsTheUser() {
        let r = PromptBuilder.build(context: ctx(), styleDescription: "", model: "m",
                                    selfName: "Ruben Flam", selfAliases: ["Rubke", "R.F."])
        XCTAssertTrue(r.systemPrompt.contains("Rubke"))
        XCTAssertTrue(r.systemPrompt.contains("R.F."))
        XCTAssertTrue(r.systemPrompt.lowercased().contains("your own"))
    }

    func testAliasesIgnoredWithoutAName() {
        // Aliases only make sense as "also you" — without a primary name there's no
        // anchor, so the identity line shouldn't appear at all.
        let r = PromptBuilder.build(context: ctx(), styleDescription: "", model: "m",
                                    selfName: "", selfAliases: ["Rubke"])
        XCTAssertFalse(r.systemPrompt.contains("Rubke"))
    }

    func testAliasesDedupedAgainstNameAndEachOther() {
        let r = PromptBuilder.build(context: ctx(), styleDescription: "", model: "m",
                                    selfName: "Ruben", selfAliases: ["ruben", "Rubke", "Rubke"])
        let prompt = r.systemPrompt
        XCTAssertEqual(prompt.components(separatedBy: "Rubke").count - 1, 1, "duplicate alias should collapse to one")
        XCTAssertFalse(prompt.lowercased().contains("appear as ruben"), "an alias equal to the name should be dropped")
    }

    // End-to-end: the Settings the UI writes flow through the exact path
    // Coordinator.makeRequest uses to build a request. Saves/restores the shared
    // singleton so it can't leak into other tests.
    @MainActor
    func testSettingNameFlowsIntoPrompt() {
        let s = Settings.shared
        let (savedName, savedAliases) = (s.selfName, s.selfAliases)
        defer { s.selfName = savedName; s.selfAliases = savedAliases }

        s.selfName = "Test Persson"
        s.selfAliases = "TP, T.P."
        XCTAssertEqual(s.effectiveSelfName, "Test Persson")
        XCTAssertEqual(s.selfAliasList, ["TP", "T.P."])

        let r = PromptBuilder.build(context: ctx(), styleDescription: "", model: "m",
                                    selfName: s.effectiveSelfName, selfAliases: s.selfAliasList)
        XCTAssertTrue(r.systemPrompt.contains("writing as Test Persson"))
        XCTAssertTrue(r.systemPrompt.contains("TP"))
        XCTAssertTrue(r.systemPrompt.contains("T.P."))
    }

    @MainActor
    func testEffectiveSelfNameFallsBackToOSNameWhenBlank() {
        let s = Settings.shared
        let saved = s.selfName
        defer { s.selfName = saved }

        s.selfName = "   "                       // blank → fall back to the OS name
        XCTAssertEqual(s.effectiveSelfName, Settings.osFullName)
        s.selfName = "Explicit Name"             // set → use it verbatim
        XCTAssertEqual(s.effectiveSelfName, "Explicit Name")
    }
}

final class CodableModelTests: XCTestCase {
    func testStyleProfileRoundTrip() throws {
        let p = StyleProfile(description: "terse", sampleCount: 3, updatedAtEpoch: 123)
        let back = try JSONDecoder().decode(StyleProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.description, "terse")
        XCTAssertEqual(back.sampleCount, 3)
        XCTAssertEqual(back.updatedAtEpoch, 123)
    }

    func testStyleProfileDefaults() {
        let p = StyleProfile()
        XCTAssertEqual(p.description, "")
        XCTAssertEqual(p.sampleCount, 0)
        XCTAssertNil(p.updatedAtEpoch)
    }

    func testInteractionRoundTrip() throws {
        let i = Interaction(epoch: 1, appName: "A", windowTitle: "W", contextText: "c",
                            generated: "g", final: "f", disposition: .edited)
        let back = try JSONDecoder().decode(Interaction.self, from: JSONEncoder().encode(i))
        XCTAssertEqual(back.disposition, .edited)
        XCTAssertEqual(back.generated, "g")
        XCTAssertEqual(back.final, "f")
    }
}

final class StreamingHTTPTests: XCTestCase {
    func testParsesJSONObject() {
        let o = StreamingHTTP.jsonObject(#"{"type":"x","n":1}"#)
        XCTAssertEqual(o?["type"] as? String, "x")
    }

    func testRejectsNonObject() {
        XCTAssertNil(StreamingHTTP.jsonObject("not json"))
        XCTAssertNil(StreamingHTTP.jsonObject("[1,2,3]"))
        XCTAssertNil(StreamingHTTP.jsonObject(""))
    }

    func testSSEPayloadExtraction() {
        XCTAssertEqual(StreamingHTTP.payload(from: #"data: {"a":1}"#), #"{"a":1}"#)
        XCTAssertEqual(StreamingHTTP.payload(from: #"data:{"a":1}"#), #"{"a":1}"#)  // no space
        XCTAssertNil(StreamingHTTP.payload(from: "data: [DONE]"))
        XCTAssertNil(StreamingHTTP.payload(from: "data: "))
        XCTAssertNil(StreamingHTTP.payload(from: "event: message_start"))
        XCTAssertNil(StreamingHTTP.payload(from: ""))
    }

    func testRetryableStatusCodes() {
        // Rate limits and server errors retry; client errors and success don't.
        XCTAssertTrue(StreamingHTTP.isRetryable(status: 429))
        XCTAssertTrue(StreamingHTTP.isRetryable(status: 500))
        XCTAssertTrue(StreamingHTTP.isRetryable(status: 503))
        XCTAssertFalse(StreamingHTTP.isRetryable(status: 200))
        XCTAssertFalse(StreamingHTTP.isRetryable(status: 400))
        XCTAssertFalse(StreamingHTTP.isRetryable(status: 401))
        XCTAssertFalse(StreamingHTTP.isRetryable(status: 404))
    }

    func testRetryDelayHonorsRetryAfter() {
        XCTAssertEqual(StreamingHTTP.retryDelay(retryAfter: "5", attempt: 1), 5)
        XCTAssertEqual(StreamingHTTP.retryDelay(retryAfter: " 2 ", attempt: 1), 2)   // trimmed
        XCTAssertEqual(StreamingHTTP.retryDelay(retryAfter: "100", attempt: 1), 30)  // clamped
    }

    func testRetryDelayFallsBackToBackoff() {
        XCTAssertEqual(StreamingHTTP.retryDelay(retryAfter: nil, attempt: 1), 1.5)
        XCTAssertEqual(StreamingHTTP.retryDelay(retryAfter: "not-a-number", attempt: 1), 1.5)  // HTTP-date ignored
        XCTAssertEqual(StreamingHTTP.retryDelay(retryAfter: "0", attempt: 1), 1.5)              // non-positive ignored
    }
}

final class ActivityMemoryTests: XCTestCase {
    private func snap(_ app: String, _ window: String, _ text: String, at epoch: TimeInterval) -> ActivitySnapshot {
        ActivitySnapshot(epoch: epoch, appName: app, windowTitle: window, text: text)
    }

    func testCoalescesConsecutiveSameWindow() {
        var buf: [ActivitySnapshot] = []
        buf = ActivityMemory.appending(snap("Slack", "general", "hi", at: 1), to: buf, now: 1, maxAge: 1000, maxCount: 10)
        buf = ActivityMemory.appending(snap("Slack", "general", "hi there", at: 2), to: buf, now: 2, maxAge: 1000, maxCount: 10)
        XCTAssertEqual(buf.count, 1)
        XCTAssertEqual(buf.last?.text, "hi there")   // kept the newest text
    }

    func testKeepsDistinctWindows() {
        var buf: [ActivitySnapshot] = []
        buf = ActivityMemory.appending(snap("Docs", "Plan", "a", at: 1), to: buf, now: 1, maxAge: 1000, maxCount: 10)
        buf = ActivityMemory.appending(snap("Slack", "general", "b", at: 2), to: buf, now: 2, maxAge: 1000, maxCount: 10)
        XCTAssertEqual(buf.count, 2)
    }

    func testPrunesByAgeAndCount() {
        var buf: [ActivitySnapshot] = []
        buf = ActivityMemory.appending(snap("A", "1", "old", at: 0), to: buf, now: 0, maxAge: 100, maxCount: 10)
        // Now is far past maxAge → the old one is pruned when the next arrives.
        buf = ActivityMemory.appending(snap("B", "2", "new", at: 200), to: buf, now: 200, maxAge: 100, maxCount: 10)
        XCTAssertEqual(buf.map(\.appName), ["B"])

        var capped: [ActivitySnapshot] = []
        for i in 0..<5 { capped = ActivityMemory.appending(snap("App\(i)", "w\(i)", "t", at: TimeInterval(i)), to: capped, now: TimeInterval(i), maxAge: 1000, maxCount: 3) }
        XCTAssertEqual(capped.count, 3)
        XCTAssertEqual(capped.first?.appName, "App2")   // oldest dropped
    }

    func testDigestExcludesCurrentWindowAndOrdersNewestFirst() {
        let buf = [
            snap("Docs", "Plan", "roadmap details", at: 1),
            snap("Slack", "general", "should be excluded", at: 2),
        ]
        let digest = ActivityMemory.digest(from: buf, excludingApp: "Slack", excludingWindow: "general",
                                           now: 3, maxAge: 1000, maxItems: 4, maxChars: 100)
        XCTAssertTrue(digest.contains("Docs — Plan"))
        XCTAssertTrue(digest.contains("roadmap details"))
        XCTAssertFalse(digest.contains("should be excluded"))
    }

    func testDigestEmptyWhenNothingRelevant() {
        let buf = [snap("Slack", "general", "x", at: 1)]
        let digest = ActivityMemory.digest(from: buf, excludingApp: "Slack", excludingWindow: "general",
                                           now: 2, maxAge: 1000, maxItems: 4, maxChars: 100)
        XCTAssertEqual(digest, "")
    }
}

final class SSEDeltaTests: XCTestCase {
    func testAnthropicTextDelta() {
        let payload = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        XCTAssertEqual(AnthropicProvider.textDelta(fromSSE: payload), "Hello")
    }

    func testAnthropicIgnoresNonTextEvents() {
        XCTAssertNil(AnthropicProvider.textDelta(fromSSE: #"{"type":"message_start","message":{}}"#))
        XCTAssertNil(AnthropicProvider.textDelta(fromSSE: #"{"type":"content_block_stop","index":0}"#))
        XCTAssertNil(AnthropicProvider.textDelta(fromSSE: #"{"type":"ping"}"#))
        XCTAssertNil(AnthropicProvider.textDelta(fromSSE: "not json"))
    }

    func testOpenAITextDelta() {
        let payload = #"{"choices":[{"delta":{"content":"Hi"},"index":0}]}"#
        XCTAssertEqual(OpenAIProvider.textDelta(fromSSE: payload), "Hi")
    }

    func testOpenAIIgnoresRoleAndFinishChunks() {
        XCTAssertNil(OpenAIProvider.textDelta(fromSSE: #"{"choices":[{"delta":{"role":"assistant"}}]}"#))
        XCTAssertNil(OpenAIProvider.textDelta(fromSSE: #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#))
        XCTAssertNil(OpenAIProvider.textDelta(fromSSE: #"{"choices":[]}"#))
    }

    func testReasoningEffortByProvider() {
        // The gpt-5.4 family rejects "minimal"; "none" is its lowest tier. Custom
        // OpenAI-compatible endpoints get nil so the param can't break an unknown model.
        XCTAssertEqual(OpenAIProvider.reasoningEffort(for: .openai), "none")
        XCTAssertEqual(OpenAIProvider.reasoningEffort(for: .gemini), "low")
        XCTAssertNil(OpenAIProvider.reasoningEffort(for: .openAICompatible))
    }
}

final class ModifierTapDetectorTests: XCTestCase {
    // Right Option keycode + its flag.
    private let key: UInt16 = 61
    private let mask: CGEventFlags = .maskAlternate

    func testCleanTapFires() {
        var d = ModifierTapDetector(keyCode: key, mask: mask)
        XCTAssertFalse(d.modifierChanged(keyCode: key, flags: [.maskAlternate]))  // down
        XCTAssertTrue(d.modifierChanged(keyCode: key, flags: []))                 // up → fires
    }

    func testTapWithAnotherModifierHeldDoesNotFire() {
        var d = ModifierTapDetector(keyCode: key, mask: mask)
        // Option pressed while Command already held → dirty.
        _ = d.modifierChanged(keyCode: key, flags: [.maskAlternate, .maskCommand])
        XCTAssertFalse(d.modifierChanged(keyCode: key, flags: [.maskCommand]))
    }

    func testRealKeyDuringTapCancels() {
        var d = ModifierTapDetector(keyCode: key, mask: mask)
        _ = d.modifierChanged(keyCode: key, flags: [.maskAlternate])  // down
        d.keyPressed()                                                // typed a key
        XCTAssertFalse(d.modifierChanged(keyCode: key, flags: []))    // up → no fire
    }

    func testOtherModifierChangingMidTapCancels() {
        var d = ModifierTapDetector(keyCode: key, mask: mask)
        _ = d.modifierChanged(keyCode: key, flags: [.maskAlternate])  // down
        _ = d.modifierChanged(keyCode: 55, flags: [.maskAlternate, .maskCommand])  // Cmd down mid-tap
        XCTAssertFalse(d.modifierChanged(keyCode: key, flags: []))
    }

    func testUnrelatedModifierIgnored() {
        var d = ModifierTapDetector(keyCode: key, mask: mask)
        XCTAssertFalse(d.modifierChanged(keyCode: 55, flags: [.maskCommand]))  // not our key
    }
}

final class AXContextTests: XCTestCase {
    func testClipShortTextUnchanged() {
        let text = "short conversation"
        XCTAssertEqual(AXContext.clip(text, marker: "•", maxChars: 100), text)
    }

    func testClipCentersOnMarker() {
        let before = String(repeating: "A", count: 200)
        let after = String(repeating: "B", count: 200)
        let text = before + "•" + after
        let clipped = AXContext.clip(text, marker: "•", maxChars: 40)
        XCTAssertTrue(clipped.contains("•"))           // marker preserved
        XCTAssertLessThan(clipped.count, text.count)   // actually clipped
    }

    func testClipWithoutMarkerTruncates() {
        let text = String(repeating: "x", count: 500)
        let clipped = AXContext.clip(text, marker: "•", maxChars: 50)
        XCTAssertTrue(clipped.hasSuffix("…"))
        XCTAssertLessThanOrEqual(clipped.count, 51)
    }
}

final class ProviderTests: XCTestCase {
    func testMetadata() {
        XCTAssertTrue(ProviderKind.anthropic.keysURL.contains("anthropic"))
        XCTAssertTrue(ProviderKind.openai.keysURL.contains("openai"))
        XCTAssertTrue(ProviderKind.gemini.keysURL.contains("google"))
        XCTAssertEqual(ProviderKind.allCases.count, 4)
    }

    func testCompatibleProvider() {
        XCTAssertFalse(ProviderKind.openAICompatible.requiresKey)
        XCTAssertTrue(ProviderKind.anthropic.requiresKey)
        XCTAssertTrue(ProviderKind.openai.requiresKey)
        XCTAssertTrue(ProviderKind.gemini.requiresKey)
        XCTAssertFalse(CompatiblePreset.all.isEmpty)
    }

    func testGeminiRoutesThroughOpenAICompatibleEndpoint() {
        // Gemini has a fixed OpenAI-compatible base URL, and the factory tags the
        // provider it builds as .gemini.
        let base = ProviderKind.gemini.fixedBaseURL
        XCTAssertNotNil(base)
        XCTAssertTrue(base?.absoluteString.contains("generativelanguage.googleapis.com") == true)
        XCTAssertEqual(AIProviderFactory.make(.gemini, baseURL: nil).kind, .gemini)
        XCTAssertNil(ProviderKind.anthropic.fixedBaseURL)
    }

    func testPresetsAreValid() {
        for preset in CompatiblePreset.all {
            XCTAssertFalse(preset.model.isEmpty, "\(preset.name) has no model")
            let url = URL(string: preset.baseURL)
            XCTAssertTrue(url?.scheme == "http" || url?.scheme == "https", "\(preset.name) base URL invalid")
        }
    }

    func testModelDefaultsAreSelectable() {
        XCTAssertTrue(AIModels.anthropicChoices.contains(AIModels.defaultAnthropic))
        XCTAssertTrue(AIModels.openAIChoices.contains(AIModels.defaultOpenAI))
        XCTAssertTrue(AIModels.geminiChoices.contains(AIModels.defaultGemini))
    }

    func testFactoryMatchesKind() {
        XCTAssertEqual(AIProviderFactory.make(.anthropic, baseURL: nil).kind, .anthropic)
        XCTAssertEqual(AIProviderFactory.make(.openai, baseURL: nil).kind, .openai)
    }
}
