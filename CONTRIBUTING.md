# Contributing to Koifish

**This is an open-source project. Code is held to a flawless, best-practice
standard** — anyone may read it, so every file should be exemplary.

## Standards

- **Clarity first.** Clear names, small focused types, comments that explain
  *why* (not *what*). Match the style of surrounding code.
- **No dead code, no bloat.** Remove unused vars, params, and abstractions. Don't
  add structure for hypothetical future needs.
- **Safety.** No force-unwraps or force-casts on untrusted/runtime input (AX
  results, JSON, env, user text). Validate at boundaries; fail gracefully.
- **Errors are explicit.** Surface them to the user with actionable messages and
  log them; never swallow silently.
- **Concurrency.** UI on the main thread; long work off it. No data races.
- **Privacy.** API keys live only in the Keychain. Field/clipboard content goes
  only to the user's chosen provider with the user's key — nowhere else. Secure
  fields are never targeted.
- **Clean-room.** No third-party proprietary code, prompts, or assets. Behavior
  may be informed by public products; implementations and prompt text are ours.

## Before every change

```sh
swift build      # must be clean — zero warnings
swift test       # all tests pass; add tests for new pure logic
./scripts/bundle.sh && open ./Koifish.app   # smoke-test the real app
```

- Keep `swift build` **warning-free**.
- Add or update tests in `Tests/KoifishTests/` for any new testable logic
  (parsing, encoding, prompt building, provider wiring).
- Interactive paths (hotkeys, Accessibility, insertion, mic) can't be unit
  tested — verify them by running the app and checking `log stream`.

## Architecture

See the table in [README.md](README.md#how-it-works). Roadmap and deferred work
live in [TODO.md](TODO.md).
