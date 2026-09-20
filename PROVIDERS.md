# Providers

UsageBar intentionally supports only these two providers.

| Provider | Authentication ownership | Quota source | Status requirement | Live-tested status |
|---|---|---|---|---|
| Codex | Official Codex CLI/app-server | `codex app-server` → `initialize` → `initialized` → `account/rateLimits/read` | Connected only after a successful real quota response | See `TESTING.md` |
| GitHub Copilot | Existing GitHub CLI authentication | GitHub CLI compatibility request for Copilot quota snapshots | Connected only after a successful real quota response | See `TESTING.md` |

UsageBar never reads Codex authentication files, prompts, conversations, or sessions. It never reads or stores GitHub tokens, and it has no API-key entry or credential storage.

## Copilot compatibility note

At implementation time there was no documented stable public GitHub REST endpoint that exposed an account's Copilot quota and was directly usable from this architecture. The implementation therefore invokes the existing GitHub CLI, which retains ownership of authentication, to request its currently functioning Copilot quota compatibility path. This is deliberately isolated in `CopilotProvider`; it must be live-tested on a configured account before being represented as connected.
