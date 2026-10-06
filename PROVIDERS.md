# Providers

UsageBar intentionally supports only these two providers.

| Provider | Authentication ownership | Quota source | Status requirement | Live-tested status |
|---|---|---|---|---|
| Codex | Official Codex CLI/app-server | `codex app-server` → `initialize` → `initialized` → `account/rateLimits/read` | Connected only after a successful real quota response | See `TESTING.md` |
| GitHub Copilot | Existing GitHub CLI authentication | GitHub CLI compatibility request for Copilot quota snapshots | Connected only after a successful real quota response | See `TESTING.md` |

UsageBar never reads Codex authentication files, prompts, conversations, or sessions. It never reads or stores GitHub tokens, and has no API-key entry UI. Quota credentials remain with Codex and GitHub CLI.

## Separate cost metrics

OpenAI billing is **not** a third quota provider. `OpenAI billed cost (30d)` reads the official Organization Costs API for a rolling 30-day interval, including pagination; valid zero is authoritative and errors show unavailable. Its optional Admin API key is kept in macOS Keychain (service `UsageBar.OpenAI.AdminAPIKey`, account `NSUserName()`), never in preferences or files and never displayed/logged.

`OpenAI observed local` is a separate read-only sum of valid `assistant_message.usage.costTotal` from the available ForgeApis telemetry file. It has no 30-day claim and never replaces official billing. Jev likewise reads local data without modifying ForgeJev/ForgeApis: post-baseline accounting uses only input tokens at $42/billion and deduplicates canonical request IDs across ledgers and shared traces.

Manual Refresh updates provider data, Jev and both OpenAI metrics. Automatic refresh is about 60 seconds for local observations and 300 seconds for official billing.

## Copilot compatibility note

At implementation time there was no documented stable public GitHub REST endpoint that exposed an account's Copilot quota and was directly usable from this architecture. The implementation therefore invokes the existing GitHub CLI, which retains ownership of authentication, to request its currently functioning Copilot quota compatibility path. This is deliberately isolated in `CopilotProvider`; it must be live-tested on a configured account before being represented as connected.
