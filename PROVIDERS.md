# Provider matrix

| Provider | Connection | Real quota source | Status |
|---|---|---|---|
| Codex | Existing authenticated official Codex CLI | Official local app-server `account/rateLimits/read` | FULL |
| OpenRouter | API key in macOS Keychain | Documented non-billable `https://openrouter.ai/api/v1/credits`; purchased credits and used credits provide a denominator | PARTIAL |
| OpenAI API | — | Spend without a configured cap is not a global quota percentage | UNSUPPORTED |
| Anthropic API | — | No safe implemented global quota endpoint | UNSUPPORTED |
| Gemini API / CLI | — | No safe implemented global quota endpoint | UNSUPPORTED |
| Groq | — | No safe implemented global quota endpoint | UNSUPPORTED |
| Mistral | — | No safe implemented global quota endpoint | UNSUPPORTED |
| DeepSeek | — | No safe implemented global quota endpoint | UNSUPPORTED |
| Claude Code | Existing local CLI | No safe implemented quota RPC; conversation data is not quota data | UNSUPPORTED |
| Cursor | Local application state | No safe implemented quota endpoint | UNSUPPORTED |
| GitHub Copilot | Existing CLI/OAuth where applicable | No safe implemented global quota endpoint | UNSUPPORTED |
| OpenCode | Existing local tool | No safe implemented quota endpoint | UNSUPPORTED |

`FULL` means UsageBar can calculate a mathematically valid remaining percentage from a real quota limit and the integration has been validated live. `PARTIAL` means the implementation is present and secure but live provider validation is still pending, or a global percentage cannot yet be truthfully confirmed. `UNSUPPORTED` means no secure/reliable adapter is implemented. UsageBar does not make billable generation requests to discover limits.

OpenRouter parsing, host allowlisting, Keychain storage, and error handling are implemented and tested with sanitized fixtures, but it remains `PARTIAL` until a real user-owned API key successfully validates the live credits endpoint.