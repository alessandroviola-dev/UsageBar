# UsageBar — Local Account Auto-Detection Phase

Work in the existing UsageBar project. Do not modify FreeBar or RamBar.

## Product correction

UsageBar must behave like OpenUsage in one important respect: **auto-detect AI tools/accounts already authenticated on the Mac and reuse that existing login whenever safely possible.**

Do not require API keys for services already used through an authenticated official CLI/desktop app.

The current Codex implementation is the reference behavior:

- detect the official local tool
- ask the official tool/account service for quota
- do not copy credentials
- do not read conversations
- do not ask the user to sign in again
- display only normalized remaining quota

API-key entry remains only for providers whose legitimate integration genuinely requires one.

## 1. Status-bar behavior — IMPORTANT

The provider name MUST always be visible in the macOS menu bar so the user immediately knows which quota is being shown.

Examples:

```text
Codex 5H 53% | 7D 82%
Claude 5H 68% | 7D 91%
Gemini Daily 74%
Copilot Premium 61%
OpenRouter Credits 83%
```

Do not show an unlabeled value such as:

```text
5H 53% | 7D 82%
```

The provider label should be concise and human-readable:

- `Codex`
- `Claude`
- `Gemini`
- `Copilot`
- `Cursor`
- `OpenCode`
- `OpenRouter`

Do not include the account name in the menu-bar title unless required to disambiguate two accounts of the same provider.

## 2. Multiple providers

UsageBar must support multiple connected/detected providers simultaneously, but the menu bar shows only ONE **active provider** at a time.

Never concatenate every provider into one huge status title.

Example with four connected providers:

```text
Menu bar:
Codex 5H 53% | 7D 82%
```

Clicking UsageBar should show a compact summary of all connected providers:

```text
Codex      5H 53% | 7D 82%
Claude     5H 68% | 7D 91%
Gemini     Daily 74%
Copilot    Premium 61%

Switch Provider >
Providers…
Refresh
Launch at Login
----------------
Quit UsageBar
```

The summary should include only providers for which UsageBar has a meaningful current quota value. Detected providers without a usable quota may appear in `Providers…` but should not clutter the main menu summary.

`Switch Provider >` lists available connected providers/accounts. Selecting one immediately makes it the active provider and updates the menu-bar title.

Persist the active provider/account identifier in UserDefaults. Never store secrets there.

If the active provider becomes unavailable or logged out:

- keep the last successful value for a sensible stale period
- indicate the error in the dropdown
- do not silently switch providers unless there is no longer a valid active provider
- if a fallback selection is required, pick another connected provider deterministically and document the behavior

## 3. Multiple accounts for the same provider

Design identities so multiple accounts remain possible, for example:

```text
Codex Personal
Codex Work
```

The dropdown / Providers window must distinguish them.

The menu bar may remain compact:

```text
Codex 5H 53% | 7D 82%
```

If two accounts of the same provider are simultaneously configured and ambiguity would be harmful, use a short account label, for example:

```text
Codex Work 5H 53% | 7D 82%
```

Do not expose emails or account IDs in the menu-bar title by default.

## 4. Auto-discovery

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
- Cursor: installed application/CLI and known local state
- OpenCode if installed

A detected tool is not automatically FULL; it means UsageBar should attempt its safe quota adapter.

## 5. Provider states

Replace generic `UnavailableProvider` placeholders with truthful dynamic states:

- `Detected — connected`
- `Detected — quota unavailable`
- `Not installed`
- `Needs API key`
- `Needs login`
- `Unsupported`

Example:

```text
Codex            Connected
Claude Code      Connected
Gemini CLI       Not installed
Cursor           Detected — quota unavailable
OpenRouter       Needs API key
```

Keep the UI minimal and native.

## 6. Codex

Keep the existing implementation based on the official short-lived:

`codex app-server`

RPC:

`account/rateLimits/read`

Do not regress it.

Codex has already passed independent comparison against OpenUsage.

Expected title style:

`Codex 5H XX% | 7D YY%`

## 7. Claude Code — high priority

Inspect the CURRENT OpenUsage implementation under:

`janekbaraniewski/openusage/internal/providers/claude_code/`

and Claude Code's current official/local interfaces.

Determine the exact current authentication source and authoritative usage/quota source rather than deriving quota from conversation logs.

