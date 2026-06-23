# OpenFish

> The app's display name is **OpenFish**. The internal bundle id, Keychain
> service, and data folder keep the `Koifish` name so existing permissions and
> data carry over; the repo and Swift module are also still `Koifish`.

An open-source, bring-your-own-API-key macOS menu-bar assistant that drafts
replies **in your voice, anywhere you type**. Press a hotkey, OpenFish reads the
text field you're focused on *and the surrounding conversation*, generates a
reply that matches your style, and inserts it where your cursor is. It also does
voice dictation and learns your tone over time — all locally, with your own keys.

OpenFish is an independent, open-source project. All of its code, prompts, and
assets are original. MIT licensed.

> **This repository is open source.** All code is held to a flawless,
> idiomatic, best-practice standard — clear naming, no dead code, no force
> unwraps on untrusted input, errors handled explicitly, public behavior covered
> by tests. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Features

- **Hotkey → reply** (default: **tap Right Option ⌥**): reads the focused
  field's text (and any selection) via the Accessibility API, generates a draft,
  shows it in a floating panel to **Accept / edit / Regenerate / Cancel**, then
  inserts it.
- **Bring your own key**: Anthropic **Claude**, **OpenAI** GPT, or any
  **OpenAI-compatible** endpoint (Groq, OpenRouter, Gemini, Ollama, LM Studio).
  Keys live in your macOS **Keychain** — never on disk or in the cloud. Transient
  failures (rate-limit / 5xx) auto-retry once before surfacing.
- **Voice dictation** (default: **hold Fn to talk, release to stop**): shows a live
  soundwave, transcribes via Whisper (OpenAI or your compatible endpoint), inserts
  the text. Language auto-detects or can be pinned.
- **Reconfigurable triggers**: change the generate and dictate keys in
  **Settings → General → Behavior** — pick any of Right/Left ⌥, Right ⌘/⌃/⇧, or
  Fn, and choose tap-to-toggle or hold-to-talk for dictation. Changes apply live.
- **Learns your tone**: every accepted/edited reply is logged locally; a cheap
  model periodically distills a style profile that's fed into future drafts.
- **Menu-bar only** (`LSUIElement`) — no Dock icon, single instance.

## Requirements

- macOS 14+ to run
- **Xcode 26+ (macOS 26 SDK)** to build — the UI uses Liquid Glass APIs
- An API key for your chosen provider (any OpenAI-compatible one works for voice too)

## Build & run

```sh
# Build, bundle into OpenFish.app, and code-sign it
./scripts/setup-dev-cert.sh    # once: stable signing identity so grants survive rebuilds
./scripts/bundle.sh            # debug; use `release` for an optimized build

# Launch
open ./OpenFish.app
```

`swift build` alone produces the binary; `scripts/bundle.sh` wraps it into a
proper `.app` with `Info.plist`, the microphone entitlement, and signs it with
the stable **Koifish Dev** identity (from `setup-dev-cert.sh`) so macOS
Accessibility/Microphone grants survive rebuilds. Without that cert it falls back
to ad-hoc signing (grants reset on each code change).

## First-run setup

1. Launch the app — it appears as a fish icon in the menu bar.
2. **Settings → Permissions → Request Access** and grant **Accessibility**
   (needed to read/insert text and to install the global hotkey). Hotkeys start
   automatically once granted.
3. **Settings → General** — pick a provider and paste its key (stored in Keychain),
   or choose **Custom** for any OpenAI-compatible endpoint.
4. For voice, set **System Settings → Keyboard → "Press 🌐 key to" → Do Nothing**
   so OpenFish can use Fn.
5. In any app, type something and **tap the Right Option key**. **Hold Fn** to
   dictate — speak, then **release Fn** to stop (microphone access is requested the
   first time).

## How it works

```
tap ⌥ ─► FocusedFieldReader + AXContext    reads field, selection, and the
                                            surrounding window text (cursor-marked)
       ─► PromptBuilder + StyleProfile      grounded prompt in your voice
       ─► AIProvider (Claude/OpenAI/compat) streams the reply (BYO key from Keychain)
       ─► direct: inline placeholder in the field, replaced in place
          overlay: review panel (Accept / edit / Regenerate / Cancel)
       ─► TextInserter / InlineComposer     universal synthesized paste (⌘V)
       ─► MemoryStore                       logs the interaction; refreshes StyleProfile
```

Local data lives in `~/Library/Application Support/Koifish/`
(`style-profile.json`, `interactions.jsonl`) — open it from the menu.

| File | Role |
|---|---|
| `Sources/Koifish/Hotkey/` | `CGEventTap` global hotkey — modifier tap (Right ⌥) / hold (Fn) |
| `Sources/Koifish/Accessibility/` | read focused field, insert text, AX permission |
| `Sources/Koifish/AI/` | provider protocol, Anthropic + OpenAI, prompt builder |
| `Sources/Koifish/Voice/` | hold-to-talk capture → Whisper |
| `Sources/Koifish/Memory/` | interaction log + auto-learned style profile |
| `Sources/Koifish/Settings/` | config (UserDefaults), Keychain, SwiftUI settings |

## Models

Defaults: Claude generation on `claude-sonnet-4-6` (Opus `claude-opus-4-8`
selectable), style summaries on `claude-haiku-4-5`; OpenAI generation on
`gpt-4o`, transcription on `whisper-1`. Change the provider/model in
**Settings → General**.

## Privacy

- API keys: macOS Keychain only.
- Field text and your drafts are sent to the AI provider **you** chose, using
  **your** key. Nothing is sent anywhere else.
- Style learning is local; the only network calls are to your provider.
- Password fields and other secure inputs are not targeted.

## Known limitations (v1)

- Triggers are chosen from a set of modifier keys (tap/hold) in Settings; binding
  an arbitrary key-combo chord is supported by the model but not the picker yet.
- Fn-based triggers require the 🌐 key set to "Do Nothing" (see step 4); if macOS
  still intercepts Fn, switch the trigger to another modifier in Settings.
- Dictation transcription is batch (text appears after you stop); realtime
  streaming is on the roadmap (see `TODO.md`).
- The bundled icon is a generated placeholder — replace `Resources/AppIcon-1024.png`
  with your own art and re-run `scripts/make_icon.sh`.

## License

MIT — see [LICENSE](LICENSE). Built as a student research project.
