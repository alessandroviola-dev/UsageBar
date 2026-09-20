# UsageBar

A tiny native macOS menu-bar utility for monitoring OpenAI Codex usage limits, with optional GitHub Copilot support.

UsageBar is designed primarily for OpenAI Codex. It displays the real remaining percentage for the authenticated Codex account's 5-hour and 7-day windows. Reset countdowns appear in the Codex dropdown only; the menu-bar title remains compact and never contains a countdown.

GitHub Copilot is an optional secondary provider. Codex is the default provider and the selected provider persists between launches.

## Providers

The Providers window contains only:

- Codex
- GitHub Copilot

It reports only these states: **Connected**, **Not installed**, **Needs login**, and **Temporarily unavailable**. A provider becomes Connected only after UsageBar completes a real quota read. Switching provider changes the menu-bar provider name immediately. Each provider has its own cached snapshot, so one provider's failure does not erase the other's last successful read.

## Authentication and privacy

No API key is entered, copied, or stored by UsageBar.

- Codex usage is read exclusively through the official `codex app-server` JSON-RPC interface.
- GitHub Copilot usage is requested through the user's existing authenticated GitHub CLI; UsageBar does not read or save its token.
- UsageBar does not read Codex prompts, conversations, sessions, or authentication files.
- UsageBar does not make a model-generation request to obtain quota data.
- Authentication remains managed by the official Codex and GitHub tools.
- There is no UsageBar server, telemetry, analytics, tracking, remote sync, or credential storage.

See [PROVIDERS.md](PROVIDERS.md) for implementation and live-test status.

## Installation

Download the latest `UsageBar-vX.Y.Z-macOS.zip` from [GitHub Releases](https://github.com/alessandroviola-dev/UsageBar/releases), extract `UsageBar.app`, drag it to `/Applications`, and open it.

Current builds are ad-hoc signed unless a release states otherwise. If Gatekeeper blocks the first launch, control-click the app, choose **Open**, then confirm. Do not disable Gatekeeper globally.

## Build from source

Requires macOS 13+, Apple Silicon, Swift 6+, and a macOS SDK:

```bash
swift test
swift build --arch arm64 -Xswiftc -warnings-as-errors
./scripts/build-release.sh
./install.sh
```

`install.sh` installs only `~/Applications/UsageBar.app`. The app has no Dock icon and supports Launch at Login.

## Uninstall

```bash
./uninstall.sh
```

The uninstaller removes only UsageBar and its selected-provider preference. It never alters Codex or GitHub authentication.

## Limitations

Provider quota interfaces may change. The GitHub Copilot quota path is a compatibility endpoint invoked by the official GitHub CLI because no documented stable public quota endpoint was available for this lightweight native architecture at the time of implementation. Its live status is recorded separately in [TESTING.md](TESTING.md).

## License

MIT.
