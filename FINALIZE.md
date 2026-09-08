# UsageBar — Final completion plan

Work from the existing project. Do not rewrite the application and do not touch FreeBar or RamBar.

Repository: `Ilcoach/UsageBar`

Local path: `<project-root>sageBar`

Version remains `0.1.0` until this plan is complete.

## Already accepted — do not redo unnecessarily

- Native Swift/AppKit menu-bar core exists.
- Codex uses the official local Codex app-server RPC `account/rateLimits/read`.
- Codex does not read prompts, conversations, session JSONL, or auth files.
- Remaining percentage normalization is correct: `100 - used_percent`.
- 300 minutes formats as `5H`; 10080 minutes formats as `7D`.
- Existing automated Codex validation passed.
- Independent manual validation against OpenUsage also passed on 2026-09-08:
  - OpenUsage: `5H 69% | 7D 85%`
  - UsageBar: `5H 69% | 7D 85%`
- Keychain round-trip test passed.
- Build/install/reinstall/privacy/signing passed.

Treat Codex quota correctness as PASS unless a later regression appears.

---

## Goal

Finish UsageBar as a small, truthful multi-provider usage utility in the same visual family as FreeBar and RamBar.

The menu bar remains minimal and shows at most two meaningful current values for the selected account/provider.

Do not turn it into OpenUsage.

No charts, cost dashboard, history, token breakdown, models, burn rate, notifications, themes, analytics, daemon, or remote UsageBar backend.

---

## 1. Close every remaining macOS acceptance test

Actually run and record each item in `TESTING.md` as PASS / FAIL / NOT TESTED. Do not infer success from code presence.

Required observations:

1. automatic 60-second refresh
2. manual `Refresh` menu action
3. provider/account switching
4. no Dock icon
5. Launch at Login toggle using `SMAppService.mainApp`
6. login item state reflects reality after toggling
7. uninstall
8. reinstall after uninstall
9. CPU at idle and during refresh
10. RSS
11. child-process behavior during Codex refresh
12. no persistent Codex app-server child
13. FreeBar and RamBar remain running/unmodified
14. sleep/wake refresh if safely testable

If a GUI action cannot be safely automated, leave it clearly marked for one final human click-test instead of fabricating PASS.

---

## 2. Codex process hardening

The current implementation uses a short-lived Codex app-server child per refresh.

Review this carefully.

Requirements:

- never allow overlapping app-server children
- enforce a timeout
- terminate/reap the child on timeout/cancellation/app quit
- coalesce refresh requests
- stale older results must never overwrite newer state
- no zombie processes
- no shell polling
- no prompt/generation request
- preserve 60-second refresh

Measure the real child-process lifetime and document it.

If a persistent app-server would materially reduce overhead without complicating lifecycle/security, evaluate it, but do not change architecture merely for elegance. Prefer the smallest robust design.

---

## 3. Provider architecture must become real, not placeholder-only

The current registry contains several `UnavailableProvider` placeholders. Replace placeholders with real adapters where a secure, useful implementation is possible.

Use current `janekbaraniewski/openusage` source and provider docs as an MIT-licensed engineering reference, together with official provider documentation where available.

Do not add OpenUsage as a runtime dependency.

Do not invoke the OpenUsage executable to power UsageBar.

If source is materially adapted, preserve required MIT attribution.

---

## 4. Provider categories

Implement connection support in this priority order.

### A. Existing local authenticated tools

Investigate and implement safe quota/balance retrieval where possible for:

- Claude Code
- Cursor
- GitHub Copilot
- Gemini CLI
- OpenCode

Use official local state/RPC/API where possible.

Do not read conversation contents just to calculate quota.

Do not scrape prompts/messages.

If a tool only exposes usage by parsing conversation history and there is no real quota source, do not pretend that local activity equals subscription quota.

### B. API-key providers

Implement secure account connection through macOS Keychain for as many of the current OpenUsage API providers as can be supported safely, including where applicable:

- OpenAI
- Anthropic
- OpenRouter
- Azure OpenAI
- Groq
- Mistral
- DeepSeek
- Moonshot/Kimi
- Perplexity only if a safe legitimate auth mechanism exists
- xAI
- Z.AI
- Google Gemini API
- Alibaba Cloud
- OpenCode/Zen
- other currently supported OpenUsage API platforms discovered during implementation

