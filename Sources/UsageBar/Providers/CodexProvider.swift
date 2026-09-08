import Foundation

/// Uses Codex's official local app-server RPC. It never reads or copies Codex
/// credentials and sends no model-generation request.
struct CodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let allowedHosts: [String] = [] // The official Codex process owns its provider connection.

    func connectionStatus() async -> ProviderConnectionStatus {
        do {
            _ = try await fetchUsage()
            return .connected(accountName: "Codex")
        } catch {
            return .disconnected
        }
    }

    func connect() async throws { _ = try await fetchUsage() }
    func disconnect() async throws { /* Codex authentication belongs to the official CLI. */ }

    func fetchUsage() async throws -> UsageSnapshot {
        let response = try await Task.detached(priority: .utility) {
            try Self.readRateLimits()
        }.value
        let decoded = try JSONDecoder().decode(RPCResponse.self, from: response)
        guard let limits = decoded.result?.rateLimits else { throw ProviderError.malformedResponse }
        return UsageSnapshot(
            providerID: id,
            accountID: "codex-local",
            primary: limits.primary.map(Self.window),
            secondary: limits.secondary.map(Self.window),
            fetchedAt: .now
        )
    }

    private static func window(_ limit: LimitWindow) -> UsageWindow {
        UsageWindow(
            id: "\(limit.windowDurationMins ?? 0)",
            label: UsageFormatting.windowLabel(minutes: limit.windowDurationMins ?? 0),
            remainingPercent: UsageFormatting.remainingPercent(usedPercent: limit.usedPercent ?? 100),
            resetAt: limit.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private static func readRateLimits() throws -> Data {
        let executable = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let executable else { throw ProviderError.unavailable("Codex CLI is not installed or is not on a supported path.") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe() // Never surface provider output: it could include sensitive data.
        try process.run()

        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"UsageBar","version":"0.1.0"},"capabilities":{}}}"#
        let read = #"{"id":2,"method":"account/rateLimits/read","params":null}"#
        input.fileHandleForWriting.write(Data((initialize + "\n" + read + "\n").utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProviderError.commandFailed }

        for line in data.split(separator: 10) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  (object["id"] as? Int) == 2 else { continue }
            return Data(line)
        }
        throw ProviderError.malformedResponse
    }
}

private struct RPCResponse: Decodable {
    let result: RateLimitsResult?
}
private struct RateLimitsResult: Decodable {
    let rateLimits: RateLimits
}
private struct RateLimits: Decodable {
    let primary: LimitWindow?
    let secondary: LimitWindow?
}
private struct LimitWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}
