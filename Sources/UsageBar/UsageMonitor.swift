import Foundation

@MainActor
final class UsageMonitor {
    private let registry = ProviderRegistry()
    private let defaults = UserDefaults.standard
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastError = false
    private(set) var activeProviderID: String
    var onChange: (() -> Void)?

    init() {
        let stored = defaults.string(forKey: "selectedProviderID")
        activeProviderID = registry.provider(id: stored ?? "") == nil ? "codex" : stored!
    }

    deinit { refreshTask?.cancel() }

    var activeProvider: any UsageProvider { registry.provider(id: activeProviderID) ?? registry.providers[0] }
    var providers: [any UsageProvider] { registry.providers }

    func start() {
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func refresh() {
        generation += 1
        let requestGeneration = generation
        let provider = activeProvider
        Task { [weak self] in
            do {
                let fetched = try await provider.fetchUsage()
                guard let self, requestGeneration == self.generation, provider.id == self.activeProviderID else { return }
                self.snapshot = fetched
                self.lastError = false
                self.onChange?()
            } catch {
                guard let self, requestGeneration == self.generation else { return }
                // Preserve the last known good value rather than putting errors in the menu bar.
                self.lastError = true
                self.onChange?()
            }
        }
    }

    func select(providerID: String) {
        guard registry.provider(id: providerID) != nil else { return }
        activeProviderID = providerID
        defaults.set(providerID, forKey: "selectedProviderID")
        snapshot = nil
        lastError = false
        onChange?()
        refresh()
    }
}