Do not hard-code this list as permanently complete; inspect the current OpenUsage provider matrix first.

---

## 5. Connection support and display support are different

UsageBar should be able to connect an account even when that provider cannot expose a meaningful global percentage.

Use truthful capability levels:

- `FULL`: secure connection + meaningful current remaining quota/allowance can be displayed
- `PARTIAL`: secure connection and useful account/usage/balance data exists, but no mathematically valid global remaining percentage
- `UNSUPPORTED`: no safe/reliable implementation

Do not mark a provider FULL merely because authentication works.

Update `PROVIDERS.md` with the real result.

---

## 6. Do not invent percentages

A percentage may only be displayed when both current remaining/used quantity and denominator/limit are known from trustworthy data.

Valid examples:

- `remaining = 100 - used_percent`
- `(limit - used) / limit * 100`
- `credit_balance / fixed_allowance * 100` only when the allowance is actually known

Invalid examples:

- spend today divided by an arbitrary number
- balance with unknown original allowance
- token counts treated as quota
- local session activity treated as subscription remaining

For PARTIAL providers, the dropdown may show a compact absolute value such as balance/credits if useful, but the menu-bar status must not fabricate `%`.

If a selected PARTIAL provider has no valid percentage, use a truthful compact title such as `Credits $12.40`, `Balance 8.2`, or `Usage ?` depending on what the provider actually exposes.

Never show more than two primary values.

---

## 7. No billable probes

Absolutely never send an AI generation request merely to obtain rate-limit headers.

No automatic prompts to OpenAI, Anthropic, Gemini, xAI, etc.

Use non-billable account, billing, quota, balance, subscription, rate-limit or official local endpoints.

If a provider exposes useful rate-limit headers only on billable model calls, classify that capability PARTIAL/UNSUPPORTED rather than polling it.

---

## 8. Authentication security

All UsageBar-created secrets must use Security.framework / macOS Keychain service namespace:

`com.alessandroviola.usagebar`

Never store secrets in UserDefaults, plist, JSON, logs, README, tests, source, or shell history generated by the app.

For API-key providers use a secure native entry sheet.

For OAuth:

- only use legitimate documented third-party OAuth flows
- system browser
- PKCE where required
- never steal another app's OAuth client credentials
- never emulate private first-party clients

For existing CLI authentication:

- prefer official RPC/API access
- do not copy tokens unless technically unavoidable
- never display/log them

Disconnect must remove only UsageBar-owned credentials/state, never the provider CLI's own login unless the user explicitly authenticated through UsageBar and the mechanism requires it.

---

## 9. Network security

UsageBar has no backend.

Remote traffic must go directly to the configured provider.

Each remote provider adapter must define/validate legitimate hosts.

Requirements:

- HTTPS by default
- credential for provider A must never be sent to provider B
- no analytics
- no telemetry
- no update checker
- no UsageBar server
- no unexpected endpoints

For user-defined Azure/custom endpoints, validate and display the endpoint explicitly.

Inspect actual network destinations during tests without logging Authorization headers.

---

## 10. Provider setup UI

Keep the existing small Providers window, but make it genuinely useful.

It should support:

- provider list
- connection state
- Connect / Add Key where appropriate
- Disconnect
- multiple accounts where feasible
- local display name
- active account selection

Do not build a large settings application.

For API keys use `NSSecureTextField` or equivalent.

Provider/account identifiers may be persisted in UserDefaults; secrets may not.

---

## 11. Status/menu behavior

Normal menu-bar style remains CLI-like and monochrome.

Codex example:

`5H 69% | 7D 85%`

Dropdown example:

```text
Codex

5H      69%     reset 18:52
7D      85%     reset 15 Sep

Switch Provider >
Providers…

Refresh
Launch at Login
----------------
Quit UsageBar
```

Keep reset time in local timezone.

No second-by-second countdown.

If refresh fails temporarily, keep recent valid data and indicate stale/error state only in the dropdown.

Do not replace a good menu-bar value with noisy error text after one transient failure.

---

## 12. Refresh/backoff

Active provider default refresh remains 60 seconds unless a provider requires a slower safe interval.

Inactive providers should not be continuously polled.

Refresh them when selected or explicitly requested.

Respect provider rate limits and `Retry-After`.

Use bounded exponential backoff for repeated failures.

