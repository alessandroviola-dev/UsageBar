import Foundation

enum LocalProviderState: Equatable, Sendable {
    case notInstalled
    case needsLogin
    /// The command is present and its local authentication check passed, but no
    /// quota request has verified the account yet.
    case awaitingQuotaRead

    var connectionStatus: ProviderConnectionStatus {
        switch self {
        case .notInstalled: .notInstalled
        case .needsLogin: .needsLogin
        case .awaitingQuotaRead: .temporarilyUnavailable
        }
    }
}

struct LocalProviderDiscovery: @unchecked Sendable {
    let fileManager: FileManager
    let environment: [String: String]
    let fallbackSearchRoots: [String]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallbackSearchRoots: [String] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.fallbackSearchRoots = fallbackSearchRoots
    }

    func executable(named name: String) -> URL? {
        let pathEntries = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        for root in pathEntries + fallbackSearchRoots where seen.insert(root).inserted {
            let candidate = URL(fileURLWithPath: root).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    func state(for providerID: String) -> LocalProviderState {
        switch providerID {
        case "codex":
            guard let codex = executable(named: "codex") else { return .notInstalled }
            return commandSucceeds(executable: codex, arguments: ["login", "status"]) ? .awaitingQuotaRead : .needsLogin
        case "github-copilot":
            guard let gh = executable(named: "gh") else { return .notInstalled }
            return commandSucceeds(executable: gh, arguments: ["auth", "status"]) ? .awaitingQuotaRead : .needsLogin
        default:
            return .notInstalled
        }
    }

    private func commandSucceeds(executable: URL, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
