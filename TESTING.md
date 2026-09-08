# Testing — UsageBar 0.1.0

Overall release status: **PASS**.

Only executed checks are marked PASS.

| Check | Result | Notes |
|---|---|---|
| Debug / release arm64 build | PASS | `swift test`; `swift build -c release --arch arm64`. |
| XCTest | PASS | 22 tests, 0 failures. |
| Codex live retrieval | PASS | Authenticated official local app-server; no prompt/generation request. |
| Copilot live retrieval | PASS | Existing authenticated official GitHub CLI returned non-billable Copilot quota snapshots; no token was read or stored. |
| Local provider discovery | PASS | Fixture tests cover present/absent tools and duplicate-free registry; this Mac detected Codex and authenticated GitHub CLI. |
| Providers rescan UI | PASS | Accessibility automation opened Providers and ran Rescan; it showed connected Codex/Copilot and truthful not-installed/API-key states. |
| Copilot selected-provider UI | PASS | Accessibility automation selected the existing GitHub CLI account; UsageBar displayed `Copilot Chat 100% | Completions 100%`. |
| Multi-provider cached dropdown | PASS | Accessibility automation observed Codex and Copilot summaries together. |
| Provider-prefixed switch | PASS | Accessibility automation observed Codex → Copilot → Codex with the provider name always present in the menu-bar title. |
| Codex independent validation | PASS | OpenUsage and UsageBar both showed `5H 69% | 7D 85%` on 2026-09-08. |
| Automatic 60-second refresh | PASS | Installed app was observed spawning one short-lived Codex app-server child on its timer. |
| Manual Refresh | PASS | Accessibility automation invoked the menu action and observed the displayed quota update. |
| Provider switching | PASS | Accessibility automation switched between connected providers and returned to Codex. |
| No Dock icon | PASS | Screenshot inspection showed UsageBar in the menu bar and absent from the visible Dock; installed plist has `LSUIElement=1`. |
| Launch at Login | PASS | Accessibility automation toggled `SMAppService.mainApp`; menu mark changed absent → checked → absent. |
| Keychain round-trip/update | PASS | Isolated randomly named UsageBar Keychain items were saved, updated, read, and deleted by XCTest. |
| Install/reinstall | PASS | Installer built, signed, validated, installed and relaunched the bundle twice. |
| Uninstall | PASS | `./uninstall.sh --keep-credentials` removed only `~/Applications/UsageBar.app`; reinstall then passed. |
| Privacy manifest | PASS | Source and installed manifests passed `plutil -lint`. |
| Idle CPU / RSS | PASS | Final observed idle process: 0.0% CPU, approximately 52 MB RSS. |
| Codex child processes | PASS | Short-lived app-server child only; no persistent Codex child remained. |
| Network destination inspection | NOT TESTED | Codex/Copilot provider networking is owned by their official CLIs; no packet/connection capture was performed. |
| Sleep/wake refresh | NOT TESTED | Not safely automated without interrupting the development session. |
| FreeBar/RamBar isolation | PASS | No project files outside UsageBar were changed. |
| OpenRouter live connection | NOT TESTED | No user API key was requested or used. Sanitized parsing and host-scope tests pass. |

## Final live record

Final observed menu-bar display:

```text
Codex 5H 29% | 7D 79%
```

Connected cached summaries:

```text
Codex 5H 29% | 7D 79%
Copilot Chat 100% | Completions 100%
```

Provider switch test:

```text
Codex 5H 31% | 7D 79%
Copilot Chat 100% | Completions 100%
Codex 5H 31% | 7D 79%
```

The remaining `NOT TESTED` items are documented non-blocking observations for v0.1.0, not known defects.
