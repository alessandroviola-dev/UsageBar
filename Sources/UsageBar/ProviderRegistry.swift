import Foundation

struct ProviderRegistry {
    let providers: [any UsageProvider]

    init(providers: [any UsageProvider]? = nil) {
        self.providers = providers ?? [CodexProvider(), CopilotProvider()]
    }

    func provider(id: String) -> (any UsageProvider)? {
        providers.first { $0.id == id }
    }
}
