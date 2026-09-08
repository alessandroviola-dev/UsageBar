# UsageBar — Final Multi-Provider UI Polish

Work in the existing UsageBar project. This is a focused final correction. Do not redesign the app and do not modify FreeBar or RamBar.

## Why this pass exists

The current implementation successfully auto-detects Codex and GitHub Copilot on the development Mac, but it missed the final agreed multi-provider presentation rules.

Current incorrect active-provider menu-bar text:

```text
5H 42% | 7D 81%
```

Required:

```text
Codex 5H 42% | 7D 81%
```

The provider name must always be visible in the macOS menu bar so the user immediately knows which account/provider the quota belongs to.

The dropdown must also provide compact cached summaries for every connected provider that has valid quota data, while keeping only one active provider in the menu bar.

---

## 1. Menu-bar title — mandatory provider prefix

The status title MUST always include the active provider's concise display name.

Examples:

```text
Codex 5H 42% | 7D 81%
Copilot Premium 73% | Chat 100%
Claude 5H 68% | 7D 91%
Gemini Daily 74%
OpenRouter Credits 63%
```

Use concise status names. For GitHub Copilot, prefer `Copilot` in the menu bar rather than `GitHub Copilot` if space is materially better. The Providers window/menu may still use the full human-readable name.

Do not show an account label in the menu bar unless needed to disambiguate multiple accounts of the same provider.

When no quota snapshot exists, show the provider name plus unknown state:

```text
Codex ?
Copilot ?
```

Do not fall back to the generic `Usage ?` when an active provider is known.

Update the formatting API so provider identity is explicit rather than inferred accidentally.

Suggested shape:

```swift
UsageFormatting.statusTitle(providerName: String, snapshot: UsageSnapshot?)
```

or an equivalent clean design.

---

## 2. One active provider in the menu bar

The macOS menu bar displays exactly ONE provider/account at a time.

Do not concatenate multiple providers into the menu-bar title.

Correct:

```text
Codex 5H 42% | 7D 81%
```

Incorrect:

```text
Codex 5H 42% | Copilot Premium 73% | Gemini 80%
```

The selected provider remains persisted through the existing selected-provider preference.

---

## 3. Dropdown summary of all connected providers

When the user opens UsageBar, show a compact summary of all provider/accounts for which UsageBar currently has truthful quota data.

Example with Codex and Copilot connected:

```text
Codex        5H 42% | 7D 81%
Copilot      Premium 73% | Chat 100%

Switch Provider >
Providers…
Refresh
Launch at Login
----------------
Quit UsageBar
```

Rules:

- Show each provider at most once per configured account.
- Active provider should be identifiable, e.g. with the normal macOS checkmark or another native subtle state.
- Do not turn these rows into graphs/cards.
- Do not show providers that are `NOT INSTALLED`.
- A detected provider with no authoritative quota may be omitted from the summary and remain visible in `Providers…` with its truthful state.
- A `NEEDS CONFIG` API-key provider may remain only in `Providers…` until configured.
- Keep all text monochrome/native.

If multiple accounts of the same provider exist later, the summary may use local account labels:

```text
Codex Personal   5H 42% | 7D 81%
Codex Work       5H 90% | 7D 55%
```

but do not expose email addresses/account IDs automatically.

---

## 4. Snapshot cache for inactive connected providers

The current `UsageMonitor` only retains the active provider snapshot. Add a small cache such as:

```swift
private(set) var snapshotsByProviderID: [String: UsageSnapshot]
```

or a provider/account keyed equivalent suitable for future multi-account support.

Requirements:

- The active snapshot remains the source for the menu-bar title.
- A successful fetch updates that provider's cached snapshot.
- Switching providers should immediately use a still-fresh cached snapshot if available, then refresh asynchronously.
- A stale response from the previously active provider must never overwrite the active provider title.
- Preserve the existing generation/race protection.
- One provider failure must not erase valid cached snapshots from other providers.

Do not store credentials in this cache.

---

## 5. Refresh policy for inactive providers

Do NOT poll every provider every 60 seconds.

Keep:

- active provider: 60-second refresh

For inactive connected providers:

- refresh on startup after discovery, OR lazily the first time the menu is opened
- refresh when the user selects that provider
- refresh when `Providers…` / `Rescan Providers` makes a new connected provider available
- optionally refresh cached inactive summaries only when older than ~5 minutes

Avoid unnecessary child processes/network calls.

Manual `Refresh` should refresh the ACTIVE provider immediately. It does not need to hammer every provider.

If useful, add a distinct internal `refreshProviderSummariesIfStale()` invoked when the menu is about to open.

---

## 6. Native menu-open refresh

If needed, make `StatusBarController` an `NSMenuDelegate` and use `menuWillOpen(_:)` to request stale inactive summaries before/rebuild during the next onChange.

Do not block the main thread waiting for provider RPC/API calls.

The currently cached menu must open instantly.

---

## 7. Switch Provider behavior

