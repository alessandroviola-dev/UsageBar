import Foundation

/// Uses the authenticated GitHub CLI only. UsageBar neither reads nor stores a
/// GitHub token. GitHub has no documented stable public Copilot quota endpoint
/// usable through `gh`; this compatibility endpoint is therefore isolated here.
struct CopilotProvider: UsageProvider {
    let id = "github-copilot"
    let displayName = "GitHub Copilot"
    let statusName = "Copilot"
    private let discovery: LocalProviderDiscovery

    init(discovery: LocalProviderDiscovery = LocalProviderDiscovery()) {
        self.discovery = discovery
    }

    func connectionStatus() async -> ProviderConnectionStatus {
        switch discovery.state(for: id) {
        case .notInstalled: return .notInstalled
        case .needsLogin: return .needsLogin
        case .awaitingQuotaRead:
            do {
                _ = try await fetchUsage()
                return .connected(accountName: displayName)
            } catch let error as ProviderError {
                return error.connectionStatus
            } catch {
                return .temporarilyUnavailable
            }
        }
    }

    func fetchUsage() async throws -> UsageSnapshot {
        guard let gh = discovery.executable(named: "gh") else { throw ProviderError.notInstalled }
        guard discovery.state(for: id) != .needsLogin else { throw ProviderError.needsLogin }
        let response = try await Task.detached(priority: .utility) { try readSnapshot(gh: gh) }.value
        return try Self.parseSnapshot(response)
    }

    static func parseSnapshot(_ response: Data, now: Date = .now) throws -> UsageSnapshot {
        let user: CopilotUser
        do {
            user = try JSONDecoder().decode(CopilotUser.self, from: response)
        } catch {
            throw ProviderError.malformedResponse
        }
        let candidates = [
            ("chat", "Chat"),
            ("completions", "Completions"),
            ("premium_interactions", "Premium")
        ].compactMap { key, label -> UsageWindow? in
            guard let quota = user.quotaSnapshots[key], quota.hasQuota == true, quota.unlimited != true,
                  let percent = quota.percentRemaining else { return nil }
            return UsageWindow(id: key, label: label, remainingPercent: Int(percent.rounded()), resetAt: quota.quotaResetAt)
        }
        // An authenticated account can legitimately have no percentage-based
        // Copilot quota. Keep it connected without inventing a 100% window.
        return UsageSnapshot(providerID: "github-copilot", accountID: "github-cli", primary: candidates.first, secondary: candidates.dropFirst().first, fetchedAt: now)
    }

    private func readSnapshot(gh: URL) throws -> Data {
        let process = Process()
        process.executableURL = gh
        // There is currently no public, stable GitHub REST endpoint for this
        // account quota. gh owns the authentication and transport for this call.
        process.arguments = ["api", "/copilot_internal/user"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ProviderError.temporarilyUnavailable }
            return data
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.temporarilyUnavailable
        }
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
    let quotaResetAt: Date?

    enum CodingKeys: String, CodingKey { case percentRemaining = "percent_remaining", hasQuota = "has_quota", unlimited, quotaResetAt = "quota_reset_at" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        percentRemaining = try container.decodeIfPresent(Double.self, forKey: .percentRemaining)
        hasQuota = try container.decodeIfPresent(Bool.self, forKey: .hasQuota)
        unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited)
        if let seconds = try container.decodeIfPresent(Double.self, forKey: .quotaResetAt) {
            quotaResetAt = seconds > 10_000_000_000 ? Date(timeIntervalSince1970: seconds / 1_000) : Date(timeIntervalSince1970: seconds)
        } else {
            quotaResetAt = nil
        }
    }
}
