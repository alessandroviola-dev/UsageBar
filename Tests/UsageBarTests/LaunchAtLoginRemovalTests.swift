import XCTest
@testable import UsageBar

final class LaunchAtLoginRemovalTests: XCTestCase {
    func testUnregisterSuccessExitCode() {
        var calls = 0
        XCTAssertEqual(LaunchAtLoginRemoval.exitCode { calls += 1 }, 0)
        XCTAssertEqual(calls, 1)
    }

    func testUnregisterErrorExitCode() {
        struct FixtureError: Error {}
        XCTAssertNotEqual(LaunchAtLoginRemoval.exitCode { throw FixtureError() }, 0)
        XCTAssertNotEqual(LaunchAtLoginRemoval.exitCode {
            throw LaunchAtLoginRemoval.UnsupportedOS()
        }, 0)
    }
}
