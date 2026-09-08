import XCTest
@testable import UsageBar

final class ProviderHardeningTests: XCTestCase {
    func testOpenRouterSanitizedFixtureProducesTruthfulPercentage() throws {
        let fixture = Data(#"{"data":{"total_credits":100.0,"total_usage":24.0}}"#.utf8)
        let window = try OpenRouterProvider.parseCreditsResponse(fixture)
        XCTAssertEqual(window.label, "Credits")
        XCTAssertEqual(window.remainingPercent, 76)
    }

    func testOpenRouterFixtureClampsOverspendAndRejectsUnknownAllowance() throws {
        let overdrawn = Data(#"{"data":{"total_credits":10,"total_usage":12}}"#.utf8)
        XCTAssertEqual(try OpenRouterProvider.parseCreditsResponse(overdrawn).remainingPercent, 0)
        let invalid = Data(#"{"data":{"total_credits":0,"total_usage":0}}"#.utf8)
        XCTAssertThrowsError(try OpenRouterProvider.parseCreditsResponse(invalid))
    }

    func testProviderEndpointScopesCredentialDestination() throws {
        XCTAssertNoThrow(try ProviderEndpoint(url: URL(string: "https://openrouter.ai/api/v1/credits")!, allowedHosts: ["openrouter.ai"]))
        XCTAssertThrowsError(try ProviderEndpoint(url: URL(string: "http://openrouter.ai/api/v1/credits")!, allowedHosts: ["openrouter.ai"]))
        XCTAssertThrowsError(try ProviderEndpoint(url: URL(string: "https://example.invalid/")!, allowedHosts: ["openrouter.ai"]))
    }

    func testRetryAfterParsing() {
        let before = Date.now
        XCTAssertNotNil(RetryAfter.date(from: "60"))
        XCTAssertGreaterThanOrEqual(RetryAfter.date(from: "60") ?? .distantPast, before)
        XCTAssertNil(RetryAfter.date(from: "not-a-date"))
    }

    func testKeychainUpdateReplacesOnlyUsageBarItem() throws {
        let account = "test-update-\(UUID().uuidString)"
        defer { try? KeychainStore.delete(account: account) }
        try KeychainStore.save(Data("first".utf8), account: account)
        try KeychainStore.save(Data("second".utf8), account: account)
        XCTAssertEqual(try KeychainStore.load(account: account), Data("second".utf8))
    }

    @MainActor
    func testProviderSelectionPersistsOnlyIdentifier() async throws {
        let suite = "UsageBarTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw XCTSkip("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = FakeState(results: [.success(FakeProvider.snapshot(provider: "one"))])
        let monitor = UsageMonitor(registry: ProviderRegistry(providers: [FakeProvider(id: "one", state: state), FakeProvider(id: "two", state: state)]), defaults: defaults)
        monitor.select(providerID: "two")
        XCTAssertEqual(defaults.string(forKey: "selectedProviderID"), "two")
        XCTAssertNil(defaults.object(forKey: "apiKey"))
        XCTAssertNil(defaults.object(forKey: "accessToken"))
    }

    @MainActor
    func testNetworkFailurePreservesLastGoodSnapshot() async throws {
        let suite = "UsageBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let good = FakeProvider.snapshot(provider: "codex", remaining: 76)
        let state = FakeState(results: [.success(good), .failure(ProviderError.network)])
        let monitor = UsageMonitor(registry: ProviderRegistry(providers: [FakeProvider(id: "codex", state: state)]), defaults: defaults)
        monitor.refresh(manual: true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(monitor.snapshot?.primary?.remainingPercent, 76)
        monitor.refresh(manual: true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(monitor.snapshot?.primary?.remainingPercent, 76)
        XCTAssertTrue(monitor.lastError)
    }
}

private actor FakeState {
    private var results: [Result<UsageSnapshot, Error>]
    init(results: [Result<UsageSnapshot, Error>]) { self.results = results }
    func next() -> Result<UsageSnapshot, Error> { results.isEmpty ? .failure(ProviderError.network) : results.removeFirst() }
}

private struct FakeProvider: UsageProvider {
    let id: String
    let state: FakeState
    let displayName = "Fixture"
    let allowedHosts: [String] = []
    func connectionStatus() async -> ProviderConnectionStatus { .connected(accountName: "Fixture") }
    func connect() async throws {}
    func disconnect() async throws {}
    func fetchUsage() async throws -> UsageSnapshot { try await state.next().get() }
    static func snapshot(provider: String, remaining: Int = 50) -> UsageSnapshot {
        UsageSnapshot(providerID: provider, accountID: "fixture", primary: UsageWindow(id: "fixture", label: "Test", remainingPercent: remaining, resetAt: nil), secondary: nil, fetchedAt: .now)
    }
}
