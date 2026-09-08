import Foundation

struct UsageWindow: Equatable, Sendable {
    let id: String
    let label: String
    let remainingPercent: Int
    let resetAt: Date?

    init(id: String, label: String, remainingPercent: Int, resetAt: Date?) {
        self.id = id
        self.label = label
        self.remainingPercent = min(100, max(0, remainingPercent))
        self.resetAt = resetAt
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let providerID: String
    let accountID: String
    let primary: UsageWindow?
    let secondary: UsageWindow?
    let fetchedAt: Date
}

enum ProviderConnectionStatus: Equatable, Sendable {
    case connected(accountName: String)
    case disconnected
    case unsupported(reason: String)
}

enum UsageFormatting {
    static func remainingPercent(usedPercent: Double) -> Int {
        let used = Int(usedPercent.rounded())
        return min(100, max(0, 100 - used))
    }

    static func windowLabel(minutes: Int) -> String {
        guard minutes > 0 else { return "Limit" }
        if minutes.isMultiple(of: 1_440) { return "\(minutes / 1_440)D" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)H" }
        return "\(minutes)M"
    }

    static func snapshotSummary(_ snapshot: UsageSnapshot?) -> String? {
        guard let snapshot else { return nil }
        let values = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.prefix(2).map { "\($0.label) \($0.remainingPercent)%" }.joined(separator: " | ")
    }

    static func statusTitle(providerName: String, snapshot: UsageSnapshot?) -> String {
        guard let summary = snapshotSummary(snapshot) else { return "\(providerName) ?" }
        return "\(providerName) \(summary)"
    }

    static func resetText(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.timeZone = .current
            formatter.dateFormat = "HH:mm"
            return "reset \(formatter.string(from: date))"
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM"
        return "reset \(formatter.string(from: date))"
    }
}
