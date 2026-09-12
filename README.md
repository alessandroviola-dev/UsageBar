# UsageBar

Menu bar: `Codex 5H 23% | 7D 50%`

Codex menu: `Codex 5H 23% 02:34H | 7D 50% 3D 07:12H`

A tiny native macOS menu-bar utility for AI usage limits.

UsageBar shows **remaining** quota for one selected provider, with at most two meaningful percentage limits. The menu bar always prefixes the active provider and deliberately has no reset countdown. The Codex row in the dropdown adds compact reset countdowns (`HH:MMH`, or `dD HH:MMH`) to its truthful cached summary; other connected providers retain their normal compact summaries. It is deliberately not a dashboard: no charts, costs, tokens, history, notifications, or Dock icon.

**v0.1.0 status: PASS.** Codex and GitHub Copilot are live-validated on the development Mac; OpenRouter support is implemented but optional and requires a user-supplied API key.

## Providers

v0.1.0 auto-detects local Codex, Claude Code, Gemini CLI, GitHub Copilot, Cursor, and OpenCode installations. Codex uses its official local `app-server` RPC (`account/rateLimits/read`); GitHub Copilot reuses the authenticated `gh` CLI to retrieve quota data. Tools without a safe quota source are clearly shown as not installed, needing login, or quota unavailable rather than guessed.

The app does not read Codex sessions, prompts, conversations, or authentication files. It asks the selected authenticated provider for a non-billable quota snapshot every 60 seconds, plus on manual refresh or provider selection.

OpenRouter can be connected from the Providers window with an API key. Use **Rescan Providers** after installing or signing in to a local tool. Its credits endpoint supplies purchased and consumed credit, so `Credits XX%` has a real denominator. Other providers are only listed where no safe truthful adapter is implemented.

The menu-bar labels derive from the reported window duration, so a 300-minute window becomes `5H` and a 10080-minute window becomes `7D`. Values are `100 - used_percent`, clamped to `0...100`. Codex reset times are shown only in its dropdown row, rounded up to the next minute: `02:34H` or `3D 07:12H`.

See [PROVIDERS.md](PROVIDERS.md) for truthful provider status.

## Security and privacy

- OpenRouter API keys entered in the Providers window use the macOS Keychain, never UserDefaults or files.
- Existing Codex and GitHub CLI credentials are not copied; authentication remains owned by the official provider tools.
- Credentials never leave the Mac except directly to their configured provider.
- There is no UsageBar server, telemetry, analytics, tracking, backend, or remote sync.
- UsageBar makes no billable AI generation request to discover a quota.

## Install

```bash
git clone https://github.com/alessandroviola-dev/UsageBar.git
cd UsageBar
./install.sh
```

This creates `~/Applications/UsageBar.app`, validates its plists, ad-hoc signs it, safely replaces a previous UsageBar installation, and launches it.

## Uninstall

```bash
./uninstall.sh
```

The interactive uninstaller asks about UsageBar-created Keychain entries. Non-interactive use removes those entries by default; `--keep-credentials` preserves them. It never removes provider CLI authentication.

## Development

```bash
swift test
swift build -c release --arch arm64
```

See `TESTING.md` for the executed validation matrix.

## Limitations

- Provider quota interfaces can change over time; Codex app-server and GitHub Copilot quota behavior may require future adapter updates.
- OpenRouter is implemented but was not live-tested without a user-supplied API key.
- Claude Code, Gemini CLI, Cursor, OpenCode, and other listed providers are only shown when UsageBar can report a truthful supported state; unsupported quota data is never fabricated.

## License

MIT.
