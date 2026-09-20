import Foundation

/// Read-only adapter for the official Codex CLI app-server. It never reads
/// Codex files, credentials, prompts, conversations, or sessions.
struct CodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    private let discovery: LocalProviderDiscovery
    private static let client = CodexAppServerClient()

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
        guard let executable = discovery.executable(named: "codex") else { throw ProviderError.notInstalled }
        let response = try await Self.client.rateLimits(executable: executable)
        return try Self.parseRateLimitsResponse(response)
    }

    static func parseRateLimitsResponse(_ response: Data, now: Date = .now) throws -> UsageSnapshot {
        let decoded: RPCEnvelope
        do {
            decoded = try JSONDecoder().decode(RPCEnvelope.self, from: response)
        } catch {
            throw ProviderError.malformedResponse
        }
        if let error = decoded.error {
            let message = "\(error.code.map(String.init) ?? "") \(error.message ?? "")".lowercased()
            if message.contains("401") || message.contains("token_revoked") || message.contains("unauthorized") {
                throw ProviderError.authenticationFailed
            }
            throw ProviderError.temporarilyUnavailable
        }
        guard let limits = decoded.result?.limits else { throw ProviderError.malformedResponse }
        return UsageSnapshot(
            providerID: "codex",
            accountID: "codex-local",
            primary: window(limits.primary, id: "primary"),
            secondary: window(limits.secondary, id: "secondary"),
            fetchedAt: now
        )
    }

    private static func window(_ limit: LimitWindow?, id: String) -> UsageWindow? {
        // A missing usage percentage is deliberately not represented as 0% used.
        guard let limit, let usedPercent = limit.usedPercent else { return nil }
        let minutes = limit.windowDurationMins ?? 0
        return UsageWindow(
            id: id,
            label: UsageFormatting.windowLabel(minutes: minutes),
            remainingPercent: UsageFormatting.remainingPercent(usedPercent: usedPercent),
            resetAt: limit.resetsAt
        )
    }
}

/// Serializes callers so refresh and the Providers window never leave multiple
/// app-server children behind.
private actor CodexAppServerClient {
    private var inFlight: Task<Data, Error>?

    func rateLimits(executable: URL) async throws -> Data {
        if let inFlight { return try await inFlight.value }
        let task = Task.detached(priority: .utility) {
            try CodexAppServerSession.readRateLimits(executable: executable, timeout: 15)
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}

enum CodexAppServerSession {
    /// Implements the required JSON-RPC sequence exactly: initialize response,
    /// initialized notification, then account/rateLimits/read response.
    static func readRateLimits(executable: URL, timeout: TimeInterval) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe() // Provider diagnostics may contain account data.
        do {
            try process.run()
        } catch {
            throw ProviderError.temporarilyUnavailable
        }

        let watchdog = ProcessTimeout(process: process, after: timeout)
        defer {
            watchdog.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"UsageBar","version":"0.2.0"},"capabilities":{}}}"#
        let initialized = #"{"method":"initialized"}"#
        let read = #"{"id":2,"method":"account/rateLimits/read","params":null}"#
        input.fileHandleForWriting.write(Data((initialize + "\n").utf8))

        var buffer = Data()
        var sentRateLimitRead = false
        while !watchdog.didFire {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let requestID = object["id"] as? Int else { continue }
                if requestID == 1, !sentRateLimitRead {
                    if object["error"] != nil { return Data(line) }
                    input.fileHandleForWriting.write(Data((initialized + "\n" + read + "\n").utf8))
                    sentRateLimitRead = true
                } else if requestID == 2 {
                    return Data(line)
                }
            }
        }
        if watchdog.didFire { throw ProviderError.temporarilyUnavailable }
        throw ProviderError.malformedResponse
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
            self?.lock.lock()
            self?.fired = true
            self?.lock.unlock()
            if process?.isRunning == true { process?.terminate() }
        }
        timer.resume()
    }

    var didFire: Bool {
        lock.lock(); defer { lock.unlock() }
        return fired
    }

    func cancel() { timer.cancel() }
}

private struct RPCEnvelope: Decodable {
    let result: RateLimitsResult?
    let error: RPCError?
}

private struct RPCError: Decodable {
    let code: Int?
    let message: String?
}

private struct RateLimitsResult: Decodable {
    let limits: RateLimits

    enum CodingKeys: String, CodingKey { case rateLimits, rate_limits, limits, primary, secondary }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rateLimits = try container.decodeIfPresent(RateLimits.self, forKey: .rateLimits)
            ?? container.decodeIfPresent(RateLimits.self, forKey: .rate_limits)
            ?? container.decodeIfPresent(RateLimits.self, forKey: .limits) {
            limits = rateLimits
        } else if container.contains(.primary) || container.contains(.secondary) {
            limits = try RateLimits(from: decoder)
        } else {
            throw DecodingError.keyNotFound(CodingKeys.rateLimits, .init(codingPath: decoder.codingPath, debugDescription: "Missing rate limits"))
        }
    }
}

private struct RateLimits: Decodable {
    let primary: LimitWindow?
    let secondary: LimitWindow?
}

private struct LimitWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey { case usedPercent, used_percent, windowDurationMins, window_duration_mins, resetsAt, resets_at }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
            ?? container.decodeIfPresent(Double.self, forKey: .used_percent)
        windowDurationMins = try container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
            ?? container.decodeIfPresent(Int.self, forKey: .window_duration_mins)
        resetsAt = try Self.date(from: container, key: .resetsAt) ?? Self.date(from: container, key: .resets_at)
    }

    private static func date(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date? {
        if let seconds = try? container.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
        }
        guard let string = try? container.decode(String.self, forKey: key) else { return nil }
        if let seconds = Double(string) { return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds) }
        return ISO8601DateFormatter().date(from: string)
    }
}
