import Foundation

@MainActor
final class UsageMonitor {
    private let registry: ProviderRegistry
    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private var refreshInFlight = false
    private var refreshQueued = false
    private var queuedManualRefresh = false
    private var consecutiveFailures = 0
    private var nextAutomaticRefresh = Date.distantPast
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastError = false
    private(set) var activeProviderID: String
    var onChange: (() -> Void)?

    init(registry: ProviderRegistry = ProviderRegistry(), defaults: UserDefaults = .standard) {
        self.registry = registry
        self.defaults = defaults
        let stored = defaults.string(forKey: "selectedProviderID")
        activeProviderID = registry.provider(id: stored ?? "") == nil ? "codex" : stored!
    }

    deinit { refreshTask?.cancel() }

    var activeProvider: any UsageProvider { registry.provider(id: activeProviderID) ?? registry.providers[0] }
    var providers: [any UsageProvider] { registry.providers }
    func provider(id: String) -> (any UsageProvider)? { registry.provider(id: id) }

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

    /// Coalesces clicks/timer events. Manual refresh bypasses local error backoff,
    /// but providers may still return a server-directed rate-limit error.
    func refresh(manual: Bool = false) {
        if refreshInFlight {
            refreshQueued = true
            queuedManualRefresh = queuedManualRefresh || manual
            return
        }
        guard manual || Date.now >= nextAutomaticRefresh else { return }
        refreshInFlight = true
        generation += 1
        let requestGeneration = generation
        let provider = activeProvider
        Task { [weak self] in
            let result: Result<UsageSnapshot, Error>
            do { result = .success(try await provider.fetchUsage()) }
            catch { result = .failure(error) }
            guard let self else { return }
            self.finish(result, provider: provider, generation: requestGeneration)
        }
    }

    private func finish(_ result: Result<UsageSnapshot, Error>, provider: any UsageProvider, generation requestGeneration: Int) {
        refreshInFlight = false
        switch result {
        case .success(let fetched):
            if requestGeneration == generation && provider.id == activeProviderID {
                snapshot = fetched
                lastError = false
                consecutiveFailures = 0
                nextAutomaticRefresh = .distantPast
                onChange?()
            }
        case .failure(let error):
            if requestGeneration == generation {
                lastError = true
                consecutiveFailures = min(consecutiveFailures + 1, 5)
                let delay = min(900.0, 60.0 * pow(2.0, Double(consecutiveFailures - 1)))
                nextAutomaticRefresh = retryDate(error: error) ?? Date.now.addingTimeInterval(delay)
                onChange?() // Preserve an existing successful snapshot.
            }
        }
        if refreshQueued {
            let manual = queuedManualRefresh
            refreshQueued = false
            queuedManualRefresh = false
            refresh(manual: manual)
        }
    }

    private func retryDate(error: Error) -> Date? {
        guard case ProviderError.rateLimited(let retryAfter) = error else { return nil }
        return retryAfter
    }

    func select(providerID: String) {
        guard registry.provider(id: providerID) != nil else { return }
        activeProviderID = providerID
        defaults.set(providerID, forKey: "selectedProviderID")
        generation += 1 // Ensures any older provider result is discarded.
        snapshot = nil
        lastError = false
        onChange?()
        refresh()
    }
}
