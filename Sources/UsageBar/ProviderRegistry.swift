import Foundation

struct ProviderRegistry {
    let providers: [any UsageProvider]

    init(providers: [any UsageProvider]? = nil) {
        if let providers { self.providers = providers; return }
        self.providers = [
            CodexProvider(),
            UnavailableProvider(id: "claude-code", displayName: "Claude Code", reason: "No safe quota source is implemented yet."),
            UnavailableProvider(id: "cursor", displayName: "Cursor", reason: "No safe quota source is implemented yet."),
            UnavailableProvider(id: "github-copilot", displayName: "GitHub Copilot", reason: "No safe quota source is implemented yet."),
            UnavailableProvider(id: "gemini-cli", displayName: "Gemini CLI", reason: "No safe quota source is implemented yet."),
            UnavailableProvider(id: "opencode", displayName: "OpenCode", reason: "No safe quota source is implemented yet."),
            OpenRouterProvider(),
            UnavailableProvider(id: "openai-api", displayName: "OpenAI API", reason: "API spend is not a quota percentage without a configured cap."),
            UnavailableProvider(id: "anthropic-api", displayName: "Anthropic API", reason: "API spend is not a quota percentage without a configured cap."),
            UnavailableProvider(id: "gemini-api", displayName: "Gemini API", reason: "No safe global quota endpoint is implemented."),
            UnavailableProvider(id: "groq", displayName: "Groq", reason: "No safe global quota endpoint is implemented."),
            UnavailableProvider(id: "mistral", displayName: "Mistral", reason: "No safe global quota endpoint is implemented."),
            UnavailableProvider(id: "deepseek", displayName: "DeepSeek", reason: "No safe global quota endpoint is implemented.")
        ]
    }

    func provider(id: String) -> (any UsageProvider)? { providers.first { $0.id == id } }
}
