import Foundation

struct JevCostSnapshot: Equatable, Sendable {
    let inputTokens: Int64
    let costUSD: Decimal
    let status: Status
    enum Status: Equatable, Sendable { case available, unavailable, partial }
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
        if value == 0 { return "$0" }
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
    let v1URL: URL
    let v2URL: URL

    init(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) {
        let base = homeDirectory.appendingPathComponent(".pi/agent/forgeapis", isDirectory: true)
        telemetryURL = base.appendingPathComponent("telemetry.jsonl")
        v1URL = base.appendingPathComponent("real-usage-canary-v1/state.json")
        v2URL = base.appendingPathComponent("real-usage-canary-v2/state.json")
    }

    init(telemetryURL: URL, v1URL: URL, v2URL: URL) {
        self.telemetryURL = telemetryURL; self.v1URL = v1URL; self.v2URL = v2URL
    }

    func read() -> JevCostSnapshot {
        var tokens: Int64 = 0
        var valid = false
        var malformed = false
        var identities = Set<String>()
        if let data = try? Data(contentsOf: telemetryURL), let text = String(data: data, encoding: .utf8) {
            valid = true
            for line in text.split(separator: "\n") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { malformed = true; continue }
                guard object["event"] as? String == "router_classification",
                      let classification = object["routerClassification"] as? [String: Any],
                      let usage = classification["usage"] as? [String: Any],
                      let input = integer(usage["inputTokens"]) else { malformed = true; continue }
                let identity = "telemetry:\(object["runId"] as? String ?? ""):\(object["timestamp"] as? String ?? "")"
                if identities.insert(identity).inserted { tokens += input }
            }
        } else if FileManager.default.fileExists(atPath: telemetryURL.path) { malformed = true }
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
        return JevCostSnapshot(inputTokens: tokens, costUSD: JevPricing.cost(inputTokens: tokens), status: malformed ? .partial : .available)
    }

    private func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, number.doubleValue >= 0, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue <= Double(Int64.max) else { return nil }
        return number.int64Value
    }
}