Preferred order:

1. official Claude CLI command/RPC exposing usage/quota
2. official account/usage endpoint using the CLI's existing authenticated state, read only in memory
3. minimal local account metadata if it contains authoritative quota

Do not parse prompt or conversation text merely to estimate quota.

If a local credential/token must be read:

- minimum material only
- memory only
- never copy to UsageBar Keychain
- never print/log it
- send only to Anthropic/Claude expected hosts

If an authoritative percentage/reset can be retrieved, implement a real `ClaudeCodeProvider` and mark FULL after validation. Otherwise show `Detected — quota unavailable`.

## 8. Gemini CLI — high priority

Inspect the CURRENT OpenUsage Gemini CLI provider.

Known relevant behavior includes:

- `gemini` binary + `~/.gemini/`
- existing OAuth state
- optional Google Cloud Code endpoints
- `loadCodeAssist`
- `retrieveUserQuota`
- `https://cloudcode-pa.googleapis.com/v1internal/`

Implement only the minimum needed for quota:

- detect existing Gemini CLI login
- obtain quota through existing OAuth when possible
- refresh OAuth only through Google's legitimate token endpoint when required
- do not read conversation/session bodies
- do not collect token history, MCP config, install IDs, etc.

If a Google Cloud project is required, first inspect existing CLI settings/environment. If missing, show `Needs config`; do not invent a project.

Never duplicate Gemini OAuth tokens into UsageBar Keychain.

## 9. GitHub Copilot — high priority

Inspect the CURRENT OpenUsage Copilot implementation and installed GitHub/Copilot tooling.

Discovery should consider:

- standalone `copilot` CLI
- `gh`
- `~/.copilot/`

Prefer an official CLI/account command if it exposes quota.

If `gh` can act as the authenticated gateway, prefer a short-lived `gh` invocation over extracting/copying its token.

Do not parse coding-session contents unless quota snapshots are genuinely the only safe source; if necessary read only quota event fields, never prompts/messages.

If a real chat/completions/premium quota is available, normalize the most useful one or two limits and validate before marking FULL.

## 10. Cursor — high priority

Inspect the CURRENT OpenUsage Cursor implementation.

Detection may use local Cursor application state and known SQLite databases in **read-only** mode.

Rules:

- databases read-only
- retrieve only account/auth/quota-related keys
- do not inspect conversations, Composer content, prompts, projects or code
- token stays in memory only
- token sent only to verified Cursor-owned endpoints
- no credential copied to UsageBar Keychain

Find CURRENT quota endpoint/semantics; do not guess.

If a reliable denominator exists, implement it. Otherwise show `Detected — quota unavailable`.

## 11. OpenCode and additional local tools

After the priority adapters, inspect the current OpenUsage detection/provider registry for other tools that can be auto-detected safely.

Only implement adapters that answer:

**How much usage do I have left?**

Do not port cost, token history, sessions, models, projects, burn rate or dashboard features.

## 12. API-key providers

Keep API-key adapters separate from local-login adapters.

OpenRouter is optional. The user does not currently have an OpenRouter API key, so OpenRouter live validation is NOT a release blocker.

Do not require OpenRouter or any other API-key provider to call the locally authenticated core complete.

Do not confuse ChatGPT/Claude subscription login with API billing credentials.

## 13. Security model

### UsageBar-created secret

Example: manually entered OpenRouter key.

Store in macOS Keychain.

### Provider-owned existing credential

Example: Codex/Claude/Gemini/Cursor/GitHub login already owned by its official tool.

Do NOT migrate or duplicate it into UsageBar Keychain.

Use official CLI/RPC where possible. If direct read access is unavoidable, use read-only/in-memory access and document why.

Never modify provider auth files.
Never log secrets.

For direct HTTP networking, define strict provider-specific host allowlists.

No credential may ever be sent to another provider's host.

## 14. Discovery / Providers UI

Add:

`Rescan Providers`

Auto-detected authenticated providers should normally require no manual `Connect` action; they should appear as Connected after successful validation.

The Providers window must distinguish:

- installed vs not installed
- logged in vs logged out
- quota available vs unavailable
- manual API key required
- unsupported

The normal menu is NOT a dashboard. Keep the multi-provider quota summary compact.

## 15. Refresh policy with multiple providers

