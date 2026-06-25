# Openfish

**An AI that writes in your voice, wherever you type — your keys, your machine, no middleman.**

Hit a key. Openfish reads the field you're standing in — and the conversation
around it — then fires back the reply *you* would've written, in *your* voice,
right at the cursor. Hold a key and talk; it types what you said. No web app, no
account, no telemetry, no one reading over your shoulder. Just a fish in your
menu bar that does your typing and keeps its mouth shut.

Bring your own key — Claude, GPT, Gemini, or any OpenAI-compatible endpoint. The
key sits in your Keychain and nowhere else. The only packet that ever leaves the
machine is the one *you* aim at the model *you* picked.

## Install

```sh
brew tap openfish-sh/tap
brew trust openfish-sh/tap     # Homebrew makes you vouch for third-party casks
brew install --cask openfish
```

It's self-signed, not notarized — an Apple Developer ID costs money and this is a
student project. So macOS will clutch its pearls on first launch. Open it anyway:

- **macOS 14 and older:** right-click Openfish in Applications → Open → Open.
- **macOS 15+:** try to open it, then System Settings → Privacy & Security → **Open Anyway**.

Or grab `Openfish.dmg` from [Releases](https://github.com/openfish-sh/openfish/releases) and drag it into Applications.

## Wire it up

1. A fish appears in your menu bar.
2. **Settings → Permissions → grant Accessibility.** That's the whole game —
   without it Openfish is blind and mute. Hotkeys arm the instant you grant it.
3. **Settings → pick a provider, paste your key** — Claude, OpenAI, Gemini, or
   Custom (any OpenAI-compatible endpoint).
4. For voice: **System Settings → Keyboard → "Press 🌐 key to" → Do Nothing**, so Fn is yours.
5. Anywhere you type, **tap Right Option** to draft. **Hold Fn** to dictate; release to stop.

## What it does

- **Tap → reply.** Reads the focused field plus the visible thread — it knows who
  said what — drafts in your style, drops it in place or in a review panel. Your call.
- **Hold → dictate.** Live waveform, Whisper transcription, text at the cursor.
- **Learns you.** Every reply you keep quietly sharpens a local style profile.
  No cloud, no training on you-the-product.
- **Profiles.** Keep several personalities — Personal, Work — Sales, Internal comms —
  each with its own About-you brief, voice, and separately-learned style. Switch the
  active one from the menu-bar fish (Profile ▸), or manage them in Settings → Style.
- **Your keys, four ways.** Claude · OpenAI · Gemini · anything OpenAI-compatible
  (Groq, OpenRouter, Ollama, LM Studio). Keychain only.
- **Menu-bar only.** No Dock clutter, one instance, out of your way.

## Build from source

Runs on macOS 14+. Building needs **Xcode 26 / the macOS 26 SDK** — the UI rides Liquid Glass.

```sh
./scripts/setup-dev-cert.sh   # once: stable signing so permission grants survive rebuilds
./scripts/bundle.sh release   # universal (Apple Silicon + Intel) Openfish.app
./scripts/make_dmg.sh         # optional: package Openfish.dmg
open ./Openfish.app
```

## Privacy

Keys live in the Keychain. Your text and drafts go to the provider *you* chose
with *your* key — nowhere else. Style learning is local. Password and secure
fields are invisible to it by design. There's no backend, so there's nothing to leak.

## License

MIT — see [LICENSE](LICENSE). All code is original. Built as a student research project.
