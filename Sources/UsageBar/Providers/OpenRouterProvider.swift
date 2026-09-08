import Foundation

protocol APIKeyProvider: UsageProvider {
    /// Validates through a documented non-billable endpoint before retaining a key.
    func connect(accountName: String, apiKey: String) async throws
}

/// OpenRouter's documented credits endpoint reports both purchased credit and
/// consumed credit, providing a real denominator without any model request.
struct OpenRouterProvider: APIKeyProvider {
    let id = "openrouter"
    let displayName = "OpenRouter"
    let allowedHosts = ["openrouter.ai"]
    private let credentialAccount = "openrouter.default"

    func connectionStatus() async -> ProviderConnectionStatus {
        do {
            return try KeychainStore.load(account: credentialAccount) == nil ? .disconnected : .connected(accountName: "OpenRouter")
        } catch { return .disconnected }
    }

    func connect() async throws {
        guard let key = try KeychainStore.load(account: credentialAccount), let value = String(data: key, encoding: .utf8) else {
            throw ProviderError.unavailable("Add an OpenRouter API key first.")
        }
        _ = try await fetchUsage(apiKey: value)
    }

    func connect(accountName: String, apiKey: String) async throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.unavailable("An API key is required.")
        }
        _ = try await fetchUsage(apiKey: apiKey)
        try KeychainStore.save(Data(apiKey.utf8), account: credentialAccount)
        // The local display name is non-secret metadata.
        UserDefaults.standard.set(accountName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "accountLabel.openrouter.default")
    }

    func disconnect() async throws {
        try KeychainStore.delete(account: credentialAccount)
        UserDefaults.standard.removeObject(forKey: "accountLabel.openrouter.default")
    }

    func fetchUsage() async throws -> UsageSnapshot {
        guard let data = try KeychainStore.load(account: credentialAccount), let key = String(data: data, encoding: .utf8) else {
            throw ProviderError.unavailable("OpenRouter is not connected.")
        }
        return try await fetchUsage(apiKey: key)
    }

    private func fetchUsage(apiKey: String) async throws -> UsageSnapshot {
        let endpoint = try ProviderEndpoint(url: URL(string: "https://openrouter.ai/api/v1/credits")!, allowedHosts: allowedHosts)
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.network }
        if http.statusCode == 401 || http.statusCode == 403 { throw ProviderError.authenticationFailed }
        if http.statusCode == 429 { throw ProviderError.rateLimited(retryAfter: RetryAfter.date(from: http.value(forHTTPHeaderField: "Retry-After"))) }
        guard (200...299).contains(http.statusCode) else { throw ProviderError.network }
        return UsageSnapshot(providerID: id, accountID: "openrouter.default", primary: try Self.parseCreditsResponse(data), secondary: nil, fetchedAt: .now)
    }

    static func parseCreditsResponse(_ data: Data) throws -> UsageWindow {
        let credits = try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data).data
        guard credits.totalCredits.isFinite, credits.totalUsage.isFinite, credits.totalCredits > 0 else { throw ProviderError.malformedResponse }
        let remaining = max(0, credits.totalCredits - credits.totalUsage)
        return UsageWindow(id: "credits", label: "Credits", remainingPercent: Int((remaining / credits.totalCredits * 100).rounded()), resetAt: nil)
    }
}

struct ProviderEndpoint: Sendable {
    let url: URL
    init(url: URL, allowedHosts: [String]) throws {
        guard url.scheme == "https", let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            throw ProviderError.unavailable("The provider endpoint is not allowed.")
        }
        self.url = url
    }
}

struct RetryAfter {
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value) { return .now.addingTimeInterval(max(0, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

private struct OpenRouterCreditsResponse: Decodable {
    let data: Credits
    struct Credits: Decodable {
        let totalCredits: Double
        let totalUsage: Double
        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
}
