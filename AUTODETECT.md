# UsageBar — Local Account Auto-Detection Phase

Work in the existing UsageBar project. Do not redesign the UI and do not modify FreeBar or RamBar.

## Product correction

UsageBar must behave like OpenUsage in one important respect: **auto-detect AI tools/accounts already authenticated on the Mac and reuse that existing login whenever safely possible.**

Do not require the user to obtain API keys for services they already use through an authenticated official CLI/desktop app.

The current Codex implementation is the reference behavior:

- detect the official local tool
- ask the official tool/account service for quota
- do not copy credentials
- do not read conversations
- do not ask the user to sign in again
- display only the normalized remaining quota

API-key entry remains available only for providers whose legitimate integration genuinely requires an API key.

## 1. Auto-discovery

Implement a small `LocalProviderDiscovery` layer.

Run discovery:

1. at UsageBar startup
2. when `Providers…` opens
3. when the user chooses `Rescan Providers`

Do not poll the whole filesystem every 60 seconds.

Look only at known provider binary/config locations and PATH/well-known Homebrew paths.

Detect at minimum:

- Codex CLI: `codex`
- Claude Code: `claude`
- Gemini CLI: `gemini`
- GitHub Copilot: standalone `copilot`, and `gh` where relevant
- Cursor: installed application/CLI and its known local state
- OpenCode if installed

A detected tool is not automatically `FULL`; it means UsageBar should attempt its safe quota adapter.

## 2. Provider states

Replace generic `UnavailableProvider` placeholders with truthful dynamic states:

- `Detected — connected`
- `Detected — quota unavailable`
- `Not installed`
- `Needs API key`
- `Needs login`
- `Unsupported`

The Providers UI should explain the real reason instead of simply saying unavailable.

Example:

```text
Codex            Connected
Claude Code      Connected
Gemini CLI       Not installed
Cursor           Detected — quota unavailable
OpenRouter       Needs API key
```

Keep the UI minimal and native.

## 3. Codex

Keep the existing implementation based on the official short-lived:

`codex app-server`

RPC:

`account/rateLimits/read`

Do not regress it.

Codex has already passed independent comparison against OpenUsage.

## 4. Claude Code — high priority

Inspect the CURRENT OpenUsage implementation under:

`janekbaraniewski/openusage/internal/providers/claude_code/`

and Claude Code's current official/local interfaces.

OpenUsage currently has a live Usage API path in addition to local statistics. Determine the exact current authentication source and endpoint rather than assuming Claude quota must be derived from conversation logs.

Preferred order:

1. official Claude CLI command/RPC that returns usage/quota, if currently available
2. official account/usage endpoint using the CLI's existing authenticated state, read only in memory
3. minimal local account metadata if it contains authoritative quota

Do **not** parse prompt or conversation text merely to estimate quota.

If a local credential/token must be read because the official CLI stores authentication locally:

- read only the minimum credential material needed
- keep it in memory only
- never copy it into UsageBar Keychain
- never print/log it
- never commit it
- send it only to Anthropic/Claude's expected host

If an authoritative percentage/reset can be retrieved, implement a real `ClaudeCodeProvider` and mark FULL after live validation.

If not, show `Detected — quota unavailable`; do not fabricate a 5-hour percentage from token history.

## 5. Gemini CLI — high priority

Inspect the CURRENT OpenUsage Gemini CLI provider.

Known current OpenUsage behavior uses:

- `gemini` binary + `~/.gemini/`
- existing OAuth state
- optional Google Cloud Code endpoints
- `loadCodeAssist`
- `retrieveUserQuota`

The relevant quota service currently uses:

`https://cloudcode-pa.googleapis.com/v1internal/`

and can return quota buckets containing remaining fractions.

Implement only the minimum necessary path for UsageBar:

- detect existing Gemini CLI login
- obtain quota through the existing OAuth account when possible
- refresh OAuth only through Google's legitimate token endpoint when required
- do not read conversation/session bodies
- do not collect token history, MCP configuration, install IDs, etc.

If a Google Cloud project is required, first attempt the existing CLI settings/environment. If none exists, show a concise provider state explaining what is missing; do not invent a project.

Never copy Gemini's existing refresh/access token into UsageBar Keychain.

## 6. GitHub Copilot — high priority

Inspect the CURRENT OpenUsage Copilot implementation and the currently installed GitHub/Copilot tooling.

Discovery should consider:

- standalone `copilot` CLI
- `gh`
- `~/.copilot/`

Prefer an official CLI/account command if it exposes quota.

OpenUsage currently uses GitHub authentication via `gh` for quota access and has historically used a Copilot account endpoint. Re-evaluate the current implementation rather than hard-coding an old endpoint.

If `gh` can act as the authenticated gateway, prefer a short-lived `gh` invocation over extracting/copying its token.

Do not parse coding-session contents unless quota snapshots are the only safe source; even then read only the quota event fields, not prompts/messages.

If a real chat/completions/premium quota is obtained, normalize the most useful one or two windows and mark FULL only after live validation.

## 7. Cursor — high priority

Inspect the CURRENT OpenUsage Cursor implementation.

Detection may use the local Cursor application state and known SQLite databases in **read-only** mode.

OpenUsage currently detects Cursor account state from its local application database. UsageBar may use equivalent local state only when necessary to talk directly to Cursor's own account/quota service.

Rules:

