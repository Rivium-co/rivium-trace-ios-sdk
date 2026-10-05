import XCTest
@testable import RiviumTrace
#if canImport(CrashReporter)
import CrashReporter
#endif

/// The event id: one per event, the same on every send of that event.
final class EventIdTests: XCTestCase {

    private let apiKey = "rv_live_event_id_test_key"
    private var directory: URL!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rivium-trace-event-id-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent(OfflineErrorStore.fileName)
        StubURLProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Helpers

    private func makeClient(store: OfflineErrorStore? = nil, enableOfflineStorage: Bool = true) -> RiviumTraceClient {
        let config = RiviumTraceConfig(
            apiKey: apiKey,
            httpTimeout: 5,
            enableOfflineStorage: enableOfflineStorage,
            apiUrl: "https://trace.test.invalid"
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        return RiviumTraceClient(
            config: config,
            sessionConfiguration: sessionConfiguration,
            offlineStore: store ?? OfflineErrorStore(fileURL: fileURL)
        )
    }

    private func send(_ error: RiviumTraceError, with client: RiviumTraceClient) {
        let done = expectation(description: "send")
        client.sendError(error) { _ in done.fulfill() }
        wait(for: [done], timeout: 10)
    }

    private func flush(_ client: RiviumTraceClient) {
        let done = expectation(description: "resend pass")
        client.flushOfflineErrors { done.fulfill() }
        wait(for: [done], timeout: 10)
    }

    private func launch(_ source: PendingCrashReportSource, _ client: RiviumTraceClient) -> PendingCrashReportOutcome? {
        let done = expectation(description: "pending crash report handled")
        var outcome: PendingCrashReportOutcome?
        PendingCrashReportSender(source: source, client: client).sendPendingReport(
            environment: "test",
            releaseVersion: "1.0",
            userAgent: "test-agent"
        ) { result in
            outcome = result
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return outcome
    }

    /// The top-level `event_id` of a request body.
    private func eventId(in body: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        return object?["event_id"] as? String
    }

    private func matchesServerPattern(_ id: String) -> Bool {
        return id.range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil
    }

    private struct SampleError: Error {}

    // MARK: (a) Present and distinct

    func testEveryErrorHasItsOwnValidId() {
        let errors: [RiviumTraceError] = [
            RiviumTraceError(message: "plain"),
            RiviumTraceError(message: "plain"),
            RiviumTraceError.from(error: SampleError()),
            RiviumTraceError.from(error: SampleError()),
            RiviumTraceError.from(exception: NSException(name: .genericException, reason: "r", userInfo: nil)),
            RiviumTraceError.message("a message"),
            RiviumTraceError.nativeCrash(crashInfo: "info"),
            RiviumTraceError.anr(stackTrace: "main", anrDurationMs: 5000),
            RiviumTraceError.anr(stackTrace: "main", anrDurationMs: 5000)
        ]

        for error in errors {
            XCTAssertTrue(matchesServerPattern(error.eventId), error.eventId)
            XCTAssertEqual(error.eventId, error.eventId.lowercased())
            XCTAssertEqual(error.toDictionary()["event_id"] as? String, error.eventId)
        }
        XCTAssertEqual(Set(errors.map { $0.eventId }).count, errors.count)
    }

    func testIdDoesNotChangeBetweenSerialisations() {
        let error = RiviumTraceError(message: "same")
        XCTAssertEqual(error.toDictionary()["event_id"] as? String, error.toDictionary()["event_id"] as? String)
        XCTAssertEqual(
            RiviumTraceClient.payload(for: error)["event_id"] as? String,
            error.eventId
        )
    }

    func testIdGivenByTheCallerIsKeptWhenValidAndReplacedWhenNot() {
        XCTAssertEqual(RiviumTraceError(message: "m", eventId: "my_event-0001").eventId, "my_event-0001")

        let tooLong = String(repeating: "a", count: 65)
        for invalid in ["", "short", "has space in it", "slash/not/allowed", "ünïcödé-ïd-1", tooLong] {
            let error = RiviumTraceError(message: "m", eventId: invalid)
            XCTAssertNotEqual(error.eventId, invalid)
            XCTAssertTrue(matchesServerPattern(error.eventId), error.eventId)
        }

        XCTAssertTrue(RiviumTraceError.isValidEventId(String(repeating: "a", count: 8)))
        XCTAssertTrue(RiviumTraceError.isValidEventId(String(repeating: "a", count: 64)))
        XCTAssertFalse(RiviumTraceError.isValidEventId(String(repeating: "a", count: 7)))
    }

    func testPostedErrorCarriesTheIdAtTheTopLevel() throws {
        StubURLProtocol.reset(fallback: .status(201))
        let client = makeClient()
        let first = RiviumTraceError(message: "one", extra: ["k": "v"])
        let second = RiviumTraceError(message: "two")

        send(first, with: client)
        send(second, with: client)

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/errors", "/api/errors"])
        XCTAssertEqual(eventId(in: requests[0].body), first.eventId)
        XCTAssertEqual(eventId(in: requests[1].body), second.eventId)
        XCTAssertNotEqual(first.eventId, second.eventId)

        // The fields sent before are all still there.
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].body) as? [String: Any])
        for key in ["message", "platform", "environment", "timestamp", "level", "tags", "breadcrumbs", "extra"] {
            XCTAssertNotNil(body[key], key)
        }
    }

    func testSynchronousSendCarriesTheId() {
        StubURLProtocol.reset(fallback: .status(201))
        let error = RiviumTraceError(message: "uncaught")

        XCTAssertTrue(makeClient().sendErrorSync(error))

        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(eventId(in: StubURLProtocol.requests[0].body), error.eventId)
    }

    func testMessagesAreSentAsBefore() throws {
        StubURLProtocol.reset(fallback: .status(201))
        let done = expectation(description: "message")
        makeClient().sendMessage(RiviumTraceError.message("hello")) { _ in done.fulfill() }
        wait(for: [done], timeout: 10)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/messages")
        XCTAssertNil(eventId(in: request.body))
    }

    // MARK: (b) Stored and resent copy

    func testStoredAndResentCopyKeepsTheId() throws {
        // The server got the report but the answer never arrived.
        StubURLProtocol.reset(outcomes: [.failure(.timedOut)], fallback: .status(201))
        let store = OfflineErrorStore(fileURL: fileURL)
        let client = makeClient(store: store)
        let error = RiviumTraceError(message: "answer lost")

        send(error, with: client)

        let stored = store.snapshot()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(eventId(in: try XCTUnwrap(stored.first).body), error.eventId)

        // A later launch: new store and client over the same file.
        let laterStore = OfflineErrorStore(fileURL: fileURL)
        XCTAssertEqual(eventId(in: try XCTUnwrap(laterStore.snapshot().first).body), error.eventId)
        flush(makeClient(store: laterStore))

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(eventId(in: requests[0].body), error.eventId)
        XCTAssertEqual(eventId(in: requests[1].body), error.eventId)
        XCTAssertEqual(requests[1].body, requests[0].body, "The resent body is the first one, byte for byte")
        XCTAssertTrue(laterStore.snapshot().isEmpty)
    }

    func testIdSurvivesRepeatedResendAttempts() {
        StubURLProtocol.reset(
            outcomes: [.failure(.networkConnectionLost), .status(503), .status(429), .status(201)]
        )
        let store = OfflineErrorStore(fileURL: fileURL)
        let client = makeClient(store: store)
        let error = RiviumTraceError(message: "retried")

        send(error, with: client)
        flush(client)
        flush(client)
        flush(client)

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(Set(requests.map { eventId(in: $0.body) }), [error.eventId])
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testSynchronousSendStoresTheSameId() throws {
        StubURLProtocol.reset(fallback: .failure(.notConnectedToInternet))
        let store = OfflineErrorStore(fileURL: fileURL)
        let error = RiviumTraceError(message: "uncaught, offline")

        XCTAssertFalse(makeClient(store: store).sendErrorSync(error))

        XCTAssertEqual(eventId(in: try XCTUnwrap(store.snapshot().first).body), error.eventId)
    }

    // MARK: (c) Pending crash report

    func testCrashEventIdComesFromTheReportId() {
        let data = Data("report".utf8)
        let id = PendingCrashReport.eventId(reportUUID: "0F8FAD5B-D9CB-469F-A165-70867728950E", data: data)

        XCTAssertEqual(id, "0f8fad5b-d9cb-469f-a165-70867728950e")
        XCTAssertEqual(id, PendingCrashReport.eventId(reportUUID: "0F8FAD5B-D9CB-469F-A165-70867728950E", data: data))
        XCTAssertEqual(
            id,
            PendingCrashReport.eventId(reportUUID: "0F8FAD5B-D9CB-469F-A165-70867728950E", data: Data("other".utf8)),
            "The report id wins over the bytes"
        )
        XCTAssertNotEqual(
            id,
            PendingCrashReport.eventId(reportUUID: "1F8FAD5B-D9CB-469F-A165-70867728950E", data: data)
        )
    }

    func testCrashEventIdFallsBackToTheReportBytes() {
        let first = Data("crash report one".utf8)
        let second = Data("crash report two".utf8)

        for missing in [nil, "", "not valid!"] as [String?] {
            let id = PendingCrashReport.eventId(reportUUID: missing, data: first)
            XCTAssertTrue(matchesServerPattern(id), id)
            XCTAssertEqual(id, PendingCrashReport.eventId(reportUUID: nil, data: first))
            XCTAssertNotEqual(id, PendingCrashReport.eventId(reportUUID: nil, data: second))
        }
        // SHA-256("abc"), first 16 bytes.
        XCTAssertEqual(
            PendingCrashReport.eventId(reportUUID: nil, data: Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223"
        )
        XCTAssertTrue(matchesServerPattern(PendingCrashReport.eventId(reportUUID: nil, data: Data())))
    }

    #if canImport(CrashReporter)
    /// A real report from the crash reporter, read on two launches.
    func testRealCrashReportGetsTheSameIdOnEveryLaunch() throws {
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: [])
        let reporter = try XCTUnwrap(PLCrashReporter(configuration: config))
        let data = try reporter.generateLiveReportAndReturnError()

        let reportUUID = try XCTUnwrap(
            NativeCrashReporter.reportUUID(of: try PLCrashReport(data: data)),
            "The vendored crash reporter writes an id into every report"
        )

        let firstLaunch = try NativeCrashReporter.shared.pendingReport(
            from: data, environment: "test", releaseVersion: "1.0", userAgent: "agent"
        )
        let secondLaunch = try NativeCrashReporter.shared.pendingReport(
            from: data, environment: "test", releaseVersion: "1.1", userAgent: "other agent"
        )

        XCTAssertEqual(firstLaunch.error.eventId, reportUUID.lowercased())
        XCTAssertEqual(secondLaunch.error.eventId, firstLaunch.error.eventId)
        XCTAssertTrue(matchesServerPattern(firstLaunch.error.eventId))
        XCTAssertEqual(secondLaunch.id, firstLaunch.id)
        XCTAssertEqual(
            RiviumTraceClient.payload(for: firstLaunch.error)["event_id"] as? String,
            firstLaunch.error.eventId
        )
    }

    /// A report source that parses the raw report again on every launch, as
    /// the real one does, and never loses it.
    private final class ReparsingSource: PendingCrashReportSource, @unchecked Sendable {
        let data: Data
        init(data: Data) { self.data = data }

        func loadPendingCrashReport(
            environment: String,
            releaseVersion: String?,
            userAgent: String?
        ) -> PendingCrashReport? {
            return try? NativeCrashReporter.shared.pendingReport(
                from: data, environment: environment, releaseVersion: releaseVersion, userAgent: userAgent
            )
        }

        func purgePendingCrashReport() {}
    }

    func testCrashReportSentOnSeveralLaunchesKeepsOneId() throws {
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: [])
        let data = try XCTUnwrap(PLCrashReporter(configuration: config)).generateLiveReportAndReturnError()
        let source = ReparsingSource(data: data)

        // Offline storage off: sent directly on each launch until it is accepted.
        StubURLProtocol.reset(outcomes: [.failure(.timedOut), .status(503), .status(201)])
        for expected in [PendingCrashReportOutcome.stillPending, .stillPending, .delivered] {
            XCTAssertEqual(launch(source, makeClient(enableOfflineStorage: false)), expected)
        }

        // Offline storage on: stored, sent, and (purge lost) stored and sent again.
        for _ in 0..<2 {
            let client = makeClient(store: OfflineErrorStore(fileURL: fileURL))
            XCTAssertEqual(launch(source, client), .stored)
            flush(client)
        }

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 5)
        let ids = Set(requests.map { eventId(in: $0.body) })
        XCTAssertEqual(ids.count, 1)
        XCTAssertTrue(matchesServerPattern(try XCTUnwrap(ids.first ?? nil)))
    }
    #endif

    /// Without a real report: the id travels with the report through the
    /// sender, with and without the offline store.
    func testPendingCrashReportIdIsTheSameOnEveryAttempt() {
        let eventId = PendingCrashReport.eventId(reportUUID: nil, data: Data("raw crash report".utf8))
        let error = RiviumTraceError(message: "Native crash: SIGSEGV", level: "fatal", eventId: eventId)
        let source = FakeCrashReportSource(report: PendingCrashReport(id: "r1", error: error))

        StubURLProtocol.reset(outcomes: [.failure(.networkConnectionLost), .status(500), .status(201)])
        for _ in 0..<3 {
            _ = launch(source, makeClient(enableOfflineStorage: false))
        }

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(Set(requests.map { self.eventId(in: $0.body) }), [eventId])
        XCTAssertFalse(source.hasPendingReport)
    }
}
