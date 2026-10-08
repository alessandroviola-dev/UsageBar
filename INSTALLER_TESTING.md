# Installer verification (local, 2026-10-08)

Canonical destination: `/Applications/UsageBar.app`. No per-user installation fallback or creation of `~/Applications`. Existing verified canonical and legacy bundles are backed up until canonical launch, signature and privacy-manifest verification succeed; rollback restores their original paths. Uninstall preflights both locations. Bundle ID, executable presence and strict signature checks are required. Symlinked bundles or Applications directories are refused. Generic pkill was removed: only the exact executable path is selected, rechecked before TERM.

## Results

- `bash -n install.sh uninstall.sh scripts/common.sh scripts/build-release.sh`: PASS.
- `python3 scripts/test-installer.py`: 15 scenarios PASS (fresh, canonical-only, legacy-only, coexistence, legacy/canonical wrong IDs, bad signature, bundle/parent symlinks, rollback on launch failure or missing process, uninstall, absent uninstall, unregister failure retention, exact executable process selection).
- Initial `swift test`: 37 XCTest tests, zero failures, 2 live-provider tests skipped (not enabled). On the final rerun, `testCodexAppServerHandshakeSequence` failed with `temporarilyUnavailable` after its fixture timeout; an immediate isolated rerun passed (0.231 seconds). This intermittent timeout remains open and is unrelated to installer changes.
- `swift build -c release --arch arm64 -Xswiftc -warnings-as-errors`: PASS.
- `git diff --check`: PASS.
- Read-only installed bundle ID and strict signature verification: PASS.
- Installed process retained PID 34295; executable modification time remained 2026-10-06. No real app install/replacement/termination, GitHub Actions, push or release creation.

## Test isolation incident

The initial sandbox harness did not mock `defaults`. Its uninstall scenario executed `defaults delete com.alessandroviola.usagebar` against the real user's preference domain, despite the temporary HOME. The domain was subsequently observed empty. The prior selected-provider preference is unknown and was not reconstructed. The installed bundle/process and provider credentials were not changed. The harness now mocks `defaults`; all 15 scenarios were rerun with this correction. This side effect was disclosed to the user.

## Follow-up corrections (2026-10-08)

- Uninstall preserves preferences by default. Only `--delete-preferences` requests domain deletion. No preference recovery has been attempted; installer bundle backups do not contain preferences.
- Harness fails closed on unapproved defaults syntax before execution, checks Bash command resolution, and traps absolute defaults calls before execution with exit 97 and a violation marker. The marker is checked independently of script success. macOS sandbox-exec additionally denies execution of `/usr/bin/defaults`, including descendants; its availability and denial are probed before running scripts. Temporary HOME alone is not considered isolation.
- Added negative isolation probes (including an absolute invocation followed by `|| true`), assertions that normal uninstall never calls defaults, and an explicit deletion scenario using only the mock. Existing unregister-failure scenario verifies retained bundles and error diagnostics. Unit tests inject unregister success/failure without calling SMAppService.
- Codex fixture now validates each request before acknowledging it, uses `IFS= read -r`, and waits for stdin closure after emitting the response. This removes premature fixture exit as a race source. The original intermittent failure's root cause is not conclusively proven; the 2-second watchdog remains, with no retries or sleeps added.
- Validation: original 15 installer scenarios plus explicit deletion and isolation checks PASS; focused Codex handshake PASS; offline XCTest suite: 39 tests, 2 live tests skipped, zero failures. Bash syntax and git diff whitespace checks PASS.
- No installed bundle, real preferences, existing backup, installer destination, push, release, or Actions run was modified/executed.

## Limits / open issues

- Sandbox tests use disposable script copies, redirected paths and mocked OS tools, including Bash `kill` in the process test. Real signing/LaunchServices/SMAppService migration behavior is not established by these tests.
- Updated source propagates unregister errors as a nonzero process exit (generic stderr, no framework error details). Existing installed binaries have NOT been replaced and may still swallow errors; manual login-item verification remains necessary.
- Check Launch at Login after legacy migration. Real permission/disk failures and recovery retention remain manual checks. Failed rollback retains staging rather than deleting backups.
- `scripts/build-release.sh` was inspected and syntax-checked, not executed; it packages in `dist` without installing apps.
