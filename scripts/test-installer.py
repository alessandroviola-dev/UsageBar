#!/usr/bin/env python3
"""Sandbox integration tests: redirect paths in disposable script copies and mock OS tools.
Signing, launch and login-item behavior are simulated, not macOS end-to-end tests.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def validate_defaults_calls(text):
    # Fail closed before executing disposable scripts; never rewrite absolute calls.
    for line in text.splitlines():
        if 'defaults' in line and not line.lstrip().startswith('#'):
            if line.strip() != 'defaults delete "$BUNDLE_ID" 2>/dev/null || true':
                raise AssertionError(f"Unapproved defaults invocation: {line}")


def test_defaults_isolation():
    for command in ('/usr/bin/defaults read x', 'command defaults read x',
                    '"/usr/bin/defaults" read x', '$(which defaults) read x'):
        try:
            validate_defaults_calls(command)
        except AssertionError:
            continue
        raise AssertionError(command)
    print('PASS defaults-isolation')

ROOT = Path(__file__).resolve().parents[1]
NAME = ROOT.name
BUNDLE_ID = "com.alessandroviola." + NAME.lower()


def run_case(case):
    with tempfile.TemporaryDirectory(prefix=f"{NAME}-installer-test-") as tmp:
        base = Path(tmp)
        repo = base / "repo"
        repo.mkdir()
        shutil.copytree(ROOT / "Resources", repo / "Resources")
        (repo / "scripts").mkdir()
        apps = base / "Applications"
        apps.mkdir()
        home = base / "home"
        home.mkdir()
        mocks = base / "mocks"
        mocks.mkdir()
        binary = base / "bin"
        binary.mkdir()
        exe = binary / NAME
        exe.write_text('#!/bin/bash\n[[ ${TEST_UNREGISTER_FAIL:-0} != 1 ]]\n')
        exe.chmod(0o755)
        env = dict(os.environ, HOME=str(home), PATH=f"{mocks}:/usr/bin:/bin:/usr/sbin:/sbin",
                   TEST_BIN=str(binary), TEST_ID=BUNDLE_ID)
        commands = {
            "uname": 'if [[ $1 == -m ]]; then echo arm64; else echo Darwin; fi',
            "swift": 'if [[ " $* " == *" --show-bin-path "* ]]; then echo "$TEST_BIN"; fi',
            "xcode-select": 'exit 0', "xcrun": 'exit 0', "plutil": 'exit 0',
            "lipo": 'echo arm64', "defaults": 'printf "%s\\n" "$*" >> "$TEST_DEFAULTS_LOG"', "sleep": 'exit 0',
            "codesign": 'if [[ $* == *--verify* && -f "${@: -1}/bad-signature" ]]; then exit 1; fi',
            "PlistBuddy": 'if [[ -f "${@: -1}.id" ]]; then /bin/cat "${@: -1}.id"; else echo "$TEST_ID"; fi',
            "open": '[[ ${TEST_OPEN_FAIL:-0} != 1 ]]',
            "pgrep": 'if [[ ${TEST_PROCESSES:-0} == 1 ]]; then printf "100001\\n100002\\n100003\\n"; fi',
            "ps": 'case "$2" in 100001) echo "$TEST_CANONICAL";; 100002) echo "$TEST_LEGACY --arg";; 100003) echo "$TEST_OTHER";; esac',
        }
        for command, body in commands.items():
            path = mocks / command
            path.write_text("#!/bin/bash\n" + body + "\n")
            path.chmod(0o755)
        env['TEST_DEFAULTS_LOG'] = str(base / 'defaults.log')
        guard = base / 'guard.sh'
        guard.write_text('''set -T
trap 'case "$BASH_COMMAND" in
  *defaults*)
    if [[ "$BASH_COMMAND" == *"/defaults"* || $(command -v defaults) != "$TEST_MOCK_DEFAULTS" ]]; then
      printf "%s\\n" "Blocked real defaults" > "$TEST_DEFAULTS_VIOLATION"
      exit 97
    fi ;;
esac' DEBUG
''')
        env.update(BASH_ENV=str(guard), TEST_MOCK_DEFAULTS=str(mocks / 'defaults'),
                   TEST_DEFAULTS_VIOLATION=str(base / 'defaults.violation'))
        profile = base / 'sandbox.sb'
        profile.write_text('(version 1)(allow default)(deny process-exec (literal "/usr/bin/defaults"))')
        assert Path('/usr/bin/sandbox-exec').exists(), 'Required OS isolation unavailable'
        # Probe the OS boundary before any installer script is allowed to run.
        # The harmless read must be denied before defaults can even start.
        probe = subprocess.run(['/usr/bin/sandbox-exec', '-f', str(profile),
                                '/usr/bin/defaults', 'read', BUNDLE_ID],
                               capture_output=True, text=True)
        assert probe.returncode != 0 and 'Operation not permitted' in probe.stderr, probe.stderr
        guard_env = dict(env, TEST_DEFAULTS_VIOLATION=str(base / 'guard-probe.violation'))
        for command in ('/usr/bin/defaults read x', 'command /usr/bin/defaults read x'):
            blocked = subprocess.run(['/usr/bin/sandbox-exec', '-f', str(profile),
                                      '/bin/bash', '-c', command + ' || true'],
                                     env=guard_env, capture_output=True, text=True)
            assert blocked.returncode == 97, blocked.stderr
            assert (base / 'guard-probe.violation').exists()
        for relative in ("install.sh", "uninstall.sh", "scripts/common.sh"):
            validate_defaults_calls((ROOT / relative).read_text())
            text = (ROOT / relative).read_text().replace('"/Applications', f'"{apps}').replace(' /Applications ', f' {apps} ')
            for absolute, replacement in {
                "/usr/libexec/PlistBuddy": "PlistBuddy", "/usr/bin/open": "open",
                "/usr/bin/pgrep": "pgrep", "/bin/ps": "ps", "/usr/bin/lipo": "lipo",
            }.items():
                text = text.replace(absolute, replacement)
            # Only post-launch observation is simulated; process filtering is tested separately.
            text = text.replace('[[ -n $(installed_pids) ]]', '[[ ${TEST_NO_PROCESS:-0} != 1 ]]')
            (repo / relative).write_text(text)
        canonical = apps / f"{NAME}.app"
        legacy = home / "Applications" / f"{NAME}.app"

        def bundle(path, marker):
            (path / "Contents/MacOS").mkdir(parents=True)
            shutil.copy2(exe, path / f"Contents/MacOS/{NAME}")
            (path / "Contents/Info.plist").write_text("fixture")
            (path / "marker").write_text(marker)

        if case not in ("fresh", "absent-uninstall", "process-paths"):
            if case != "legacy-only":
                bundle(canonical, "canonical")
            if case != "canonical-only":
                bundle(legacy, "legacy")
        if case == "wrong-id":
            (legacy / "Contents/Info.plist.id").write_text("unrelated.app")
        if case == "canonical-wrong-id":
            (canonical / "Contents/Info.plist.id").write_text("unrelated.app")
        if case == "bad-signature":
            (legacy / "bad-signature").touch()
        if case == "symlink":
            shutil.rmtree(legacy)
            legacy.symlink_to(canonical)
        if case == "parent-symlink":
            shutil.rmtree(legacy.parent)
            legacy.parent.symlink_to(apps)
        if case == "rollback-open":
            env["TEST_OPEN_FAIL"] = "1"
        if case == "rollback-no-process":
            env["TEST_NO_PROCESS"] = "1"
        if case == "unregister-failure":
            env["TEST_UNREGISTER_FAIL"] = "1"
        if case == "process-paths":
            env.update(TEST_PROCESSES="1", TEST_CANONICAL=f"{canonical}/Contents/MacOS/{NAME}",
                       TEST_LEGACY=f"{legacy}/Contents/MacOS/{NAME}", TEST_OTHER=f"/unrelated/{NAME}")
            script = f'''source "{repo}/scripts/common.sh"
[[ $(installed_pids) == 100001 ]]
[[ $(installed_pids "$LEGACY_APP") == 100002 ]]
# Mock the shell builtin too: this test must never signal any real process.
kill() {{ if [[ $1 == -TERM ]]; then printf '%s\\n' "$2" >> "{base}/signals"; else return 1; fi; }}
stop_installed_app
stop_installed_app "$LEGACY_APP"
'''
            result = subprocess.run(["/bin/bash", "-c", script], env=env, capture_output=True, text=True)
            assert result.returncode == 0, result.stderr
            assert (base / "signals").read_text().splitlines() == ["100001", "100002"]
            print(f"PASS {case}")
            return
        script = "uninstall.sh" if case in ("uninstall", "absent-uninstall", "unregister-failure", "delete-preferences") else "install.sh"
        args = ['--delete-preferences'] if case == 'delete-preferences' else []
        result = subprocess.run(["/usr/bin/sandbox-exec", '-f', str(profile), "/bin/bash", str(repo / script), *args], env=env, capture_output=True, text=True)
        assert not (base / 'defaults.violation').exists(), 'Attempted real defaults invocation'
        log = base / 'defaults.log'
        if case == 'delete-preferences':
            assert log.read_text().splitlines() == [f'delete {BUNDLE_ID}']
        else:
            assert not log.exists(), 'Preferences must be preserved'
        if case == 'unregister-failure':
            assert 'Launch at Login could not be removed' in result.stderr
        failures = ("wrong-id", "canonical-wrong-id", "bad-signature", "symlink", "parent-symlink",
                    "rollback-open", "rollback-no-process", "unregister-failure")
        assert (result.returncode != 0) == (case in failures), (case, result.stdout, result.stderr)
        if case in failures:
            assert (canonical / "marker").read_text() == "canonical", case
            assert (legacy / "marker").read_text() == ("canonical" if case in ("symlink", "parent-symlink") else "legacy"), case
        elif case in ("uninstall", "absent-uninstall", "delete-preferences"):
            assert not canonical.exists() and not legacy.exists()
        else:
            assert (canonical / f"Contents/MacOS/{NAME}").exists()
            assert not legacy.exists()
            if case == "fresh":
                assert not (home / "Applications").exists()
        assert not list(apps.glob(f".{NAME}-install.*")), case
        print(f"PASS {case}")


test_defaults_isolation()
for scenario in ("fresh", "canonical-only", "legacy-only", "migration", "wrong-id", "canonical-wrong-id",
                 "bad-signature", "symlink", "parent-symlink", "rollback-open", "rollback-no-process",
                 "uninstall", "absent-uninstall", "unregister-failure", "process-paths", "delete-preferences"):
    run_case(scenario)
