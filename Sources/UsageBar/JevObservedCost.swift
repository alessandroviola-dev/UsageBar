import Foundation

struct JevCostSnapshot: Equatable, Sendable {
    let inputTokens: Int64
    let costUSD: Decimal
    let status: Status
    let requestCount: Int64
    enum Status: Equatable, Sendable { case available, unavailable, partial }

    init(inputTokens: Int64, costUSD: Decimal, status: Status, requestCount: Int64 = 0) {
        self.inputTokens = inputTokens
        self.costUSD = costUSD
        self.status = status
        self.requestCount = requestCount
    }
}

enum JevPricing {
    // Public Jev input price, versioned here so accounting is not duplicated in UI.
    static let version = "jev-input-42-per-billion-v1"
    static let inputUSDPerBillionTokens = Decimal(42)
    static func cost(inputTokens: Int64) -> Decimal {
        Decimal(inputTokens) * inputUSDPerBillionTokens / Decimal(1_000_000_000)
    }
}

enum JevCostFormatting {
    static func usd(_ value: Decimal) -> String {
        // Keep four decimal places even when the amount is zero, so very small
        // API costs are not presented with the ambiguous "$0" label.
        if value == 0 { return "$0.0000" }
        let ns = value as NSDecimalNumber
        let double = ns.doubleValue
        if double >= 1 { return String(format: "$%.2f", double) }
        if double >= 0.01 { return String(format: "$%.4f", double) }
        // Six decimals preserve the expected sub-cent observations.
        return String(format: "$%.6f", double).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }
}

struct JevObservedCostReader {
    let telemetryURL: URL
    let traceDirectoryURL: URL
    let v1URL: URL
    let v2URL: URL
    let forgeJevLedgerURL: URL
    let forgeApisLedgerURL: URL
    let baselineURL: URL

    init(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) {
        let base = homeDirectory.appendingPathComponent(".pi/agent/forgeapis", isDirectory: true)
        telemetryURL = base.appendingPathComponent("telemetry.jsonl") // Legacy ForgeApis location.
        traceDirectoryURL = homeDirectory.appendingPathComponent(".pi/agent/forgejev-traces", isDirectory: true)
        v1URL = base.appendingPathComponent("real-usage-canary-v1/state.json")
        v2URL = base.appendingPathComponent("real-usage-canary-v2/state.json")
        let agent = homeDirectory.appendingPathComponent(".pi/agent", isDirectory: true)
        forgeJevLedgerURL = agent.appendingPathComponent("forgejev/routing/ledger.json")
        // ForgeApis canonical ledger; production-ledger-v2.json is only a legacy fixture.
        forgeApisLedgerURL = agent.appendingPathComponent("forgeapis/routing/ledger.json")
        baselineURL = agent.appendingPathComponent("forgejev/usage-baseline.json")
    }

    init(telemetryURL: URL, v1URL: URL, v2URL: URL, traceDirectoryURL: URL? = nil, forgeJevLedgerURL: URL? = nil, forgeApisLedgerURL: URL? = nil, baselineURL: URL? = nil) {
        self.telemetryURL = telemetryURL
        self.traceDirectoryURL = traceDirectoryURL ?? telemetryURL.deletingLastPathComponent().appendingPathComponent("forgejev-traces", isDirectory: true)
        self.v1URL = v1URL
        self.v2URL = v2URL
        let agent = telemetryURL.deletingLastPathComponent().deletingLastPathComponent()
        self.forgeJevLedgerURL = forgeJevLedgerURL ?? agent.appendingPathComponent("forgejev/routing/ledger.json")
        self.forgeApisLedgerURL = forgeApisLedgerURL ?? agent.appendingPathComponent("forgeapis/routing/ledger.json")
        self.baselineURL = baselineURL ?? agent.appendingPathComponent("forgejev/usage-baseline.json")
    }

