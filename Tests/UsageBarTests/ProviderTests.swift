import XCTest
@testable import UsageBar

final class ProviderTests: XCTestCase {
    @MainActor
    func testRegistryContainsExactlyCodexAndCopilotAndCodexIsDefault() {
        let registry = ProviderRegistry()
        XCTAssertEqual(registry.providers.map(\.id), ["codex", "github-copilot"])
        let suite = "UsageBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(UsageMonitor(registry: registry, defaults: defaults).activeProviderID, "codex")
    }

    func testLiveCodexQuotaWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["USAGEBAR_LIVE_PROVIDER_TESTS"] == "1" else {
            throw XCTSkip("Set USAGEBAR_LIVE_PROVIDER_TESTS=1 to read the local Codex account quota")
        }
        let snapshot = try await CodexProvider().fetchUsage()
        XCTAssertNotNil(snapshot.primary ?? snapshot.secondary)
    }

    func testLiveCopilotQuotaWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["USAGEBAR_LIVE_PROVIDER_TESTS"] == "1" else {
            throw XCTSkip("Set USAGEBAR_LIVE_PROVIDER_TESTS=1 to read the existing GitHub CLI Copilot quota")
        }
        let snapshot = try await CopilotProvider().fetchUsage()
        // Some authenticated plans have no percentage-based quota. A successful
        // read still proves the provider connection without manufacturing one.
        XCTAssertEqual(snapshot.providerID, "github-copilot")
    }

    func testCodexCLIAbsent() {
        let discovery = LocalProviderDiscovery(environment: ["PATH": "/definitely/absent"], fallbackSearchRoots: [])
        XCTAssertEqual(discovery.state(for: "codex"), .notInstalled)
    }

    func testCodexLoginAbsent() throws {
        let root = try temporaryTool(named: "codex", script: "#!/bin/sh\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let discovery = LocalProviderDiscovery(environment: ["PATH": root.deletingLastPathComponent().path], fallbackSearchRoots: [])
        XCTAssertEqual(discovery.state(for: "codex"), .needsLogin)
    }

    func testCodexTokenRevokedMapsToNeedsLogin() {
        let data = Data(#"{"id":2,"error":{"code":401,"message":"token_revoked"}}"#.utf8)
        XCTAssertThrowsError(try CodexProvider.parseRateLimitsResponse(data)) { error in
            XCTAssertEqual(error as? ProviderError, .authenticationFailed)
            XCTAssertEqual((error as? ProviderError)?.connectionStatus, .needsLogin)
        }
    }

    func testCodexParsesCurrentAndCompatibleRateLimitSchemas() throws {
        let current = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":24,"windowDurationMins":300,"resetsAt":1700000000},"secondary":{"usedPercent":50,"windowDurationMins":10080,"resetsAt":"1700100000000"}}}}"#.utf8)
        let snapshot = try CodexProvider.parseRateLimitsResponse(current, now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(snapshot.primary?.label, "5H")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 76)
        XCTAssertEqual(snapshot.secondary?.label, "7D")
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 50)

        let compatible = Data(#"{"id":2,"result":{"rate_limits":{"primary":{"used_percent":1,"window_duration_mins":300,"resets_at":"2024-01-01T00:00:00Z"}}}}"#.utf8)
        XCTAssertEqual(try CodexProvider.parseRateLimitsResponse(compatible).primary?.remainingPercent, 99)
    }

    func testCodexDoesNotInventMissingQuota() throws {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"windowDurationMins":300}}}}"#.utf8)
        XCTAssertNil(try CodexProvider.parseRateLimitsResponse(data).primary)
    }

    func testCodexMalformedResponse() {
        XCTAssertThrowsError(try CodexProvider.parseRateLimitsResponse(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? ProviderError, .malformedResponse)
        }
    }

    func testCodexAppServerHandshakeSequence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UsageBar-rpc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("requests.log")
        let script = root.appendingPathComponent("codex")
        let body = """
        #!/bin/sh
        read first
        printf '%s\\n' "$first" > "\(log.path)"
        echo '{"id":1,"result":{}}'
        read second
        read third
        printf '%s\\n%s\\n' "$second" "$third" >> "\(log.path)"
        echo '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300}}}}'
        """
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let response = try CodexAppServerSession.readRateLimits(executable: script, timeout: 2)
        XCTAssertEqual(try CodexProvider.parseRateLimitsResponse(response).primary?.remainingPercent, 80)
        let requests = try String(contentsOf: log)
        let lines = requests.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("\"id\":1"))
        XCTAssertEqual(lines[1], #"{"method":"initialized"}"#)
        XCTAssertTrue(lines[2].contains("\"id\":2"))
        XCTAssertTrue(lines[2].contains("account/rateLimits/read"))
    }

    func testCodexAppServerTimeout() throws {
        let tool = try temporaryTool(named: "codex", script: "#!/bin/sh\nsleep 2\n")
        defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
        XCTAssertThrowsError(try CodexAppServerSession.readRateLimits(executable: tool, timeout: 0.05)) {
            XCTAssertEqual($0 as? ProviderError, .temporarilyUnavailable)
        }
    }

    func testCodexBackendErrorIsTemporarilyUnavailable() {
        let data = Data(#"{"id":2,"error":{"code":500,"message":"backend unavailable"}}"#.utf8)
        XCTAssertThrowsError(try CodexProvider.parseRateLimitsResponse(data)) { error in
            XCTAssertEqual(error as? ProviderError, .temporarilyUnavailable)
        }
    }

    func testGitHubCLIAbsentAndNotAuthenticated() throws {
        let absent = LocalProviderDiscovery(environment: ["PATH": "/definitely/absent"], fallbackSearchRoots: [])
        XCTAssertEqual(absent.state(for: "github-copilot"), .notInstalled)
        let gh = try temporaryTool(named: "gh", script: "#!/bin/sh\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: gh.deletingLastPathComponent()) }
        let loggedOut = LocalProviderDiscovery(environment: ["PATH": gh.deletingLastPathComponent().path], fallbackSearchRoots: [])
        XCTAssertEqual(loggedOut.state(for: "github-copilot"), .needsLogin)
    }

    func testCopilotQuotaFixtureAndMalformedResponse() throws {
        let data = Data(#"{"quota_snapshots":{"chat":{"has_quota":true,"unlimited":false,"percent_remaining":80,"quota_reset_at":1700000000},"completions":{"has_quota":true,"unlimited":false,"percent_remaining":25}}}"#.utf8)
        let snapshot = try CopilotProvider.parseSnapshot(data)
        XCTAssertEqual(snapshot.primary?.label, "Chat")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 80)
        XCTAssertEqual(snapshot.secondary?.label, "Completions")
        XCTAssertThrowsError(try CopilotProvider.parseSnapshot(Data("[]".utf8))) {
            XCTAssertEqual($0 as? ProviderError, .malformedResponse)
        }
    }

    @MainActor
    func testCacheIsolationSwitchingAndPersistence() async throws {
        let suite = "UsageBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let codex = FixtureProvider(id: "codex", results: [.success(FixtureProvider.snapshot(id: "codex", remaining: 76)), .failure(ProviderError.temporarilyUnavailable)])
        let copilot = FixtureProvider(id: "github-copilot", results: [.success(FixtureProvider.snapshot(id: "github-copilot", remaining: 99))])
        let monitor = UsageMonitor(registry: ProviderRegistry(providers: [codex, copilot]), defaults: defaults)
        monitor.refresh(manual: true)
        try await Task.sleep(for: .milliseconds(100))
        monitor.select(providerID: "github-copilot")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(monitor.cachedSnapshot(for: "codex")?.primary?.remainingPercent, 76)
        XCTAssertEqual(monitor.cachedSnapshot(for: "github-copilot")?.primary?.remainingPercent, 99)
        monitor.select(providerID: "codex")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(monitor.snapshot?.primary?.remainingPercent, 76)
        XCTAssertEqual(defaults.string(forKey: "selectedProviderID"), "codex")
        XCTAssertEqual(monitor.cachedSnapshot(for: "github-copilot")?.primary?.remainingPercent, 99)
    }

    private func temporaryTool(named name: String, script: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UsageBar-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tool = root.appendingPathComponent(name)
        try Data(script.utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return tool
    }
}

private actor FixtureResults {
    var values: [Result<UsageSnapshot, Error>]
    init(_ values: [Result<UsageSnapshot, Error>]) { self.values = values }
    func next() -> Result<UsageSnapshot, Error> { values.isEmpty ? .failure(ProviderError.temporarilyUnavailable) : values.removeFirst() }
}

private struct FixtureProvider: UsageProvider {
    let id: String
    let displayName = "Fixture"
    private let values: FixtureResults

    init(id: String, results: [Result<UsageSnapshot, Error>]) {
        self.id = id
        values = FixtureResults(results)
    }

    func connectionStatus() async -> ProviderConnectionStatus { .connected(accountName: displayName) }
    func fetchUsage() async throws -> UsageSnapshot { try await values.next().get() }

    static func snapshot(id: String, remaining: Int) -> UsageSnapshot {
        UsageSnapshot(providerID: id, accountID: "fixture", primary: UsageWindow(id: "test", label: "Test", remainingPercent: remaining, resetAt: nil), secondary: nil, fetchedAt: .now)
    }
}
