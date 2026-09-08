import Foundation

/// Reuses GitHub CLI authentication through `gh api`; UsageBar never reads or
/// stores the GitHub token. The endpoint is a non-billable account snapshot.
struct CopilotProvider: UsageProvider {
    let id = "github-copilot"
    let displayName = "GitHub Copilot"
    let allowedHosts = ["api.github.com"]

    func connectionStatus() async -> ProviderConnectionStatus {
        do { _ = try await fetchUsage(); return .connected(accountName: "GitHub Copilot") }
        catch { return LocalProviderDiscovery().executable(named: "gh") == nil ? .unsupported(reason: "Not installed") : .disconnected }
    }
    func connect() async throws { _ = try await fetchUsage() }
    func disconnect() async throws {}

    func fetchUsage() async throws -> UsageSnapshot {
        let response = try await Task.detached(priority: .utility) { try Self.readSnapshot() }.value
        let user = try JSONDecoder().decode(CopilotUser.self, from: response)
        let candidates = [
            ("chat", "Chat"),
            ("completions", "Completions"),
            ("premium_interactions", "Premium")
        ].compactMap { key, label -> UsageWindow? in
            guard let value = user.quotaSnapshots[key], value.hasQuota == true, value.unlimited != true,
                  let percent = value.percentRemaining else { return nil }
            return UsageWindow(id: key, label: label, remainingPercent: Int(percent.rounded()), resetAt: value.quotaResetAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil })
        }
        guard let primary = candidates.first else { throw ProviderError.malformedResponse }
        return UsageSnapshot(providerID: id, accountID: "github-cli", primary: primary, secondary: candidates.dropFirst().first, fetchedAt: .now)
    }

    private static func readSnapshot() throws -> Data {
        guard let gh = LocalProviderDiscovery().executable(named: "gh") else { throw ProviderError.unavailable("GitHub CLI is not installed.") }
        let process = Process()
        process.executableURL = gh
        process.arguments = ["api", "/copilot_internal/user"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProviderError.authenticationFailed }
        return data
    }
}

private struct CopilotUser: Decodable {
    let quotaSnapshots: [String: CopilotQuota]
    enum CodingKeys: String, CodingKey { case quotaSnapshots = "quota_snapshots" }
}
private struct CopilotQuota: Decodable {
    let percentRemaining: Double?
    let hasQuota: Bool?
    let unlimited: Bool?
    let quotaResetAt: TimeInterval?
    enum CodingKeys: String, CodingKey {
        case percentRemaining = "percent_remaining", hasQuota = "has_quota", unlimited, quotaResetAt = "quota_reset_at"
    }
}
