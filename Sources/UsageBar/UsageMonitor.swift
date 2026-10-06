import Foundation

@MainActor
final class UsageMonitor {
    private let registry: ProviderRegistry
    private let defaults: UserDefaults
    private let jevCostReader: JevObservedCostReader
    private let openAICostMonitor: OpenAICostMonitor
    private var jevTask: Task<Void, Never>?
    private var jevQueued = false
    private var activeTask: Task<Void, Never>?
    private var summaryTasks: [String: Task<Void, Never>] = [:]
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private var refreshInFlight = false
    private var refreshQueued = false
    private var queuedManualRefresh = false
    private var consecutiveFailures = 0
    private var nextAutomaticRefresh = Date.distantPast

    private(set) var snapshot: UsageSnapshot?
    private(set) var snapshotsByProviderID: [String: UsageSnapshot] = [:]
    private(set) var connectionStatuses: [String: ProviderConnectionStatus] = [:]
    private(set) var lastError = false
    private(set) var jevCost: JevCostSnapshot
    private(set) var activeProviderID: String
    var onChange: (() -> Void)?

    var openAICost: OpenAICostMetrics { openAICostMonitor.metrics }

    init(registry: ProviderRegistry = ProviderRegistry(), defaults: UserDefaults = .standard, jevCostReader: JevObservedCostReader = JevObservedCostReader(), openAICostReader: OpenAICostReader = OpenAICostReader()) {
        self.registry = registry
        self.defaults = defaults
        self.jevCostReader = jevCostReader
        self.jevCost = JevCostSnapshot(inputTokens: 0, costUSD: 0, status: .unavailable)
        self.openAICostMonitor = OpenAICostMonitor(reader: openAICostReader)
        let stored = defaults.string(forKey: "selectedProviderID")
        if let stored, registry.provider(id: stored) != nil {
            activeProviderID = stored
        } else if registry.provider(id: "codex") != nil {
            activeProviderID = "codex"
        } else {
            activeProviderID = registry.providers.first?.id ?? "codex"
        }
        let discovery = LocalProviderDiscovery()
        for provider in registry.providers {
            connectionStatuses[provider.id] = discovery.state(for: provider.id).connectionStatus
        }
        openAICostMonitor.onChange = { [weak self] in self?.onChange?() }
    }

    deinit {
        refreshTask?.cancel()
        jevTask?.cancel()
        activeTask?.cancel()
        for task in summaryTasks.values { task.cancel() }
    }

    var activeProvider: any UsageProvider { registry.provider(id: activeProviderID) ?? registry.providers[0] }
    var providers: [any UsageProvider] { registry.providers }
    func provider(id: String) -> (any UsageProvider)? { registry.provider(id: id) }
    func cachedSnapshot(for providerID: String) -> UsageSnapshot? { snapshotsByProviderID[providerID] }
    func connectionStatus(for providerID: String) -> ProviderConnectionStatus {
        connectionStatuses[providerID] ?? .temporarilyUnavailable
    }

    func start() {
        guard refreshTask == nil else { return }
        refresh()
        refreshConnectionStatuses()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func refresh(manual: Bool = false) {
        // Cost sources refresh independently of quota backoff; all file I/O is off MainActor.
        refreshJev()
        openAICostMonitor.refresh(manual: manual)
        if manual { refreshProviderSummariesIfStale(force: true) }
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
        activeTask = Task { [weak self] in
            let result: Result<UsageSnapshot, Error>
            do { result = .success(try await provider.fetchUsage()) }
            catch { result = .failure(error) }
            guard !Task.isCancelled else { return }
            self?.finishActive(result, provider: provider, generation: requestGeneration)
        }
    }

    private func refreshJev() {
        guard jevTask == nil else { jevQueued = true; return }
        let reader = jevCostReader
        jevTask = Task { [weak self] in
            let value = await Task.detached(priority: .utility) { reader.read() }.value
            guard !Task.isCancelled, let self else { return }
            self.jevCost = value
            self.jevTask = nil
            self.onChange?()
            if self.jevQueued {
                self.jevQueued = false
                self.refreshJev()
            }
        }
    }

    private func finishActive(_ result: Result<UsageSnapshot, Error>, provider: any UsageProvider, generation requestGeneration: Int) {
        refreshInFlight = false
        activeTask = nil
        switch result {
        case .success(let fetched):
            snapshotsByProviderID[provider.id] = fetched
            connectionStatuses[provider.id] = .connected(accountName: provider.displayName)
            if requestGeneration == generation && provider.id == activeProviderID {
                snapshot = fetched
                lastError = false
                consecutiveFailures = 0
                nextAutomaticRefresh = .distantPast
                onChange?()
            }
        case .failure(let error):
            connectionStatuses[provider.id] = status(for: error)
            if requestGeneration == generation && provider.id == activeProviderID {
                lastError = true
                consecutiveFailures = min(consecutiveFailures + 1, 5)
                nextAutomaticRefresh = Date.now.addingTimeInterval(min(900, 60 * pow(2, Double(consecutiveFailures - 1))))
                onChange?()
            }
        }
        if refreshQueued {
            let manual = queuedManualRefresh
            refreshQueued = false
            queuedManualRefresh = false
            refresh(manual: manual)
        }
    }

    /// Providers are fetched independently, so a failed read never clears the
    /// other provider's cached quota.
    func refreshProviderSummariesIfStale(force: Bool = false) {
        for provider in providers where provider.id != activeProviderID {
            let expiry = snapshotsByProviderID[provider.id]?.fetchedAt.addingTimeInterval(300) ?? .distantPast
            guard (force || expiry < .now), summaryTasks[provider.id] == nil else { continue }
            summaryTasks[provider.id] = Task { [weak self] in
                defer { self?.summaryTasks[provider.id] = nil }
                do {
                    let fetched = try await provider.fetchUsage()
                    guard !Task.isCancelled else { return }
                    self?.snapshotsByProviderID[provider.id] = fetched
                    self?.connectionStatuses[provider.id] = .connected(accountName: provider.displayName)
                    self?.onChange?()
                } catch {
                    self?.connectionStatuses[provider.id] = self?.status(for: error) ?? .temporarilyUnavailable
                    self?.onChange?()
                }
            }
        }
    }

    func refreshConnectionStatuses() {
        Task { [weak self] in await self?.refreshConnectionStatusesAndWait() }
    }

    /// Used by the Providers window so it redraws only after each displayed
    /// state has been verified by an actual provider quota read.
    func refreshConnectionStatusesAndWait() async {
        for provider in providers {
            connectionStatuses[provider.id] = await provider.connectionStatus()
            onChange?()
        }
    }

    private func status(for error: Error) -> ProviderConnectionStatus {
        (error as? ProviderError)?.connectionStatus ?? .temporarilyUnavailable
    }

    func select(providerID: String) {
        guard registry.provider(id: providerID) != nil else { return }
        activeProviderID = providerID
        defaults.set(providerID, forKey: "selectedProviderID")
        generation += 1
        snapshot = snapshotsByProviderID[providerID]
        lastError = false
        onChange?()
        refresh(manual: true)
    }
}
