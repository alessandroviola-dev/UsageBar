# Provider matrix

| Provider | Connection | Real quota source | Status |
|---|---|---|---|
| Codex | Existing authenticated official Codex CLI | Official local app-server `account/rateLimits/read` | FULL |
| Claude Code | Existing local CLI | No safe, implemented percentage quota source | UNSUPPORTED |
| Cursor | Local application state | No safe, implemented percentage quota source | UNSUPPORTED |
| GitHub Copilot | Existing CLI/OAuth where applicable | No safe, implemented percentage quota source | UNSUPPORTED |
| Gemini CLI | Existing local CLI | No safe, implemented percentage quota source | UNSUPPORTED |
| OpenRouter | API key | Credit balance alone has no known allowance denominator | PARTIAL |
| OpenAI API | API key | Spend without a configured cap is not a quota percentage | PARTIAL |
| Anthropic API | API key | Spend without a configured cap is not a quota percentage | PARTIAL |

`FULL` means UsageBar can calculate a mathematically valid remaining percentage from a real quota limit. `PARTIAL` does not display an invented percentage. `UNSUPPORTED` has no implemented secure/reliable source.
