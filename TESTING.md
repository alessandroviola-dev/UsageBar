# Testing — UsageBar 0.1.0

Results are recorded only when actually run.

| Check | Result | Notes |
|---|---|---|
| Debug build | PASS | `swift test` compiled the debug target. |
| Release arm64 build | PASS | `swift build -c release --arch arm64`. |
| Unit tests | PASS | 10 XCTest tests: normalization, clamping, labels, reset text, menu text, unavailable provider, isolated Keychain round-trip, and authenticated live Codex app-server retrieval. |
| Codex live retrieval | PASS | Existing authenticated Codex CLI returned primary and secondary rate-limit windows through `account/rateLimits/read`; no prompt was sent. |
| Independent Codex comparison | NOT TESTED | A second independent authoritative source was not safely available during this run. Do not treat this as release acceptance parity. |
| Automatic 60-second refresh | NOT TESTED | Implemented; requires a 60-second UI observation. |
| Manual refresh | NOT TESTED | Implemented; requires UI observation. |
| Provider switching | NOT TESTED | Implemented; requires UI observation. |
| Keychain round-trip | PASS | Isolated, randomly named Keychain item saved, read, and deleted by XCTest. |
| No Dock icon | NOT TESTED | `LSUIElement` is set. |
| Launch at Login | NOT TESTED | Implemented with `SMAppService.mainApp`. |
| Install | PASS | `./install.sh` created `~/Applications/UsageBar.app`, launched it, and its ad-hoc signature verified. |
| Reinstall | PASS | `./install.sh` was run again; it safely replaced the existing bundle and relaunched UsageBar. |
| Uninstall | NOT TESTED | |
| CPU/RSS | NOT TESTED | |
| Child processes | NOT TESTED | Codex app-server is short-lived per refresh, not persistent. |
| Network destination inspection | NOT TESTED | The Codex CLI owns its direct provider connection. |
| Privacy manifest | PASS | Source and installed `PrivacyInfo.xcprivacy` passed `plutil -lint`. |
| FreeBar/RamBar isolation | PASS | Only this repository and `~/Applications/UsageBar.app` were changed. |

## Codex live record

The safe validation command sent only `initialize` and `account/rateLimits/read` to the existing official local Codex app-server. It returned a 300-minute primary window at 21% used (79% remaining) and a 10080-minute secondary window at 14% used (86% remaining). No account identifier, token, header, or complete payload is recorded.

```text
Codex authoritative (official local app-server):
5H used: 21%
5H remaining: 79%
7D used: 14%
7D remaining: 86%

UsageBar normalization:
5H 79%
7D 86%

Independent-source result: NOT TESTED
```