The active provider remains the highest priority and should refresh on the existing cadence.

For other connected providers shown in the dropdown summary:

- do not hammer every provider every 60 seconds if that would be wasteful
- use sensible provider-specific caching/TTL
- refresh when the menu opens if stale
- refresh immediately when selected as active
- respect rate limits and Retry-After

The menu should never block while all providers refresh. Use cached values and update asynchronously.

Prevent stale async responses from an old provider selection overwriting the new active provider title.

## 16. Tests

Add tests for:

- tool present / absent detection
- known binary paths
- detected but logged-out state
- detected and logged-in state
- no duplicate providers after rescans
- local credentials never copied into UsageBar Keychain
- provider host allowlists
- malformed quota responses
- expired OAuth behavior where applicable
- account logout while UsageBar runs
- installation after startup + rescan
- status title always includes provider label
- active provider switching changes title
- multiple providers appear in dropdown summary
- disconnected/no-quota providers do not pollute the main quota summary
- multiple accounts of one provider remain distinguishable
- stale response from provider A cannot overwrite provider B after switching

Use fake HOME/config fixtures. Never include real tokens.

## 17. Live validation on this Mac

Without asking for credentials, discover which supported local tools are installed/authenticated.

For each detected account report:

```text
Provider:
Tool detected: YES/NO
Existing login detected: YES/NO
Quota source:
UsageBar display:
Validation source:
Result: PASS/PARTIAL/UNSUPPORTED
```

Do not expose account IDs, emails, access tokens or refresh tokens.

If a tool is not installed, that is not a project failure.

Also validate the multi-provider UX with every connected provider found on this Mac:

- menu-bar title includes active provider name
- switching provider updates title correctly
- dropdown shows concise current quotas for all connected providers with usable quota

## 18. PROVIDERS.md semantics

Use columns:

```text
Provider | Auto-detection | Auth reuse | Quota source | Implementation | This Mac
```

Implementation:

- FULL
- PARTIAL
- UNSUPPORTED

This Mac:

- CONNECTED
- LOGGED OUT
- NOT INSTALLED
- NEEDS CONFIG
- NOT TESTED

Do not mark implementation UNSUPPORTED merely because the app is absent from this Mac.

## 19. Completion criteria

This phase is complete when:

1. Codex still passes.
2. The menu-bar title always identifies the active provider.
3. Multiple connected providers can coexist without creating an excessively long menu-bar title.
4. The dropdown gives a concise quota summary for all connected providers with meaningful quota.
5. Switching active provider updates the title immediately and safely.
6. UsageBar automatically discovers supported local AI tools.
7. Existing provider logins are reused without manual API keys where technically possible.
8. Providers UI distinguishes not-installed vs logged-out vs unsupported vs quota-unavailable.
9. Claude Code, Gemini CLI, Copilot and Cursor are technically investigated against current implementations, not generic placeholders.
10. Any adapter marked FULL has a real quota denominator and validation.
11. No conversation content is needed for normal quota operation.
12. Provider credentials are never duplicated unnecessarily.
13. Tests/build/install remain green.
14. FreeBar and RamBar are untouched.

## 20. Git

Keep repository PRIVATE during this phase.

After successful work:

- update README.md
- update PROVIDERS.md
- update TESTING.md
- remove obsolete generic placeholders where dynamic detection applies
- run secret scan
- commit
- push `main`

Suggested commit message:

`Add local provider auto-detection and switching`

## 21. Final handoff

Return:

### STATUS
PASS / PARTIAL / BLOCKED

### AUTO-DETECTED ON THIS MAC
List providers and CONNECTED / LOGGED OUT / NOT INSTALLED / NEEDS CONFIG.

### FULL PROVIDERS
List implementations that can truthfully display remaining quota.

### ACTIVE DISPLAY
Exact current menu-bar text, including provider name.

### MULTI-PROVIDER MENU
List the concise quota rows currently shown for every connected provider.

### AUTH REUSE
For each connected provider, mechanism only: CLI RPC / local OAuth / read-only app state / Keychain API key.

### TESTS
Exact count and failures.

### SECURITY
Secret scan, credentials handling, host allowlists.

### GIT
Commit SHA, push, visibility, clean tree.

### REMAINING ISSUES
Only genuine remaining integration limitations.

Then stop.
