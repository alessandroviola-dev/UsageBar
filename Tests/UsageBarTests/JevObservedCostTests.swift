import XCTest
@testable import UsageBar

final class JevObservedCostTests: XCTestCase {
    func testTelemetryAndCanaryAggregationAndDeduplication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let base = root.appendingPathComponent(".pi/agent/forgeapis")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("real-usage-canary-v1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("real-usage-canary-v2"), withIntermediateDirectories: true)
        let telemetry = [
            #"{"event":"router_classification","runId":"r","timestamp":"t","routerClassification":{"usage":{"inputTokens":400,"outputTokens":99}}}"#,
            #"{"event":"other","routerClassification":{"usage":{"inputTokens":999}}}"#,
            #"{"bad"}"#
        ].joined(separator: "\n")
        try telemetry.write(to: base.appendingPathComponent("telemetry.jsonl"), atomically: true, encoding: .utf8)
        let v1 = #"{"schema":"forgeapis-real-usage-canary-v1","schemaVersion":1,"limit":30,"records":[{"requestId":"a","jevInputTokens":600},{"requestId":"a","jevInputTokens":600}]}"#
        let v2 = #"{"schema":"forgeapis-real-usage-canary-v2","schemaVersion":2,"limit":30,"records":[{"requestId":"b","jevInputTokens":1000},{"requestId":"n","jevInputTokens":null}]}"#
        try v1.write(to: base.appendingPathComponent("real-usage-canary-v1/state.json"), atomically: true, encoding: .utf8)
        try v2.write(to: base.appendingPathComponent("real-usage-canary-v2/state.json"), atomically: true, encoding: .utf8)
        let reader = JevObservedCostReader(telemetryURL: base.appendingPathComponent("telemetry.jsonl"), v1URL: base.appendingPathComponent("real-usage-canary-v1/state.json"), v2URL: base.appendingPathComponent("real-usage-canary-v2/state.json"))
        let result = reader.read()
        XCTAssertEqual(result.inputTokens, 2_000)
        XCTAssertEqual(result.costUSD, JevPricing.cost(inputTokens: 2_000))
        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(JevCostFormatting.usd(result.costUSD), "$0.000084")
    }

    func testMissingAndZeroAreDistinct() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let missing = JevObservedCostReader(homeDirectory: root).read()
        XCTAssertEqual(missing.status, .unavailable)
        let file = root.appendingPathComponent(".pi/agent/forgeapis/telemetry.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{\"event\":\"router_classification\",\"routerClassification\":{\"usage\":{\"inputTokens\":0}}}".write(to: file, atomically: true, encoding: .utf8)
        let zero = JevObservedCostReader(telemetryURL: file, v1URL: root.appendingPathComponent("none"), v2URL: root.appendingPathComponent("none2")).read()
        XCTAssertEqual(zero.status, .available)
        XCTAssertEqual(zero.costUSD, 0)
        XCTAssertEqual(JevCostFormatting.usd(42), "$42.0000")
    }

    func testDashboardBaselineStartsAtConfirmedTotalAndAddsNewLedgerTokens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseline = directory.appendingPathComponent("baseline.json")
        let ledger = directory.appendingPathComponent("ledger.json")
        let anchor = #"{"schema":"usagebar-jev-baseline-v1","anchoredAt":"2026-01-01T00:00:00Z","tokens":123915,"requests":163,"costUSD":"0.0046"}"#
        let record = #"{"records":[{"requestId":"new-request","timestamp":"2026-01-01T00:00:01Z","jevInputTokens":100,"jevOutputTokens":20}]}"#
        try anchor.write(to: baseline, atomically: true, encoding: .utf8)
        try record.write(to: ledger, atomically: true, encoding: .utf8)

        let snapshot = JevObservedCostReader(
            telemetryURL: directory.appendingPathComponent("telemetry.jsonl"),
            v1URL: directory.appendingPathComponent("v1.json"),
            v2URL: directory.appendingPathComponent("v2.json"),
            forgeJevLedgerURL: ledger,
            forgeApisLedgerURL: directory.appendingPathComponent("other-ledger.json"),
            baselineURL: baseline
        ).read()

        XCTAssertEqual(snapshot.inputTokens, 124_035)
        XCTAssertEqual(snapshot.requestCount, 164)
        XCTAssertEqual(snapshot.status, .available)
        XCTAssertGreaterThan(snapshot.costUSD, Decimal(string: "0.0046")!)
    }

    func testJevMarkedTraceUsesRecordedCost() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let traces = directory.appendingPathComponent("forgejev-traces")
        try FileManager.default.createDirectory(at: traces, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let telemetry = directory.appendingPathComponent("telemetry.jsonl")
        let trace = traces.appendingPathComponent("session.jsonl")
        let line = #"{"event":"turn","provider":"jev","runId":"run-1","timestamp":"2026-01-01T00:00:00Z","usage":{"input":1118,"cost":0.002308}}"#
        try (line + "\n").write(to: trace, atomically: true, encoding: .utf8)

        let snapshot = JevObservedCostReader(
            telemetryURL: telemetry,
            v1URL: directory.appendingPathComponent("missing-v1.json"),
            v2URL: directory.appendingPathComponent("missing-v2.json"),
            traceDirectoryURL: traces
        ).read()

        XCTAssertEqual(snapshot.inputTokens, 1118)
        XCTAssertEqual(snapshot.costUSD, Decimal(string: "0.002308"))
        XCTAssertEqual(snapshot.status, .available)
    }
}
