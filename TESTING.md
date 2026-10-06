# Testing — UsageBar 0.3.2

## Maintenance validation (build 5)

New offline fixtures in `OpenAICostTests.swift` cover official nested results, multiple buckets/results, pagination and exact 30-day query bounds, authoritative zero, positive API/local separation, API/transport failures, absent key, malformed telemetry/JSON, unsupported currency, empty results, invalid/repeated cursors, per-source coalescing, and manual refresh through UsageMonitor. Fixtures inject transport, endpoint, key provider, file URL and clock; they make no real HTTP calls and contain no real credentials.

Jev fixtures now assert the exact anchored result: 123915 + 100 input tokens = 124015, 163 + 1 requests = 164, and cost 0.0046 + `JevPricing.cost(inputTokens: 100)`. The 20 output tokens do not count. Cross-source requestId deduplication and an unchanged baseline file are verified; legacy coverage is retained.

| Current maintenance check | Result | Evidence |
|---|---|---|
| Diff whitespace | PASS | `git diff --check` |
| Offline XCTest suite | PASS | 37 tests executed, 35 passed, 2 opt-in live quota tests skipped, 0 failures; includes 14 OpenAI and 5 Jev fixtures. |
| Debug arm64 warnings-as-errors | PASS | `swift build --arch arm64 -Xswiftc -warnings-as-errors` |
| Release arm64 warnings-as-errors | PASS | `swift build -c release --arch arm64 -Xswiftc -warnings-as-errors` |
| Local release archive | PASS | `./scripts/build-release.sh`: 0.3.2/build 5 app and ZIP, strict signing and extracted bundle validation; whitelist/local-user-path checks passed. |
| Installation | PASS | `./install.sh` replaced only `~/Applications/UsageBar.app`; installed defaults report 0.3.2 and 5; strict codesign passes and process is active. |
| Read-only independent cost checks | PASS | Existing telemetry, Jev baseline and both ledgers read successfully; only aggregate cost/token/request metrics inspected, no model requests generated. |
| Installed Jev row/auto-refresh | BLOCKED | Actual menu cannot be inspected without macOS Accessibility permission; independent filesystem calculation is not treated as a UI pass. |
| Installed OpenAI local row comparison | BLOCKED | Independent file sum succeeded, but cannot compare it to the installed UI. |
| Installed official billed row | BLOCKED | Keychain item presence checked without revealing its data; app performs its normal read, but status/value cannot be inspected in the UI. |
| Installed manual Refresh | BLOCKED | System Events rejects menu access with error -25211 (assistive access denied); no click or visual confirmation possible. Fixture refresh coverage passes but is not substituted for installed smoke. |
| Local commit | NOT CREATED | Required installed UI/Refresh gate remains blocked. Changes intentionally left uncommitted for continuation once Accessibility is enabled. |

No hosted CI, push, tag, or release was used. No ForgeJev/ForgeApis data was modified. To finish: enable Accessibility for the controlling terminal/harness, inspect the installed cost rows, compare local totals, click Refresh and verify both OpenAI metrics and Jev/provider updates, then repeat the final audit before one local commit.

## Previous quota validation (0.3.1)

The historical results below concern the previous cleanup run, not the new installed cost smoke. Fixture tests and live-account tests are recorded separately.

| Check | Result | Evidence |
|---|---|---|
| XCTest fixture suite | PASS | `swift test`: 20 tests executed, 18 passed, 0 failed, 2 explicitly skipped live tests when their opt-in environment variable was absent. |
| Registry and default provider | PASS | Fixture coverage verifies exactly `codex` and `github-copilot`, with Codex selected by default. |
| Codex CLI/login/error states | PASS | Fixtures cover absent CLI, absent login, revoked token, backend error, malformed response, and app-server timeout. |
| Codex RPC handshake | PASS | Fixture process asserts `initialize` response before `initialized`, followed by `account/rateLimits/read`. |
| Codex schema parsing | PASS | Fixtures cover current camel-case and compatible snake-case rate-limit fields; missing percentages are not manufactured. |
| Copilot CLI/auth/parser states | PASS | Fixtures cover absent GitHub CLI, unauthenticated GitHub CLI, valid quota, and malformed JSON. |
| Provider cache/switching/persistence | PASS | Fixture coverage verifies isolated snapshots, switching, and persisted selected provider. |
| Countdown/menu-bar formatting | PASS | Fixtures verify the Codex dropdown countdown and no countdown in the menu-bar title. |
| Jev observed cost | PASS | Fixture coverage verifies ForgeApis telemetry/canary parsing, deduplication, zero/unavailable/partial states, pricing, and sub-cent formatting. |
| Live Codex quota read | PASS | `USAGEBAR_LIVE_PROVIDER_TESTS=1 swift test --filter ProviderTests/testLiveCodexQuotaWhenExplicitlyEnabled` passed against the configured local Codex account. |
| Live Copilot quota read | PASS | `USAGEBAR_LIVE_PROVIDER_TESTS=1 swift test --filter ProviderTests/testLiveCopilotQuotaWhenExplicitlyEnabled` passed through the configured authenticated GitHub CLI account. |
| Debug arm64 warnings-as-errors build | PASS | `swift build --arch arm64 -Xswiftc -warnings-as-errors` completed successfully. |
| Release arm64 warnings-as-errors build | PASS | `swift build -c release --arch arm64 -Xswiftc -warnings-as-errors` completed successfully. |
| Release archive | PASS | `./scripts/build-release.sh` completed without warnings after the release builder was changed to enforce warnings-as-errors; signing, archive extraction, and bundle validation passed. |
| Install/reinstall/launch | PASS | `./install.sh` was run twice, then again after the final release build. The installed arm64 bundle launched successfully and passed strict code-signature and plist validation. |
| Idle process / child cleanup | PASS | After launch and a five-second idle check: 0.0% CPU, about 43 MB RSS, and no persistent `codex app-server` child. |
| Privacy manifest | PASS | Source and installed `PrivacyInfo.xcprivacy` passed `plutil -lint`. |
| No Dock icon configuration | PASS | Installed bundle has `LSUIElement=true`. |
| Launch at Login toggle | NOT TESTED | The existing ServiceManagement implementation was not toggled during this run. |
| Manual Refresh in visible UI | NOT TESTED | Refresh behavior is covered by the monitor/provider tests, but this run did not automate the visible menu item. |
| Visible UI switching in installed app | NOT TESTED | Switching and immediate provider-name updates are fixture-tested; this run did not use accessibility automation on the installed menu. |
| Network capture | NOT TESTED | Provider networking is performed by the official Codex and GitHub tools; no packet capture was performed. |
| FreeBar/RamBar isolation | PASS | Work was confined to this repository. |

The opt-in live tests deliberately do not print account identifiers, quota values, credentials, prompts, conversations, or sessions.
