# Provider matrix

`FULL` means the implemented adapter has a real remaining-quota denominator. `PARTIAL` means a safe account connection exists but no truthful global percentage is available. `UNSUPPORTED` means UsageBar intentionally has no safe quota adapter. “This Mac” is a discovery result, not a claim about every installation.

| Provider | Auto-detection | Auth reuse | Quota source | Implementation | This Mac |
|---|---|---|---|---|---|
| Codex | `codex` on PATH/Homebrew paths | Official local app-server RPC; credentials never read | `account/rateLimits/read` | FULL | CONNECTED |
| GitHub Copilot | `gh` or `copilot` | Official `gh api`; token remains owned by GitHub CLI | GitHub `/copilot_internal/user` quota snapshots | FULL | CONNECTED |
| OpenRouter | Keychain account state | UsageBar-created API key only | Non-billable credits endpoint, purchased minus used | FULL | NEEDS CONFIG |
| Claude Code | `claude` | No adapter: current OpenUsage path depends on browser/Keychain cookie extraction, which UsageBar deliberately does not copy | None | UNSUPPORTED | NOT INSTALLED |
| Gemini CLI | `gemini` + local config | No adapter until a safe official CLI/RPC path is available; no OAuth state is copied | None | UNSUPPORTED | NOT INSTALLED |
| Cursor | Cursor app/CLI | No adapter: local activity/state is not subscription quota | None | UNSUPPORTED | NOT INSTALLED |
| OpenCode | `opencode` | No safe quota RPC discovered | None | UNSUPPORTED | NOT INSTALLED |
| OpenAI API | Manual API key | No global remaining quota without a configured cap | None | UNSUPPORTED | NEEDS CONFIG |
| Anthropic API | Manual API key | No global remaining quota without a configured cap | None | UNSUPPORTED | NEEDS CONFIG |
| Gemini API, Groq, Mistral, DeepSeek | Manual API key where applicable | No safe implemented global quota endpoint | None | UNSUPPORTED | NOT TESTED |

Expected direct hosts: OpenRouter only sends its Keychain API key to `openrouter.ai` over HTTPS. Copilot uses the official GitHub CLI, which owns its API connection. Codex uses the official Codex app-server, which owns its provider connection. No provider credential is copied into UsageBar Keychain unless entered in UsageBar.
