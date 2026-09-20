# Testing — UsageBar 0.2.0

Results below describe this cleanup run. Fixture tests and live-account tests are recorded separately.

| Check | Result | Evidence |
|---|---|---|
| XCTest fixture suite | PASS | `swift test`: 18 tests executed, 16 passed, 0 failed, 2 explicitly skipped live tests when their opt-in environment variable was absent. |
| Registry and default provider | PASS | Fixture coverage verifies exactly `codex` and `github-copilot`, with Codex selected by default. |
| Codex CLI/login/error states | PASS | Fixtures cover absent CLI, absent login, revoked token, backend error, malformed response, and app-server timeout. |
| Codex RPC handshake | PASS | Fixture process asserts `initialize` response before `initialized`, followed by `account/rateLimits/read`. |
| Codex schema parsing | PASS | Fixtures cover current camel-case and compatible snake-case rate-limit fields; missing percentages are not manufactured. |
| Copilot CLI/auth/parser states | PASS | Fixtures cover absent GitHub CLI, unauthenticated GitHub CLI, valid quota, and malformed JSON. |
| Provider cache/switching/persistence | PASS | Fixture coverage verifies isolated snapshots, switching, and persisted selected provider. |
| Countdown/menu-bar formatting | PASS | Fixtures verify the Codex dropdown countdown and no countdown in the menu-bar title. |
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
