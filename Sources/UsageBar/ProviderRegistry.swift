import Foundation

struct ProviderRegistry {
    let providers: [any UsageProvider]

    init() {
        providers = [
            CodexProvider(),
            UnavailableProvider(id: "claude-code", displayName: "Claude Code", reason: "No safe quota source is implemented yet."),
            UnavailableProvider(id: "cursor", displayName: "Cursor", reason: "No safe quota source is implemented yet."),
            UnavailableProvider(id: "github-copilot", displayName: "GitHub Copilot", reason: "No safe quota source is implemented yet."),
            UnavailableProvider(id: "gemini-cli", displayName: "Gemini CLI", reason: "No safe quota source is implemented yet."),
            UnavailableProvider(id: "openrouter", displayName: "OpenRouter", reason: "A known allowance is required before a percentage can be shown."),
            UnavailableProvider(id: "openai-api", displayName: "OpenAI API", reason: "API spend is not a quota percentage without a configured cap."),
            UnavailableProvider(id: "anthropic-api", displayName: "Anthropic API", reason: "API spend is not a quota percentage without a configured cap.")
        ]
    }

    func provider(id: String) -> (any UsageProvider)? { providers.first { $0.id == id } }
}