    func read() -> JevCostSnapshot {
        // Use the complete ForgeApis telemetry. The baseline is only for the
        // legacy Jev counter and would hide costs recorded by ForgeApis.
        var tokens: Int64 = 0
        var observedCost = Decimal.zero
        var hasObservedCost = false
        var valid = false
        var malformed = false
        var identities = Set<String>()
        var telemetryURLs = [telemetryURL]
        if let traceURLs = try? FileManager.default.contentsOfDirectory(
            at: traceDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            telemetryURLs += traceURLs.filter { $0.pathExtension == "jsonl" }
        }
        for url in telemetryURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { malformed = true; continue }
            valid = true
            for line in text.split(separator: "\n") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { malformed = true; continue }
                let event = object["event"] as? String
                let isLegacyTelemetry = url == telemetryURL
                // Legacy assistant_message costs are Pi/OpenAI list prices for every model call,
                // not Jev spend. Accept them only from a trace explicitly marked as Jev.
                let isJevTrace = !isLegacyTelemetry && (event == "turn" || event == "jev_usage") && object["provider"] as? String == "jev"
                guard (isLegacyTelemetry && event == "router_classification") || isJevTrace else { continue }
                let usage = (object["routerClassification"] as? [String: Any])?["usage"] as? [String: Any] ?? object["usage"] as? [String: Any]
                guard let usage, let input = integer(usage["inputTokens"] ?? usage["input"]) else { malformed = true; continue }
                let identity = "telemetry:\(object["runId"] as? String ?? object["sessionId"] as? String ?? url.lastPathComponent):\(object["timestamp"] as? String ?? ""):\(object["event"] as? String ?? "")"
                if identities.insert(identity).inserted {
                    tokens += input
                    if isJevTrace, let cost = decimal(usage["costTotal"] ?? usage["cost"]) {
                        observedCost += cost
                        hasObservedCost = true
                    }
                }
            }
        }
        let canaries = [v1URL, v2URL]
        for (index, url) in canaries.enumerated() {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root["schema"] as? String == (index == 0 ? "forgeapis-real-usage-canary-v1" : "forgeapis-real-usage-canary-v2"),
                  root["schemaVersion"] as? Int == index + 1,
                  let records = root["records"] as? [[String: Any]] else { malformed = true; continue }
            valid = true
            for record in records {
                guard let request = record["requestId"] as? String else { malformed = true; continue }
                guard let raw = record["jevInputTokens"] else { malformed = true; continue }
                guard let input = integer(raw) else { continue } // null means no observed usage
                if identities.insert("canary:\(request)").inserted { tokens += input }
            }
        }
        guard valid else { return JevCostSnapshot(inputTokens: 0, costUSD: 0, status: .unavailable) }
        let cost = hasObservedCost ? observedCost : JevPricing.cost(inputTokens: tokens)
        return JevCostSnapshot(inputTokens: tokens, costUSD: cost, status: malformed ? .partial : .available)
    }

    private struct Baseline {
        let date: Date
        let tokens: Int64
        let requests: Int64
        let costUSD: Decimal
    }

    private func readBaseline() -> Baseline? {
        guard let data = try? Data(contentsOf: baselineURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["schema"] as? String == "usagebar-jev-baseline-v1",
              let timestamp = root["anchoredAt"] as? String,
              let date = parseDate(timestamp),
              let tokens = integer(root["tokens"]),
              let requests = integer(root["requests"]),
              let costString = root["costUSD"] as? String,
              let cost = Decimal(string: costString, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return Baseline(date: date, tokens: tokens, requests: requests, costUSD: cost)
    }

    private func readSinceBaseline(_ baseline: Baseline) -> JevCostSnapshot {
        var tokens = baseline.tokens
        var requests = baseline.requests
        var cost = baseline.costUSD
        var malformed = false
        var identities = Set<String>()
        let rate = baseline.costUSD / Decimal(max(baseline.tokens, 1))
        for url in [forgeJevLedgerURL, forgeApisLedgerURL] {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let records = root["records"] as? [[String: Any]] else { malformed = true; continue }
            for record in records {
                guard let request = record["requestId"] as? String,
                      let timestamp = record["timestamp"] as? String,
                      let date = parseDate(timestamp),
                      date > baseline.date,
                      let input = integer(record["jevInputTokens"]) else { continue }
                let output = integer(record["jevOutputTokens"]) ?? 0
                if identities.insert(request).inserted {
                    let total = input + output
                    tokens += total
                    requests += 1
                    cost += Decimal(total) * rate
                }
            }
        }
        if let data = try? Data(contentsOf: traceDirectoryURL.appendingPathComponent("jev-usage.jsonl")),
           let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      object["event"] as? String == "jev_usage",
                      object["source"] as? String == "forgeapis",
                      let request = object["requestId"] as? String,
                      let timestamp = object["timestamp"] as? String,
                      let date = parseDate(timestamp), date > baseline.date,
                      let usage = object["usage"] as? [String: Any],
                      let input = integer(usage["inputTokens"]),
                      identities.insert("shared:\(request)").inserted else { continue }
                let output = integer(usage["outputTokens"]) ?? 0
                let total = input + output
                tokens += total
                requests += 1
                cost += Decimal(total) * rate
            }
        }
        return JevCostSnapshot(inputTokens: tokens, costUSD: cost, status: malformed ? .partial : .available, requestCount: requests)
    }

    private func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func decimal(_ value: Any?) -> Decimal? {
        guard let number = value as? NSNumber, number.doubleValue >= 0 else { return nil }
        return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, number.doubleValue >= 0, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue <= Double(Int64.max) else { return nil }
        return number.int64Value
    }
}
