import Foundation
import Security

struct OpenAICostSnapshot: Sendable {
    let usd: Decimal
    let available: Bool
}

struct OpenAICostReader {
    private let service = "UsageBar.OpenAI.AdminAPIKey"
    func read() async -> OpenAICostSnapshot {
        guard let key = key() else { return localTelemetryCost() }
        let start = Int(Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(start)&limit=100")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { return localTelemetryCost() }
        var total = Decimal.zero
        for row in rows {
            if let amount = row["amount"] as? [String: Any], let value = amount["value"] as? NSNumber {
                total += Decimal(string: value.stringValue) ?? 0
            }
        }
        // ForgeApis is the source used by the normal project API key. Prefer
        // its settled local total when present; the Admin API can validly
        // return zero for a different organization/project.
        let local = localTelemetryCost()
        return local.available && local.usd > 0 ? local : .init(usd: total, available: true)
    }

    private func localTelemetryCost() -> OpenAICostSnapshot {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".pi/agent/forgeapis/telemetry.jsonl")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return .init(usd: 0, available: false)
        }
        var total = Decimal.zero
        for line in text.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["event"] as? String == "assistant_message",
                  let usage = object["usage"] as? [String: Any],
                  let value = usage["costTotal"] as? NSNumber,
                  let cost = Decimal(string: value.stringValue, locale: Locale(identifier: "en_US_POSIX")) else { continue }
            total += cost
        }
        return .init(usd: total, available: true)
    }

    private func key() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: NSUserName(), kSecAttrService as String: service, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
