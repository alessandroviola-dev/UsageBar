import Foundation

protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var allowedHosts: [String] { get }

    func connectionStatus() async -> ProviderConnectionStatus
    func connect() async throws
    func disconnect() async throws
    func fetchUsage() async throws -> UsageSnapshot
}

enum ProviderError: LocalizedError, Sendable {
    case unavailable(String)
    case malformedResponse
    case commandFailed
    case authenticationFailed
    case rateLimited(retryAfter: Date?)
    case network

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .malformedResponse: return "The provider returned an invalid usage response."
        case .commandFailed: return "The provider usage service could not be started."
        case .authenticationFailed: return "The provider rejected the credential."
        case .rateLimited: return "The provider asked UsageBar to retry later."
        case .network: return "The provider request failed."
        }
    }
}

struct UnavailableProvider: UsageProvider {
    let id: String
    let displayName: String
    let reason: String
    let allowedHosts: [String] = []

    func connectionStatus() async -> ProviderConnectionStatus { .unsupported(reason: reason) }
    func connect() async throws { throw ProviderError.unavailable(reason) }
    func disconnect() async throws {}
    func fetchUsage() async throws -> UsageSnapshot { throw ProviderError.unavailable(reason) }
}
