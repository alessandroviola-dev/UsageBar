import Foundation
import Security

struct OpenAICostSnapshot: Sendable {
    let usd: Decimal
    let available: Bool
}

struct OpenAICostReader {
    private let service = "UsageBar.OpenAI.AdminAPIKey"
    func read() async -> OpenAICostSnapshot {
        guard let key = key() else { return .init(usd: 0, available: false) }
        let start = Int(Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(start)&limit=100")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { return .init(usd: 0, available: false) }
        var total = Decimal.zero
        for row in rows {
            if let amount = row["amount"] as? [String: Any], let value = amount["value"] as? NSNumber {
                total += Decimal(string: value.stringValue) ?? 0
            }
        }
        return .init(usd: total, available: true)
    }
    private func key() -> String? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: NSUserName(), kSecAttrService as String: service, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
