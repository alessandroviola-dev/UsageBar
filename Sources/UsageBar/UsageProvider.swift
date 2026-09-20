import Foundation

/// A provider is read-only: authentication remains with its official tool.
protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var statusName: String { get }

    /// This must perform a real quota read before reporting `.connected`.
    func connectionStatus() async -> ProviderConnectionStatus
    func fetchUsage() async throws -> UsageSnapshot
}

extension UsageProvider {
    var statusName: String { displayName }
}

enum ProviderError: LocalizedError, Sendable, Equatable {
    case notInstalled
    case needsLogin
    case temporarilyUnavailable
    case malformedResponse
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The required official tool is not installed."
        case .needsLogin, .authenticationFailed:
            return "Sign in with the official provider tool, then try again."
        case .temporarilyUnavailable:
            return "The provider is temporarily unavailable."
        case .malformedResponse:
            return "The provider returned an invalid usage response."
        }
    }

    var connectionStatus: ProviderConnectionStatus {
        switch self {
        case .notInstalled: .notInstalled
        case .needsLogin, .authenticationFailed: .needsLogin
        case .temporarilyUnavailable, .malformedResponse: .temporarilyUnavailable
        }
    }
}
