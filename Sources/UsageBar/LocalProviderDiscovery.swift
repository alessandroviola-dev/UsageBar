import Foundation

enum LocalProviderState: Equatable, Sendable {
    case connected
    case detectedQuotaUnavailable
    case needsLogin
    case notInstalled
    case needsAPIKey
    case unsupported

    var description: String {
        switch self {
        case .connected: return "Connected"
        case .detectedQuotaUnavailable: return "Detected — quota unavailable"
        case .needsLogin: return "Needs login"
        case .notInstalled: return "Not installed"
        case .needsAPIKey: return "Needs API key"
        case .unsupported: return "Unsupported"
        }
    }
}

struct LocalProviderDiscovery {
    let fileManager: FileManager
    let environment: [String: String]
    let home: URL

    init(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.fileManager = fileManager
        self.environment = environment
        self.home = home
    }

    func executable(named name: String) -> URL? {
        let pathEntries = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let roots = pathEntries + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for root in roots {
            let candidate = URL(fileURLWithPath: root).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    func state(for providerID: String) -> LocalProviderState {
        switch providerID {
        case "codex": return executable(named: "codex") == nil ? .notInstalled : .connected
        case "claude-code": return executable(named: "claude") == nil ? .notInstalled : .detectedQuotaUnavailable
        case "gemini-cli": return executable(named: "gemini") == nil ? .notInstalled : .detectedQuotaUnavailable
        case "github-copilot":
            guard executable(named: "gh") != nil || executable(named: "copilot") != nil else { return .notInstalled }
            return githubAuthenticated() ? .connected : .needsLogin
        case "cursor":
            let app = URL(fileURLWithPath: "/Applications/Cursor.app")
            return executable(named: "cursor") != nil || fileManager.fileExists(atPath: app.path) ? .detectedQuotaUnavailable : .notInstalled
        case "opencode": return executable(named: "opencode") == nil ? .notInstalled : .detectedQuotaUnavailable
        case "openrouter": return .needsAPIKey
        default: return .unsupported
        }
    }

    /// Invokes only the official GitHub CLI and discards its output. No token is read by UsageBar.
    private func githubAuthenticated() -> Bool {
        guard let gh = executable(named: "gh") else { return false }
        let process = Process()
        process.executableURL = gh
        process.arguments = ["auth", "status"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
    }
}

struct LocalToolProvider: UsageProvider {
    let id: String
    let displayName: String
    let allowedHosts: [String] = []
    func connectionStatus() async -> ProviderConnectionStatus {
        let state = LocalProviderDiscovery().state(for: id)
        return state == .connected ? .connected(accountName: displayName) : .unsupported(reason: state.description)
    }
    func connect() async throws { throw ProviderError.unavailable(LocalProviderDiscovery().state(for: id).description) }
    func disconnect() async throws {}
    func fetchUsage() async throws -> UsageSnapshot { throw ProviderError.unavailable(LocalProviderDiscovery().state(for: id).description) }
}
