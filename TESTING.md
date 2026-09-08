# Testing — UsageBar 0.1.0

Only executed checks are marked PASS.

| Check | Result | Notes |
|---|---|---|
| Debug / release arm64 build | PASS | `swift test`; `swift build -c release --arch arm64`. |
| XCTest | PASS | 17 tests, 0 failures. |
| Codex live retrieval | PASS | Authenticated official local app-server; no prompt/generation request. |
| Codex independent validation | PASS | OpenUsage and UsageBar both showed `5H 69% | 7D 85%` on 2026-09-08. |
| Automatic 60-second refresh | PASS | Installed app was observed spawning one short-lived Codex app-server child on its timer. |
| Manual Refresh | PASS | Accessibility automation invoked the menu action; title changed from `5H 58% | 7D 83%` to `5H 57% | 7D 83%`. |
| Provider switching | PASS | Accessibility automation selected OpenRouter (truthful `Usage ?` while disconnected) and returned to Codex. |
| No Dock icon | PASS | Screenshot inspection showed UsageBar in the menu bar and absent from the visible Dock; installed plist has `LSUIElement=1`. |
| Launch at Login | PASS | Accessibility automation toggled `SMAppService.mainApp`; menu mark changed absent → checked → absent. |
| Keychain round-trip/update | PASS | Isolated randomly named UsageBar Keychain items were saved, updated, read, and deleted by XCTest. |
| Install/reinstall | PASS | Installer built, signed, validated, installed and relaunched the bundle twice. |
| Uninstall | PASS | `./uninstall.sh --keep-credentials` removed only `~/Applications/UsageBar.app`; reinstall then passed. |
| Privacy manifest | PASS | Source and installed manifests passed `plutil -lint`. |
| Idle CPU / RSS | PASS | Installed process observed at 0.0% CPU and 44–47 MB RSS after refreshes. |
| Codex child processes | PASS | 68-second 100ms sampling: maximum 1 `codex app-server` child, 4 samples with a child, none remained afterward. |
| Network destination inspection | NOT TESTED | Codex CLI owns its direct provider connection; no packet/connection capture was performed. |
| Sleep/wake refresh | NOT TESTED | Not safely automated without interrupting the development session. |
| FreeBar/RamBar isolation | PASS | No project files outside UsageBar were changed; both menu-bar readouts remained visible during screenshot inspection. |
| OpenRouter live connection | NOT TESTED | No user API key was requested or used. Sanitized parsing and host-scope tests pass. |

## Current Codex record

Most recent direct official app-server validation: `5H 55% | 7D 83%` remaining. Percentages remain `100 - used_percent`; values naturally change during use. No account identifiers, credentials, headers, or payload captures are stored.
