# UsageBar

A tiny native macOS menu-bar utility for monitoring OpenAI Codex usage limits, with optional GitHub Copilot support and a read-only Jev observed cost metric.

UsageBar is designed primarily for OpenAI Codex. It displays the real remaining percentage for the authenticated Codex account's 5-hour and 7-day windows. Reset countdowns appear in the Codex dropdown only; the menu-bar title remains compact and never contains a countdown.

GitHub Copilot is an optional secondary provider. Codex is the default provider and the selected provider persists between launches.

## Jev observed cost

UsageBar reads local Jev trace files (`~/.pi/agent/forgejev-traces/*.jsonl`) and legacy ForgeApis telemetry/canary data in read-only mode to show **Jev observed cost**. It uses a recorded cost only for trace records explicitly marked with provider `jev`; generic Pi/OpenAI telemetry is deliberately excluded because its list price is not Jev spend. Otherwise it falls back to the versioned Jev input-token observation. An optional local Jev-dashboard anchor (`~/.pi/agent/forgejev/usage-baseline.json`) starts the displayed total from a confirmed dashboard value and adds input tokens only from new requests after its timestamp, deduplicated by canonical `requestId` across both ledgers and the shared usage trace. The existing anchor is never rewritten: its cost remains authoritative, with future input charged at $42 per billion input tokens, not a rate inferred from the anchor. Output tokens are free and do not enter the displayed input-token total. It never accesses the Jev API key, makes additional network calls, or invokes Jev, so this is not yet an API-authoritative account-spend value.

## OpenAI cost metrics (not quota providers)

- **OpenAI billed cost (30d)** uses only the OpenAI Organization Costs API, summing `data[].results[].amount.value` in USD across all pages for an explicit rolling 30-day window. A valid zero remains zero. Missing Admin key, failed API access, or an uninterpretable response shows **unavailable**, never a local fallback.
- **OpenAI observed local** sums valid `assistant_message.usage.costTotal` entries from `~/.pi/agent/forgeapis/telemetry.jsonl`, opened read-only. Malformed records are ignored. This is the observed total of the available file, not a 30-day total or official organization billing.

Official billing polls about every 300 seconds; local costs refresh about every 60 seconds. **Refresh** immediately refreshes both OpenAI metrics, Jev, and provider data without restarting the app. In-flight cost reads are serialized per source and manual refreshes are coalesced.

## Providers

The Providers window contains only:

- Codex
- GitHub Copilot

It reports only these states: **Connected**, **Not installed**, **Needs login**, and **Temporarily unavailable**. A provider becomes Connected only after UsageBar completes a real quota read. Switching provider changes the menu-bar provider name immediately. Each provider has its own cached snapshot, so one provider's failure does not erase the other's last successful read.

## Authentication and privacy

Quota authentication remains owned by the official tools. Optional OpenAI billing authentication is separate.

- Codex usage is read exclusively through the official `codex app-server` JSON-RPC interface.
- GitHub Copilot usage is requested through the user's existing authenticated GitHub CLI; UsageBar does not read or save its token.
- UsageBar does not read Codex prompts, conversations, sessions, or authentication files.
- UsageBar does not make a model-generation request to obtain quota data.
- Codex authentication remains managed by official Codex; Copilot authentication remains managed by GitHub CLI.
- The optional OpenAI Admin API key for billed costs is retained in the macOS Keychain, service `UsageBar.OpenAI.AdminAPIKey`, account `NSUserName()`. UsageBar reads it only for the official Costs request and never displays or logs it, or saves it in preferences, files, source, or persistent environment variables. There is no API-key entry UI.
- Local observed telemetry and Jev data are read-only filesystem inputs, never modified by UsageBar.
- There is no UsageBar server, outbound telemetry, analytics, tracking, or remote sync.

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
