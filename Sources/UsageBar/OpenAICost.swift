import Foundation
import Security

/// Separate fields prevent an observed file total from replacing official billing.
struct OpenAICostMetrics: Equatable, Sendable {
    var billedUSD: Decimal?
    var observedLocalUSD: Decimal?
}

struct OpenAICostReader: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    let endpoint: URL
    let telemetryURL: URL
    let transport: Transport
    let keyProvider: @Sendable () -> String?
    let now: @Sendable () -> Date

    init(
        endpoint: URL = URL(string: "https://api.openai.com/v1/organization/costs")!,
        telemetryURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pi/agent/forgeapis/telemetry.jsonl"),
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
        keyProvider: @escaping @Sendable () -> String? = { Self.keychainKey() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.endpoint = endpoint
        self.telemetryURL = telemetryURL
        self.transport = transport
        self.keyProvider = keyProvider
        self.now = now
    }

    // Schema: https://github.com/openai/openai-openapi/blob/master/openapi.yaml
    // GET /organization/costs -> UsageResponse -> UsageTimeBucket -> CostsResult.
    func readBilled() async -> Decimal? {
        guard let key = keyProvider(), !key.isEmpty else { return nil }
        let end = Int(now().timeIntervalSince1970)
        let start = end - 30 * 86_400
        var page: String?
        var cursors = Set<String>()
        var total = Decimal.zero
        do {
            repeat {
                try Task.checkCancellation()
                guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
                components.queryItems = [
                    URLQueryItem(name: "start_time", value: String(start)),
                    URLQueryItem(name: "end_time", value: String(end)),
                    URLQueryItem(name: "bucket_width", value: "1d"),
                    URLQueryItem(name: "limit", value: "31")
                ]
                if let page { components.queryItems?.append(URLQueryItem(name: "page", value: page)) }
                guard let url = components.url else { return nil }
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await transport(request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                let decoded = try JSONDecoder().decode(CostsPage.self, from: data)
                guard decoded.object == "page" else { return nil }
                for bucket in decoded.data {
                    guard bucket.object == "bucket", bucket.start_time < bucket.end_time,
                          bucket.start_time < end, bucket.end_time > start else { return nil }
                    for result in bucket.results {
                        guard result.object == "organization.costs.result",
                              result.amount.currency == "usd", !result.amount.value.isNaN else { return nil }
                        total += result.amount.value
                    }
                }
                if !decoded.has_more { return total }
                guard let next = decoded.next_page, !next.isEmpty, cursors.insert(next).inserted else { return nil }
                page = next
            } while true
        } catch {
            // No keys, identifiers, response bodies, or transport errors are logged.
            return nil
        }
    }

    func readObservedLocal() async -> Decimal? {
        let url = telemetryURL
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            var total = Decimal.zero
            for line in text.split(whereSeparator: \.isNewline) {
                guard let record = try? JSONDecoder().decode(TelemetryRecord.self, from: Data(line.utf8)),
                      record.event == "assistant_message", let cost = record.usage?.costTotal,
                      !cost.isNaN, cost >= 0 else { continue }
                total += cost
            }
            return total
        }.value
    }

    private struct CostsPage: Decodable {
        let object: String
        let data: [Bucket]
        let has_more: Bool
        let next_page: String?
    }
    private struct Bucket: Decodable {
        let object: String
        let start_time: Int
        let end_time: Int
        let results: [CostResult]
    }
    private struct CostResult: Decodable {
        let object: String
        let amount: Amount
    }
    private struct Amount: Decodable {
        let value: Decimal
        let currency: String
    }
    private struct TelemetryRecord: Decodable {
        let event: String
        let usage: Usage?
        struct Usage: Decodable { let costTotal: Decimal? }
    }

    private static func keychainKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: NSUserName(),
            kSecAttrService as String: "UsageBar.OpenAI.AdminAPIKey",
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Called by the normal 60-second monitor tick, and immediately by manual Refresh.
/// Each source has one worker; a manual refresh during I/O queues one fresh read.
@MainActor
final class OpenAICostMonitor {
    private let reader: OpenAICostReader
    private var billedTask: Task<Void, Never>?
    private var localTask: Task<Void, Never>?
    private var billedQueued = false
    private var localQueued = false
    private var nextBilledRead = Date.distantPast
    private(set) var metrics = OpenAICostMetrics()
    var onChange: (() -> Void)?

    init(reader: OpenAICostReader = OpenAICostReader()) { self.reader = reader }
    deinit { billedTask?.cancel(); localTask?.cancel() }

    func refresh(manual: Bool = false) {
        refreshLocal(manual: manual)
        refreshBilled(manual: manual)
    }

    private func refreshLocal(manual: Bool) {
        if localTask != nil {
            localQueued = localQueued || manual
        } else {
            let reader = reader
            localTask = Task { [weak self] in
                let value = await reader.readObservedLocal()
                guard !Task.isCancelled, let self else { return }
                self.metrics.observedLocalUSD = value
                self.localTask = nil
                self.onChange?()
                if self.localQueued {
                    self.localQueued = false
                    self.refreshLocal(manual: false)
                }
            }
        }
    }

    private func refreshBilled(manual: Bool) {
        if billedTask != nil {
            billedQueued = billedQueued || manual
        } else if manual || reader.now() >= nextBilledRead {
            nextBilledRead = reader.now().addingTimeInterval(300)
            let reader = reader
            billedTask = Task { [weak self] in
                let value = await reader.readBilled()
                guard !Task.isCancelled, let self else { return }
                self.metrics.billedUSD = value
                self.billedTask = nil
                self.onChange?()
                if self.billedQueued {
                    self.billedQueued = false
                    self.refreshBilled(manual: true)
                }
            }
        }
    }
}