Manual Refresh may bypass normal TTL but must still respect an active server-directed rate-limit delay.

---

## 13. Tests

Expand XCTest coverage substantially.

At minimum add tests for:

- provider/account identity
- Keychain create/read/update/delete
- no secret persistence in UserDefaults
- response parsing for every implemented provider using sanitized fixtures
- quota arithmetic
- percentage clamping
- absolute-value formatting for PARTIAL providers
- reset formatting/timezones
- stale refresh protection
- coalescing
- timeout/error behavior
- provider switching
- credential-to-host scoping
- malformed API responses
- 401/403 handling
- 429 / Retry-After behavior
- network error preserving stale good value

Never include real keys/tokens/account IDs in fixtures.

Run warnings-as-errors for debug and release where practical.

---

## 14. Performance

Measure installed UsageBar after several refreshes.

Record:

- idle CPU
- CPU around refresh
- RSS
- number/lifetime of Codex child processes
- network connections while idle

Target idle CPU approximately 0%.

Do not introduce Electron, Node, Python, Go helpers, OpenUsage daemon, or other persistent runtimes.

---

## 15. Installer/uninstaller

Re-run and harden both scripts.

Installer must remain:

- no sudo
- safe replacement
- rollback on launch failure
- arm64 release build
- plist validation
- privacy manifest packaging
- ad-hoc signing
- installed bundle verification

Uninstaller must:

- stop only UsageBar
- unregister UsageBar Launch at Login
- remove only UsageBar app/preferences
- remove UsageBar-created Keychain secrets by default in non-interactive mode
- offer `--keep-credentials`
- never remove Codex/Claude/Gemini/GitHub/provider-owned CLI auth
- never touch FreeBar or RamBar

Actually test uninstall and reinstall afterward.

---

## 16. Privacy manifest

Review the manifest again after provider/network/UI expansion.

Declare only APIs actually used and their correct required reasons.

Validate both source and installed copy.

---

## 17. Documentation

Update:

- `README.md`
- `PROVIDERS.md`
- `TESTING.md`

README should remain concise and public-quality.

Document exactly what `%` means and that provider capability varies.

Do not claim every OpenUsage provider is supported unless it actually is.

Mention OpenUsage attribution if code/logic was materially adapted.

---

## 18. Secret scan

Before every final commit, search the repository for likely secrets and sensitive captures.

Reject commit if it contains:

- bearer token
- API key
- auth cookie
- OAuth refresh token
- Codex auth file
- provider account identifier from a real live payload
- local session transcript

---

## 19. Git

First integrate any remote documentation changes cleanly.

Do not force push.

Work on `main` unless a branch is genuinely useful.

Final commit suggestion:

`Complete UsageBar provider and lifecycle hardening`

Push to `origin/main`.

Keep repository PRIVATE until the project passes the final acceptance review.

---

## 20. Final acceptance

Do not declare PASS until all of these are true or explicitly documented as provider-specific limitations:

- Codex independent validation PASS
- automatic refresh observed
- manual refresh observed
- no Dock icon observed
- Launch at Login observed
- uninstall/reinstall PASS
- CPU/RSS measured
- Codex children controlled and reaped
- no telemetry/backend
- secrets only in Keychain where UsageBar owns them
- real provider adapters implemented where safely possible
- `PROVIDERS.md` truthful
- tests pass
- privacy manifest valid
- FreeBar/RamBar untouched
- secret scan PASS
- git pushed and clean

If some provider cannot supply a true remaining quota, that is not a project failure; classify it honestly as PARTIAL or UNSUPPORTED.

---

## Final handoff format

Return only:

### STATUS
PASS / PARTIAL / BLOCKED

### DISPLAY
Current real menu-bar display.

### CODEX
Independent validation status and current values.

### PROVIDERS
FULL / PARTIAL / UNSUPPORTED counts and names of FULL providers.

### GUI/LIFECYCLE
Refresh, provider switch, Dock, Launch at Login, sleep/wake, uninstall/reinstall.

### TESTS
Exact test count and failures.

### PERFORMANCE
CPU, RSS, Codex child lifetime/count, refresh interval.

### SECURITY
Keychain, secret scan, telemetry/backend, observed outbound hosts.

### GIT
Branch, final commit SHA, push status, visibility, working-tree status.

### REMAINING ISSUES
Only genuine unresolved items.

Then stop.
