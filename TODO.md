# Koifish — pre-launch backlog

Tracked items to address before a public launch. Ordered roughly by priority.

## Big features

### 1. Cross-window "memory" — advanced tiers
**Shipped (v1):** a **text-only, opt-in** recent-activity buffer (`ActivityMemory` /
`ActivityRecorder`). Captures the focused window's text on app activation, keeps ~30 min
in memory (never on disk), and feeds a compact "recent other windows" digest into the
prompt. Off by default; menu + Settings toggle; buffer cleared when turned off; skips
OpenFish's own windows and (via AX) secure fields. This covers the common case — drafting
in Docs, then replying in Slack — without screen recording.

**Still to do (heavier, more privacy-sensitive):**
- **Screenshots** alongside text (captures non-text UI). Needs Screen Recording TCC
  permission — add to onboarding only when enabled.
- **Longer-term activity history** persisted locally (user-inspectable and
  deletable), beyond the in-memory recent buffer.
- **Semantic search** over history + typed extraction of open items (promises, blockers, to-dos).
- Expose memory to the model as **tools** (recent-activity lookup, history search, …)
  rather than a static digest.

**Hard requirements for those tiers** (the v1 text buffer already meets the first four):
- Explicit, informed **opt-in**; off by default. ✓ (v1)
- **Local-only**; user-inspectable and deletable. (v1 is in-memory; on-disk store needs a deletion path.)
- Easy **pause / "stop watching"** + a visible indicator. ✓ (v1)
- Redaction / exclusion for sensitive apps and secure fields. ✓ secure fields; per-app exclude list still TODO.
- Screen Recording TCC permission only when screenshots are enabled.
- Bounded retention + size caps; clear data-deletion path.

### 2. Meeting notes (à la anarlog / Granola)
Record a call, transcribe it, and generate markdown notes — local-first, BYOK.
We already have ~40%: mic capture, Whisper transcription, LLM plumbing, file storage.
The new work, roughly in order of difficulty:
- **System-audio capture** (the hard part): the *other* participants' audio, not just the
  mic. ScreenCaptureKit (macOS 13+) or the macOS 14.4+ Core Audio process-tap API, plus a
  Screen Recording TCC permission.
- **Long-form chunked transcription** pipeline (optional speaker diarization) — heavier than
  the current push-to-talk dictation.
- **A notes window** — OpenFish is menu-bar-only today; viewing/editing notes needs a real
  window + session management.
- **Summarize-to-notes** prompt + markdown store (easy; reuses existing pieces).
Moderately large — a distinct product surface, not a small add. Native (ScreenCaptureKit +
on-device options) would beat anarlog's Tauri stack here.

## Updates & monetization
- **Auto-updates** via Sparkle — now unblocked (Apple Developer ID available). Needs
  Developer ID signing + notarization, an appcast feed (GitHub Releases), and EdDSA-signed
  builds.
- **14-day free trial, then one-time purchase.** A licensing layer: a local trial countdown,
  then a license-key check once bought. One-time payment + key issuance via Gumroad / Lemon
  Squeezy / Paddle (no backend to operate). Needs some tamper-resistance on the trial clock,
  and a grace path for the BYOK-only crowd.

## Polish / smaller items
- **Realtime/streaming dictation** — text as you speak (needs a streaming STT:
  OpenAI realtime websocket, or a local streaming model). Current dictation is batch.
- **Local whisper.cpp** — fully offline transcription, no key (bundling effort).
- **Chord hotkey recorder** — Behavior settings now offer modifier-key triggers
  (tap/hold); a live recorder for arbitrary key-combo chords (e.g. ⌥Space) is
  still to do. The `HotkeyTrigger.chord` case already exists in the model.
- **Inline insertion robustness** — paste-based dots avoid autocorrect drift, but
  backspace-count deletion could still drift if synthesized keystrokes are dropped
  in some apps; consider a select-back fallback where supported.

## Distribution (before a public download)
- **Developer ID signing + notarization** so a downloaded build opens without the
  Gatekeeper prompt — Apple Developer account now available; `bundle.sh` still uses a local
  self-signed cert, so wire the real identity + a `notarytool` step. (Also kills the repeated
  Keychain "allow" prompts.)
- ~~A GitHub Release with a `.zip`/`.dmg` artifact~~ — **done** (v0.1.0 + Homebrew tap cask,
  `brew install --cask openfish-sh/tap/openfish`).
- **README screenshots / demo GIF** of the overlay, inline mode, and dictation.

## Done (for reference)
- Renamed to **OpenFish** (display name; bundle id kept for grant/key continuity).
- Generated app icon (replaceable via `Resources/AppIcon-1024.png` + `make_icon.sh`).
- Universal insertion via synthesized paste/keystrokes (terminals, Chrome, Safari, native).
- In-field animated placeholder (random word) for direct mode.
- OpenAI-compatible "Custom" provider (Groq/OpenRouter/Gemini/Ollama/LM Studio) — text + voice.
- Dictation: Fn tap-to-toggle, BYOK Whisper, live soundwave, language hint; single
  in-place HUD (soundwave → "Transcribing…" in one box).
- Window-context gathering + grounded prompt for relevant, short, human replies.
- In-app hotkey configuration (modifier-key picker, tap/hold, live reload).
- 429/5xx + network auto-retry (one backoff retry, honors `Retry-After`).
- Swift 6 strict concurrency (language mode v6).
- Stable self-signed dev signing (TCC grants survive rebuilds).
- Liquid Glass settings/overlay; unified provider+key+model page.
- `swift test` suite (41 tests); GitHub Actions CI on macOS 26.