`Switch Provider >` must include connected/available provider entries.

Selecting Copilot should change the menu bar from e.g.:

```text
Codex 5H 42% | 7D 81%
```

to something like:

```text
Copilot Premium 73% | Chat 100%
```

Selecting Codex changes it back.

The provider name must change immediately even if the new provider is still refreshing:

```text
Copilot ?
```

then update when quota arrives.

---

## 8. Provider display names

Define a clean distinction if helpful:

```swift
var displayName: String       // Providers window, e.g. "GitHub Copilot"
var statusName: String        // status bar, e.g. "Copilot"
```

Do not hard-code string replacements inside `StatusBarController` if a provider-level property is cleaner.

Expected concise names:

- Codex → `Codex`
- GitHub Copilot → `Copilot`
- Claude Code → `Claude`
- Gemini CLI → `Gemini`
- Cursor → `Cursor`
- OpenCode → `OpenCode`
- OpenRouter → `OpenRouter`

Keep backwards-compatible defaults where possible.

---

## 9. Codex and Copilot regression tests

Do not regress the two working local providers.

On this Mac:

- Codex: CONNECTED
- GitHub Copilot: CONNECTED

After implementation, live-test switching between both.

Record actual titles, for example:

```text
Codex title: Codex 5H XX% | 7D YY%
Copilot title: Copilot <metric> XX% | <metric> YY%
```

Quota values naturally change during testing.

---

## 10. Unit tests

Add tests for at least:

1. provider prefix included in status title
2. unknown title includes provider name
3. one-window provider title
4. two-window provider title
5. concise provider status name
6. switching provider changes prefix immediately
7. inactive cached provider does not overwrite active title
8. cached summaries retain data independently
9. failure of one provider does not clear another provider cache
10. stale inactive cache refresh policy

Update existing tests that expected bare:

```text
5H 76% | 7D 42%
```

to expect:

```text
Codex 5H 76% | 7D 42%
```

where appropriate.

---

## 11. OpenRouter semantics

Do not make OpenRouter a release blocker on this Mac because the user does not have an OpenRouter API key.

Keep implementation capability separate from local state:

- implementation can remain `FULL` if its documented non-billable credits denominator and parsing are properly fixture-tested
- `This Mac` remains `NEEDS CONFIG`
- do not claim live OpenRouter validation

Do not request an OpenRouter key from the user merely to finish this project.

---

## 12. Existing unsupported/not-installed providers

Do not treat these as a release blocker on this Mac:

- Claude Code: NOT INSTALLED
- Gemini CLI: NOT INSTALLED
- Cursor: NOT INSTALLED
- OpenCode: NOT INSTALLED

The important requirement is that discovery truthfully distinguishes them from connected providers.

Do not install third-party AI tools automatically merely to test UsageBar.

---

## 13. Documentation

Update:

- README.md
- TESTING.md
- PROVIDERS.md if needed

README examples must now show provider-prefixed titles.

Document the multi-provider rule clearly:

> UsageBar shows one selected provider in the macOS menu bar and compact cached quota summaries for all connected providers in its dropdown.

Do not describe simultaneous provider concatenation in the status bar.

---

## 14. Final validation

Run:

- debug warnings-as-errors
- release arm64 warnings-as-errors
- all XCTest
- install/reinstall
- live Codex fetch
- live Copilot fetch
- switch Codex → Copilot → Codex
- observe title provider prefix
- open dropdown and confirm both cached summaries appear
- secret scan
- confirm FreeBar/RamBar untouched

Do not mark checks PASS unless actually observed.

Sleep/wake and packet capture remain non-blocking if they were already documented `NOT TESTED`.

---

## 15. Completion status

This UI-polish phase can be `PASS` if:

1. provider name is always present in the menu-bar title
2. only one provider is shown in the status bar
3. Codex and Copilot can both be switched live
4. dropdown shows cached truthful summaries for both connected providers
5. active/inactive async results cannot corrupt each other
6. tests/build/install remain green
7. documentation matches behavior

The absence of uninstalled Claude/Gemini/Cursor/OpenCode is not a failure.

OpenRouter `NEEDS CONFIG` is not a failure.

---

## 16. Git

Keep repository PRIVATE.

Commit and push `main`.

Suggested commit:

`Polish multi-provider status display`

---

## 17. Final handoff

Return exactly:

### STATUS
PASS / PARTIAL / BLOCKED

### MENU BAR
Current active-provider title.

### CONNECTED SUMMARIES
List the exact cached dropdown summaries observed for connected providers.

### SWITCH TEST
Codex → Copilot → Codex: PASS/FAIL with observed titles.

### TESTS
Exact count / failures.

### PERFORMANCE
CPU/RSS and any new child-process behavior if materially changed.

### SECURITY
Secret scan and credential handling status.

### GIT
Commit SHA, push, visibility, clean tree.

### REMAINING ISSUES
Only genuine non-blocking or blocking issues.

Then stop.
