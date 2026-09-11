import XCTest
@testable import UsageBar

final class LocalProviderDiscoveryTests: XCTestCase {
    func testKnownPathDetectsExecutable() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("UsageBar-discovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tool = root.appendingPathComponent("gemini")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let discovery = LocalProviderDiscovery(environment: ["PATH": root.path], home: root)
        XCTAssertEqual(discovery.executable(named: "gemini"), tool)
        XCTAssertEqual(discovery.state(for: "gemini-cli"), .detectedQuotaUnavailable)
    }

    func testCodexRequiresAValidLocalLogin() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("UsageBar-codex-auth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let codex = root.appendingPathComponent("codex")
        let loggedIn = "#!/bin/sh\nif [ \"$1\" = \"login\" ] && [ \"$2\" = \"status\" ]; then exit 0; fi\nexit 1\n"
        try Data(loggedIn.utf8).write(to: codex)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        var discovery = LocalProviderDiscovery(environment: ["PATH": root.path], home: root)
        XCTAssertEqual(discovery.state(for: "codex"), .connected)

        let loggedOut = "#!/bin/sh\nexit 1\n"
        try Data(loggedOut.utf8).write(to: codex)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        discovery = LocalProviderDiscovery(environment: ["PATH": root.path], home: root)
        XCTAssertEqual(discovery.state(for: "codex"), .needsLogin)
    }

    func testAbsentToolsAreNotInstalled() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let discovery = LocalProviderDiscovery(environment: ["PATH": root.path], home: root)
        XCTAssertEqual(discovery.state(for: "codex"), .notInstalled)
        XCTAssertEqual(discovery.state(for: "claude-code"), .notInstalled)
        XCTAssertEqual(discovery.state(for: "cursor"), .notInstalled)
        XCTAssertEqual(discovery.state(for: "opencode"), .notInstalled)
    }

    func testRegistryHasNoDuplicateProviderIDs() {
        let ids = ProviderRegistry().providers.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testCopilotLiveQuotaWhenGitHubCLIAuthenticated() async throws {
        guard LocalProviderDiscovery().state(for: "github-copilot") == .connected else {
            throw XCTSkip("GitHub CLI/Copilot authentication is unavailable")
        }
        let snapshot = try await CopilotProvider().fetchUsage()
        XCTAssertNotNil(snapshot.primary)
        XCTAssertTrue((snapshot.primary?.remainingPercent ?? -1) >= 0)
        XCTAssertTrue((snapshot.primary?.remainingPercent ?? 101) <= 100)
    }
}
