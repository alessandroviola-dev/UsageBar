import XCTest
@testable import UsageBar

final class UsageFormattingTests: XCTestCase {
    func testRemainingPercentageAndDurationLabels() {
        XCTAssertEqual(UsageFormatting.remainingPercent(usedPercent: 0), 100)
        XCTAssertEqual(UsageFormatting.remainingPercent(usedPercent: 24), 76)
        XCTAssertEqual(UsageFormatting.remainingPercent(usedPercent: 140), 0)
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 300), "5H")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 10_080), "7D")
    }

    func testResetCountdownFormatter() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(UsageFormatting.resetCountdown(now.addingTimeInterval((2 * 60 + 34) * 60), now: now), "02:34H")
        XCTAssertEqual(UsageFormatting.resetCountdown(now.addingTimeInterval((3 * 24 * 60 + 7 * 60 + 12) * 60), now: now), "3D 07:12H")
        XCTAssertEqual(UsageFormatting.resetCountdown(now.addingTimeInterval(-60), now: now), "00:00H")
    }

    func testMenuBarHasNoCountdownAndCodexDropdownDoes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(
            providerID: "codex",
            accountID: "test",
            primary: UsageWindow(id: "5h", label: "5H", remainingPercent: 23, resetAt: now.addingTimeInterval((2 * 60 + 34) * 60)),
            secondary: UsageWindow(id: "7d", label: "7D", remainingPercent: 50, resetAt: now.addingTimeInterval((3 * 24 * 60 + 7 * 60 + 12) * 60)),
            fetchedAt: now
        )
        XCTAssertEqual(UsageFormatting.statusTitle(providerName: "Codex", snapshot: snapshot), "Codex 5H 23% | 7D 50%")
        XCTAssertEqual(UsageFormatting.menuSnapshotSummary(snapshot, showResetCountdown: true, now: now), "5H 23% 02:34H | 7D 50% 3D 07:12H")
    }
}
