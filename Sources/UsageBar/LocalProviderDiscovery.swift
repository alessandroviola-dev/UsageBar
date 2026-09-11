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
        var seen = Set<String>()
        for root in roots where seen.insert(root).inserted {
            let candidate = URL(fileURLWithPath: root).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    func state(for providerID: String) -> LocalProviderState {
        switch providerID {
        case "codex":
            guard let codex = executable(named: "codex") else { return .notInstalled }
            return commandSucceeds(executable: codex, arguments: ["login", "status"]) ? .connected : .needsLogin
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

    private func commandSucceeds(executable: URL, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        var processEnvironment = environment
        if processEnvironment["HOME"] == nil { processEnvironment["HOME"] = home.path }
        process.environment = processEnvironment
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Invokes only the official GitHub CLI and discards its output. No token is read by UsageBar.
    private func githubAuthenticated() -> Bool {
        guard let gh = executable(named: "gh") else { return false }
        return commandSucceeds(executable: gh, arguments: ["auth", "status"])
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
