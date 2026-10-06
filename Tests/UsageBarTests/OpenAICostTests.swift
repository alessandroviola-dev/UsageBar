import XCTest
@testable import UsageBar

final class OpenAICostTests: XCTestCase {
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func telemetry(_ text: String = #"{"event":"assistant_message","usage":{"costTotal":5.5}}"#) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("telemetry.jsonl")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func page(_ buckets: [[String]], more: Bool = false, cursor: String? = nil) -> String {
        let data = buckets.map { values in
            let results = values.map { #"{"object":"organization.costs.result","amount":{"value":\#($0),"currency":"usd"}}"# }.joined(separator: ",")
            return #"{"object":"bucket","start_time":1799913600,"end_time":1800000000,"results":[\#(results)]}"#
        }.joined(separator: ",")
        let next = cursor.map { "\"\($0)\"" } ?? "null"
        return #"{"object":"page","data":[\#(data)],"has_more":\#(more),"next_page":\#(next)}"#
    }

    private func reader(_ server: FixtureCostsServer, url: URL, key: String? = "fixture-not-a-real-key") -> OpenAICostReader {
        let clock = clock
        return OpenAICostReader(
            endpoint: URL(string: "https://fixture.invalid/costs")!, telemetryURL: url,
            transport: { try await server.respond($0) }, keyProvider: { key }, now: { clock }
        )
    }

    func testOfficialNestedResultsAggregation() async throws {
        let server = FixtureCostsServer([page([["0.06"]])])
        let value = await reader(server, url: try telemetry()).readBilled()
        XCTAssertEqual(value, Decimal(string: "0.06"))
    }

    func testMultipleBucketsAndResults() async throws {
        let server = FixtureCostsServer([page([["0.01", "0.02"], ["1.23", "2.34"]])])
        let value = await reader(server, url: try telemetry()).readBilled()
        XCTAssertEqual(value, Decimal(string: "3.60"))
    }

    func testPaginationAndExactThirtyDayWindow() async throws {
        let server = FixtureCostsServer([page([["1"]], more: true, cursor: "cursor +/="), page([["2", "3"]])])
        let value = await reader(server, url: try telemetry()).readBilled()
        XCTAssertEqual(value, 6)
        let requests = await server.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "end_time" }?.value, "1800000000")
            XCTAssertEqual(query.first { $0.name == "start_time" }?.value, "1797408000")
        }
        let query = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "page" }?.value, "cursor +/=")
    }

    func testOfficialZeroNeverFallsBackToLocal() async throws {
        let r = reader(FixtureCostsServer([page([["0"]])]), url: try telemetry())
        let billed = await r.readBilled()
        let local = await r.readObservedLocal()
        XCTAssertEqual(billed, 0)
        XCTAssertEqual(local, Decimal(string: "5.5"))
    }

    func testPositiveOfficialAndLocalRemainSeparate() async throws {
        let r = reader(FixtureCostsServer([page([["1.25"]])]), url: try telemetry())
        let billed = await r.readBilled()
        let local = await r.readObservedLocal()
        XCTAssertEqual(billed, Decimal(string: "1.25"))
        XCTAssertEqual(local, Decimal(string: "5.5"))
    }

    func testAPIFailureLeavesLocalAvailable() async throws {
        let r = reader(FixtureCostsServer(["{}"], status: 503), url: try telemetry())
        let billed = await r.readBilled()
        let local = await r.readObservedLocal()
        XCTAssertNil(billed)
        XCTAssertEqual(local, Decimal(string: "5.5"))
    }

    func testMissingKeyDoesNotCallTransportAndLocalWorks() async throws {
        let server = FixtureCostsServer([])
        let r = reader(server, url: try telemetry(), key: nil)
        let billed = await r.readBilled()
        let local = await r.readObservedLocal()
        let calls = await server.requests.count
        XCTAssertNil(billed)
        XCTAssertEqual(local, Decimal(string: "5.5"))
        XCTAssertEqual(calls, 0)
    }

    func testMalformedTelemetryIsIgnored() async throws {
        let url = try telemetry([
            "{broken", #"{"event":"assistant_message","usage":{"costTotal":true}}"#,
            #"{"event":"assistant_message","usage":{"costTotal":-1}}"#,
            #"{"event":"assistant_message","usage":{"costTotal":null}}"#,
            #"{"event":"other","usage":{"costTotal":999}}"#,
            #"{"event":"assistant_message","usage":{"costTotal":0.1}}"#,
            #"{"event":"assistant_message","usage":{"costTotal":0.2}}"#
        ].joined(separator: "\n"))
        let value = await reader(FixtureCostsServer([]), url: url, key: nil).readObservedLocal()
        XCTAssertEqual(value, Decimal(string: "0.3"))
    }

    func testMalformedOfficialAndUnsupportedCurrencyAreUnavailable() async throws {
        for body in ["{bad", "{}", #"{"data":[{"amount":{"value":3}}]}"#,
                     page([["1"]]).replacingOccurrences(of: "usd", with: "eur"),
                     page([["1"]]).replacingOccurrences(of: "\"value\":1", with: "\"value\":true")] {
            let value = await reader(FixtureCostsServer([body]), url: try telemetry()).readBilled()
            XCTAssertNil(value)
        }
    }

    func testEmptyValidPageIsZeroAndMissingLocalIsUnavailable() async {
        let r = reader(FixtureCostsServer([page([])]), url: URL(fileURLWithPath: "/nonexistent/fixture.jsonl"))
        let billed = await r.readBilled()
        let local = await r.readObservedLocal()
        XCTAssertEqual(billed, 0)
        XCTAssertNil(local)
    }

    func testPaginationFailureAndRepeatedCursorAreUnavailable() async throws {
        for pages in [[page([["1"]], more: true)],
                      [page([["1"]], more: true, cursor: "repeat"), page([["2"]], more: true, cursor: "repeat")],
                      [page([["1"]], more: true, cursor: "next"), "{}"]] {
            let value = await reader(FixtureCostsServer(pages), url: try telemetry()).readBilled()
            XCTAssertNil(value)
        }
    }

    func testTransportFailureIsUnavailable() async throws {
        let value = await reader(FixtureCostsServer([]), url: try telemetry()).readBilled()
        XCTAssertNil(value)
    }

    @MainActor
    func testPollingManualRefreshAndNoConcurrentRequests() async throws {
        let url = try telemetry()
        let server = FixtureCostsServer([page([["1"]]), page([["2"]])], delay: .milliseconds(50))
        let monitor = OpenAICostMonitor(reader: reader(server, url: url))
        monitor.refresh()
        // A manual click while official I/O is pending must cause a fresh read afterwards.
        monitor.refresh(manual: true)
        monitor.refresh(manual: true)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(monitor.metrics.billedUSD, 2)
        XCTAssertEqual(monitor.metrics.observedLocalUSD, Decimal(string: "5.5"))
        let calls = await server.requests.count
        let maxConcurrent = await server.maxConcurrent
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(maxConcurrent, 1)
        try #"{"event":"assistant_message","usage":{"costTotal":7}}"#.write(to: url, atomically: true, encoding: .utf8)
        monitor.refresh()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(monitor.metrics.observedLocalUSD, 7)
        let unchangedCalls = await server.requests.count
        XCTAssertEqual(unchangedCalls, 2) // clock still inside the 300-second official interval
    }

    @MainActor
    func testMonitorManualRefreshRoutesToBothOpenAIMetrics() async throws {
        let server = FixtureCostsServer([page([["3"]]), page([["4"]])])
        let url = try telemetry()
        let suite = "UsageBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = UsageMonitor(
            registry: ProviderRegistry(providers: [CostTestProvider()]), defaults: defaults,
            jevCostReader: JevObservedCostReader(homeDirectory: url.deletingLastPathComponent()),
            openAICostReader: reader(server, url: url)
        )
        monitor.refresh(manual: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(monitor.openAICost.billedUSD, 3)
        try #"{"event":"assistant_message","usage":{"costTotal":8}}"#.write(to: url, atomically: true, encoding: .utf8)
        monitor.refresh(manual: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(monitor.openAICost.billedUSD, 4)
        XCTAssertEqual(monitor.openAICost.observedLocalUSD, 8)
    }
}

private struct CostTestProvider: UsageProvider {
    let id = "codex"
    let displayName = "Fixture"
    func connectionStatus() async -> ProviderConnectionStatus { .temporarilyUnavailable }
    func fetchUsage() async throws -> UsageSnapshot { throw ProviderError.temporarilyUnavailable }
}

private actor FixtureCostsServer {
    private var bodies: [String]
    private let status: Int
    private let delay: Duration
    private var concurrent = 0
    private(set) var maxConcurrent = 0
    private(set) var requests: [URLRequest] = []

    init(_ bodies: [String], status: Int = 200, delay: Duration = .zero) {
        self.bodies = bodies
        self.status = status
        self.delay = delay
    }

    func respond(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !bodies.isEmpty else { throw URLError(.cannotConnectToHost) }
        let body = bodies.removeFirst()
        concurrent += 1
        maxConcurrent = max(maxConcurrent, concurrent)
        defer { concurrent -= 1 }
        try await Task.sleep(for: delay)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
