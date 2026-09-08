import XCTest
@testable import UsageBar

final class UsageFormattingTests: XCTestCase {
    func testRemainingPercentage() {
        XCTAssertEqual(UsageFormatting.remainingPercent(usedPercent: 0), 100)
        XCTAssertEqual(UsageFormatting.remainingPercent(usedPercent: 24), 76)
        XCTAssertEqual(UsageFormatting.remainingPercent(usedPercent: 58), 42)
        XCTAssertEqual(UsageFormatting.remainingPercent(usedPercent: 100), 0)
    }

    func testRemainingPercentageClampsMalformedValues() {
        XCTAssertEqual(UsageFormatting.remainingPercent(usedPercent: -20), 100)
        XCTAssertEqual(UsageFormatting.remainingPercent(usedPercent: 140), 0)
    }

    func testDurationLabels() {
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 300), "5H")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 1_440), "1D")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 10_080), "7D")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 90), "90M")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 0), "Limit")
    }

    func testStatusContainsAtMostTwoValues() {
        let snapshot = UsageSnapshot(
            providerID: "test", accountID: "test",
            primary: UsageWindow(id: "one", label: "5H", remainingPercent: 76, resetAt: nil),
            secondary: UsageWindow(id: "two", label: "7D", remainingPercent: 42, resetAt: nil),
            fetchedAt: .now
        )
        XCTAssertEqual(UsageFormatting.statusTitle(snapshot: snapshot), "5H 76% | 7D 42%")
    }

    func testSingleWindowAndMissingSnapshot() {
        let snapshot = UsageSnapshot(providerID: "test", accountID: "test", primary: UsageWindow(id: "one", label: "Credits", remainingPercent: 63, resetAt: nil), secondary: nil, fetchedAt: .now)
        XCTAssertEqual(UsageFormatting.statusTitle(snapshot: snapshot), "Credits 63%")
        XCTAssertEqual(UsageFormatting.statusTitle(snapshot: nil), "Usage ?")
    }

    func testUsageWindowClampsPercentage() {
        XCTAssertEqual(UsageWindow(id: "x", label: "X", remainingPercent: -4, resetAt: nil).remainingPercent, 0)
        XCTAssertEqual(UsageWindow(id: "x", label: "X", remainingPercent: 104, resetAt: nil).remainingPercent, 100)
    }

    func testResetFormatting() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(UsageFormatting.resetText(now.addingTimeInterval(3_600), now: now)?.hasPrefix("reset ") == true)
        XCTAssertTrue(UsageFormatting.resetText(now.addingTimeInterval(86_400), now: now)?.hasPrefix("reset ") == true)
        XCTAssertNil(UsageFormatting.resetText(nil, now: now))
    }

    func testUnavailableProviderReturnsConciseError() async {
        let provider = UnavailableProvider(id: "test", displayName: "Test", reason: "Unavailable")
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected an unavailable provider error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Unavailable")
        }
    }

    func testLiveCodexRateLimitsWhenAuthenticated() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/codex") else {
            throw XCTSkip("Codex CLI is not installed")
        }
        do {
            let snapshot = try await CodexProvider().fetchUsage()
            XCTAssertNotNil(snapshot.primary)
            XCTAssertTrue((snapshot.primary?.remainingPercent ?? -1) >= 0)
            XCTAssertTrue((snapshot.secondary?.remainingPercent ?? -1) <= 100)
        } catch {
            throw XCTSkip("Codex is not authenticated or app-server is unavailable")
        }
    }

    func testKeychainRoundTrip() throws {
        let account = "test-\(UUID().uuidString)"
        let value = Data("fake-test-secret".utf8)
        defer { try? KeychainStore.delete(account: account) }
        try KeychainStore.save(value, account: account)
        XCTAssertEqual(try KeychainStore.load(account: account), value)
        try KeychainStore.delete(account: account)
        XCTAssertNil(try KeychainStore.load(account: account))
    }
}
