import Foundation

/// Uses Codex's official local app-server RPC. It never reads or copies Codex
/// credentials and sends no model-generation request.
struct CodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let allowedHosts: [String] = [] // The official Codex process owns its provider connection.
    private static let client = CodexAppServerClient()

    func connectionStatus() async -> ProviderConnectionStatus {
        let discovery = LocalProviderDiscovery()
        switch discovery.state(for: id) {
        case .notInstalled:
            return .unsupported(reason: "Not installed")
        case .needsLogin:
            return .disconnected
        default:
            break
        }
        do { _ = try await fetchUsage(); return .connected(accountName: "Codex") }
        catch { return .disconnected }
    }

    func connect() async throws { _ = try await fetchUsage() }
    func disconnect() async throws { /* Authentication belongs to the official CLI. */ }

    func fetchUsage() async throws -> UsageSnapshot {
        let response = try await Self.client.rateLimits()
        let decoded = try JSONDecoder().decode(RPCResponse.self, from: response)
        if let error = decoded.error {
            let lowered = error.message.lowercased()
            if lowered.contains("401") || lowered.contains("token_revoked") || lowered.contains("unauthorized") {
                throw ProviderError.authenticationFailed
            }
            throw ProviderError.commandFailed
        }
        guard let limits = decoded.result?.rateLimits else { throw ProviderError.malformedResponse }
        return UsageSnapshot(providerID: id, accountID: "codex-local", primary: limits.primary.map(Self.window), secondary: limits.secondary.map(Self.window), fetchedAt: .now)
    }

    private static func window(_ limit: LimitWindow) -> UsageWindow {
        UsageWindow(id: "\(limit.windowDurationMins ?? 0)", label: UsageFormatting.windowLabel(minutes: limit.windowDurationMins ?? 0), remainingPercent: UsageFormatting.remainingPercent(usedPercent: limit.usedPercent ?? 100), resetAt: limit.resetsAt.map { Date(timeIntervalSince1970: $0) })
    }

    fileprivate static func readRateLimits() throws -> Data {
        guard let executable = LocalProviderDiscovery().executable(named: "codex") else {
            throw ProviderError.unavailable("Codex CLI is not installed or is not on a supported path.")
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe() // Never surface provider output; it could contain sensitive data.
        try process.run()

        let timeout = ProcessTimeout(process: process, after: 15)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit() // Always reap the short-lived child.
        }

        // Codex app-server requires the normal initialize handshake:
        // initialize request -> wait for id:1 -> initialized notification -> rate-limit request.
        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"UsageBar","version":"0.1.0"},"capabilities":{}}}"#
        let initialized = #"{"method":"initialized"}"#
        let read = #"{"id":2,"method":"account/rateLimits/read","params":null}"#
        input.fileHandleForWriting.write(Data((initialize + "\n").utf8))

        var buffer = Data()
        var initializationComplete = false

        while process.isRunning {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = object["id"] as? Int else { continue }

                if id == 1, !initializationComplete {
                    if object["error"] != nil { return line }
                    initializationComplete = true
                    input.fileHandleForWriting.write(Data((initialized + "\n" + read + "\n").utf8))
                    continue
                }

                if id == 2 {
                    return line
                }
            }
        }

        if timeout.didFire { throw ProviderError.commandFailed }
        throw ProviderError.malformedResponse
    }
}

/// Serializes concurrent callers onto one short-lived official app-server child.
private actor CodexAppServerClient {
    private var inFlight: Task<Data, Error>?

    func rateLimits() async throws -> Data {
        if let inFlight { return try await inFlight.value }
        let task = Task.detached(priority: .utility) { try CodexProvider.readRateLimits() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}

private final class ProcessTimeout: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private let timer: DispatchSourceTimer

    init(process: Process, after seconds: TimeInterval) {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self, weak process] in
            guard let self else { return }
            self.lock.lock(); self.fired = true; self.lock.unlock()
            if process?.isRunning == true { process?.terminate() }
        }
        timer.resume()
    }

    var didFire: Bool { lock.lock(); defer { lock.unlock() }; return fired }
    func cancel() { timer.setEventHandler {}; timer.cancel() }
}

private struct RPCResponse: Decodable {
    let result: RateLimitsResult?
    let error: RPCError?
}
private struct RPCError: Decodable { let code: Int?; let message: String }
private struct RateLimitsResult: Decodable { let rateLimits: RateLimits }
private struct RateLimits: Decodable { let primary: LimitWindow?; let secondary: LimitWindow? }
private struct LimitWindow: Decodable { let usedPercent: Double?; let windowDurationMins: Int?; let resetsAt: TimeInterval? }