- open databases read-only
- retrieve only account/auth/quota-related keys
- do not inspect conversations, Composer content, prompts, projects or code
- token stays in memory only
- token is sent only to a verified Cursor-owned endpoint
- no credential is copied to UsageBar Keychain

Find the CURRENT quota endpoint/semantics from OpenUsage/current Cursor behavior; do not guess.

If a reliable quota denominator exists, implement it. Otherwise show `Detected — quota unavailable`.

## 8. OpenCode and additional locally authenticated tools

After the four priority adapters above, inspect the current OpenUsage provider/detection registry for other tools that can be auto-detected safely.

Only implement adapters that provide a truthful quota/allowance relevant to the question:

**How much usage do I have left?**

Do not port cost, token, history, model or session features.

## 9. API-key providers

Keep API-key adapters separate from local-login adapters.

OpenRouter is optional. The user does not currently have an OpenRouter API key, so OpenRouter live validation is **not a release blocker**.

Do not require OpenRouter or any other API-key service in order to call UsageBar complete for locally authenticated providers.

Providers such as OpenAI API / Anthropic API may remain `Needs API key` or `Unsupported` if there is no meaningful global percentage quota.

Do not confuse a ChatGPT/Claude subscription login with an API billing key.

## 10. Security model for existing local accounts

Important distinction:

### UsageBar-created secret

Example: manually entered OpenRouter key.

Store in macOS Keychain.

### Provider-owned existing credential

Example: Codex/Claude/Gemini/Cursor/GitHub login already owned by its official tool.

Do NOT migrate or duplicate it into UsageBar Keychain.

Use it through the official CLI/RPC if possible. If direct read access is absolutely required, use read-only/in-memory access and document exactly why.

Never modify provider auth files.

Never log secrets.

## 11. Networking

For every provider that performs direct HTTP networking, define a strict provider-specific host allowlist.

No credential may ever be sent to a host belonging to another provider.

Record expected hosts in `PROVIDERS.md` without recording URLs containing secrets.

## 12. Provider discovery UI

Add one compact menu command under Providers:

`Rescan Providers`

Do not add a permanent dashboard.

Auto-detected providers should appear automatically.

Where possible the user should not have to click `Connect` at all for an already authenticated CLI. It should simply show `Connected` after successful validation.

## 13. Tests

Add tests for:

- tool present / absent detection
- known binary paths
- detected but logged-out state
- detected and logged-in state
- no duplicate providers after repeated rescans
- local credentials never copied into UsageBar Keychain
- provider host allowlists
- malformed quota responses
- expired OAuth behavior where applicable
- account logout while UsageBar is running
- provider installation after UsageBar startup followed by rescan

Use fake HOME/config fixtures for unit tests. Never include real tokens.

## 14. Live validation on this Mac

Without asking the user for credentials, discover which supported local tools are actually installed/authenticated on this development Mac.

For each detected account, report:

```text
Provider:
Tool detected: YES/NO
Existing login detected: YES/NO
Quota source:
UsageBar display:
Validation source:
Result: PASS/PARTIAL/UNSUPPORTED
```

Do not expose account IDs, emails, access tokens or refresh tokens in the final report.

If a tool is not installed, that is not a project failure.

## 15. PROVIDERS.md semantics

Change status meaning to distinguish implementation support from this Mac's installed state.

Recommended columns:

```text
Provider | Auto-detection | Auth reuse | Quota source | Implementation | This Mac
```

Implementation values:

- FULL
- PARTIAL
- UNSUPPORTED

`This Mac` values:

- CONNECTED
- LOGGED OUT
- NOT INSTALLED
- NEEDS CONFIG
- NOT TESTED

Do not mark an adapter UNSUPPORTED merely because the corresponding app is not installed on this Mac.

## 16. Completion criteria

This phase is complete when:

1. Codex still passes.
2. UsageBar automatically discovers supported local AI tools.
3. Existing provider logins are reused without manual API keys where technically possible.
4. Providers screen clearly distinguishes not-installed vs not-logged-in vs unsupported.
5. At least Claude Code, Gemini CLI, Copilot and Cursor have been technically investigated against current implementations, not left as generic placeholders.
6. Any adapter marked FULL has a real quota denominator and live or fixture-backed validation.
7. No conversation content is needed for normal quota operation.
8. Provider credentials are never duplicated unnecessarily.
9. Tests/build/install remain green.
10. FreeBar and RamBar are untouched.

## 17. Git

Keep repository PRIVATE during this phase.

After successful work:

- update README.md
- update PROVIDERS.md
- update TESTING.md
- remove obsolete generic `UnavailableProvider` entries where dynamic detection now applies
- run secret scan
- commit
- push `main`

Suggested commit message:

`Add local provider auto-detection`

## 18. Final handoff

Return:

### STATUS
PASS / PARTIAL / BLOCKED

### AUTO-DETECTED ON THIS MAC
List provider names and CONNECTED / LOGGED OUT / NOT INSTALLED / NEEDS CONFIG.

### FULL PROVIDERS
List implementations that can truthfully display remaining quota.

### DISPLAY
Current UsageBar text.

### AUTH REUSE
For each connected provider, state only the mechanism (CLI RPC / local OAuth / read-only app state / Keychain API key). Do not expose identifiers.

### TESTS
Exact count and failures.

### SECURITY
Secret scan, credentials handling, host allowlists.

### GIT
Commit SHA, push, visibility, clean tree.

### REMAINING ISSUES
Only genuine remaining integration limitations.

Then stop.
