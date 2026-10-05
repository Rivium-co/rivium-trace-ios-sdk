import XCTest
@testable import RiviumTrace

// MARK: - Test doubles

/// Stands in for the crash reporter: holds at most one report, like the real one.
final class FakeCrashReportSource: PendingCrashReportSource, @unchecked Sendable {

    private let lock = NSLock()
    private var report: PendingCrashReport?
    private var loads = 0
    private var purges = 0

    init(report: PendingCrashReport?) {
        self.report = report
    }

    var hasPendingReport: Bool {
        lock.lock()
        defer { lock.unlock() }
        return report != nil
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loads
    }

    var purgeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return purges
    }

    func loadPendingCrashReport(
        environment: String,
        releaseVersion: String?,
        userAgent: String?
    ) -> PendingCrashReport? {
        lock.lock()
        defer { lock.unlock() }
        loads += 1
        return report
    }

    func purgePendingCrashReport() {
        lock.lock()
        defer { lock.unlock() }
        purges += 1
        report = nil
    }
}

/// Accepts every request and never answers, like a network that hangs.
final class HangingURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var started = 0

    static func reset() {
        lock.lock()
        started = 0
        lock.unlock()
    }

    static var startedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.started += 1
        Self.lock.unlock()
    }

    override func stopLoading() {}
}

// MARK: - Pending crash report tests

final class PendingCrashReportTests: XCTestCase {

    private let apiKey = "rv_live_crash_test_key"
    private var directory: URL!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rivium-trace-crash-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent(OfflineErrorStore.fileName)
        StubURLProtocol.reset()
        HangingURLProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Helpers

    private func makeStore() -> OfflineErrorStore {
        return OfflineErrorStore(fileURL: fileURL)
    }

    /// A store whose file can never be written: its folder is a plain file.
    private func makeUnwritableStore() throws -> OfflineErrorStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let blocker = directory.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        return OfflineErrorStore(fileURL: blocker.appendingPathComponent(OfflineErrorStore.fileName))
    }

    private func makeClient(
        store: OfflineErrorStore,
        enableOfflineStorage: Bool,
        protocolClass: AnyClass = StubURLProtocol.self
    ) -> RiviumTraceClient {
        let config = RiviumTraceConfig(
            apiKey: apiKey,
            httpTimeout: 5,
            enableOfflineStorage: enableOfflineStorage,
            apiUrl: "https://trace.test.invalid"
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [protocolClass]
        return RiviumTraceClient(config: config, sessionConfiguration: sessionConfiguration, offlineStore: store)
    }

    private func makeCrashError() -> RiviumTraceError {
        return RiviumTraceError(
            message: "Native crash: SIGSEGV (SEGV_MAPERR)",
            stackTrace: "Thread 0 Crashed:\n0 App 0x0000000100000000 main + 0",
            resolvedStackTrace: "{\"format\":\"structured\"}",
            environment: "test",
            releaseVersion: "1.0",
            timestamp: 1_700_000_000_000,
            userAgent: "test-agent",
            extra: ["error_type": "native_crash", "signal": "SIGSEGV"],
            level: MessageLevel.fatal.rawValue
        )
    }

    private func makeSource(id: String = "report-1") -> FakeCrashReportSource {
        return FakeCrashReportSource(report: PendingCrashReport(id: id, error: makeCrashError()))
    }

    /// One launch: read the pending report, hand it over, wait for the outcome.
    @discardableResult
    private func launch(
        _ source: FakeCrashReportSource,
        _ client: RiviumTraceClient
    ) -> PendingCrashReportOutcome? {
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

    private func flush(_ client: RiviumTraceClient) {
        let done = expectation(description: "resend pass")
        client.flushOfflineErrors { done.fulfill() }
        wait(for: [done], timeout: 10)
    }

    private func fileExists() -> Bool {
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    private func json(_ data: Data) -> NSDictionary? {
        return (try? JSONSerialization.jsonObject(with: data)) as? NSDictionary
    }

    // MARK: Offline storage off: sent directly

    func testPurgedAfterServerAccepts() {
        StubURLProtocol.reset(fallback: .status(201))
        let source = makeSource()

        let outcome = launch(source, makeClient(store: makeStore(), enableOfflineStorage: false))

        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(source.purgeCount, 1)
        XCTAssertFalse(source.hasPendingReport)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertFalse(fileExists(), "Nothing may be written with offline storage off")
    }

    func testPurgedAfterServerRejectsForGood() {
        for status in [400, 401, 403, 404, 413, 422] {
            StubURLProtocol.reset(fallback: .status(status))
            let source = makeSource()

            let outcome = launch(source, makeClient(store: makeStore(), enableOfflineStorage: false))

            XCTAssertEqual(outcome, .rejected, "status \(status)")
            XCTAssertEqual(source.purgeCount, 1, "status \(status)")
            XCTAssertEqual(StubURLProtocol.requests.count, 1, "status \(status)")
        }
    }

    func testNotPurgedAfterRetryableStatus() {
        for status in [408, 429, 500, 502, 503] {
            StubURLProtocol.reset(fallback: .status(status))
            let source = makeSource()

            let outcome = launch(source, makeClient(store: makeStore(), enableOfflineStorage: false))

            XCTAssertEqual(outcome, .stillPending, "status \(status)")
            XCTAssertEqual(source.purgeCount, 0, "status \(status)")
            XCTAssertTrue(source.hasPendingReport, "status \(status)")
        }
        XCTAssertFalse(fileExists(), "Nothing may be written with offline storage off")
    }

    func testNotPurgedAfterNetworkFailure() {
        let codes: [URLError.Code] = [.notConnectedToInternet, .timedOut, .cannotConnectToHost, .networkConnectionLost]
        for code in codes {
            StubURLProtocol.reset(fallback: .failure(code))
            let source = makeSource()

            let outcome = launch(source, makeClient(store: makeStore(), enableOfflineStorage: false))

            XCTAssertEqual(outcome, .stillPending, "\(code)")
            XCTAssertEqual(source.purgeCount, 0, "\(code)")
            XCTAssertTrue(source.hasPendingReport, "\(code)")
        }
        XCTAssertFalse(fileExists(), "Nothing may be written with offline storage off")
    }

    func testPendingReportIsDeliveredOnceOnALaterLaunch() {
        StubURLProtocol.reset(outcomes: [.failure(.cannotConnectToHost), .status(500), .status(201)])
        let source = makeSource()
        let store = makeStore()

        XCTAssertEqual(launch(source, makeClient(store: store, enableOfflineStorage: false)), .stillPending)
        XCTAssertEqual(launch(source, makeClient(store: store, enableOfflineStorage: false)), .stillPending)
        XCTAssertEqual(launch(source, makeClient(store: store, enableOfflineStorage: false)), .delivered)
        // Nothing is left to send on the launch after that.
        XCTAssertNil(launch(source, makeClient(store: store, enableOfflineStorage: false)))

        XCTAssertEqual(StubURLProtocol.requests.count, 3)
        XCTAssertEqual(source.purgeCount, 1)
    }

    func testNotPurgedWhenTheClientIsShutDown() {
        let source = makeSource()
        let client = makeClient(store: makeStore(), enableOfflineStorage: false)
        client.shutdown()

        XCTAssertEqual(launch(source, client), .stillPending)
        XCTAssertEqual(source.purgeCount, 0)
        XCTAssertEqual(StubURLProtocol.requests.count, 0)
    }

    func testDoesNotWaitForAHangingNetwork() {
        let source = makeSource()
        let client = makeClient(
            store: makeStore(),
            enableOfflineStorage: false,
            protocolClass: HangingURLProtocol.self
        )
        let done = expectation(description: "outcome after shutdown")
        let lock = NSLock()
        var outcome: PendingCrashReportOutcome?

        let started = Date()
        PendingCrashReportSender(source: source, client: client).sendPendingReport(
            environment: "test",
            releaseVersion: nil,
            userAgent: nil
        ) { result in
            lock.lock()
            outcome = result
            lock.unlock()
            done.fulfill()
        }
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 1, "Handing the report over must not wait for the answer")

        // The request is under way and unanswered: the report must still be there.
        let deadline = Date().addingTimeInterval(5)
        while HangingURLProtocol.startedCount == 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(HangingURLProtocol.startedCount, 1)
        XCTAssertEqual(source.purgeCount, 0)
        XCTAssertTrue(source.hasPendingReport)

        // The app going away mid-request leaves it pending too.
        client.shutdown()
        wait(for: [done], timeout: 10)
        lock.lock()
        let finalOutcome = outcome
        lock.unlock()
        XCTAssertEqual(finalOutcome, .stillPending)
        XCTAssertEqual(source.purgeCount, 0)
    }

    // MARK: Offline storage on: moved to the store, sent from there

    func testPurgedOnceStoredAndSentByTheNextPass() {
        StubURLProtocol.reset(fallback: .status(201))
        let source = makeSource()
        let store = makeStore()
        let client = makeClient(store: store, enableOfflineStorage: true)

        let outcome = launch(source, client)

        XCTAssertEqual(outcome, .stored)
        XCTAssertEqual(source.purgeCount, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 0, "Storing does not touch the network")
        XCTAssertEqual(store.snapshot().count, 1)
        XCTAssertEqual(OfflineErrorStore(fileURL: fileURL).snapshot().count, 1, "The report must be on disk before the purge")

        flush(client)

        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testStoredReportSurvivesServerErrorsAndIsDeliveredOnce() {
        StubURLProtocol.reset(outcomes: [.status(500), .failure(.timedOut), .status(201)])
        let source = makeSource()
        let store = makeStore()

        // Launch 1: server error. Launch 2: network hangs. Launch 3: accepted.
        for expectedRemaining in [1, 1, 0] {
            let client = makeClient(store: store, enableOfflineStorage: true)
            launch(source, client)
            flush(client)
            XCTAssertEqual(store.snapshot().count, expectedRemaining)
        }
        // Launch 4: nothing left.
        let client = makeClient(store: store, enableOfflineStorage: true)
        XCTAssertNil(launch(source, client))
        flush(client)

        XCTAssertEqual(StubURLProtocol.requests.count, 3)
        XCTAssertEqual(source.purgeCount, 1)
    }

    func testReportStoredButNotYetPurgedIsNotQueuedTwice() {
        StubURLProtocol.reset(fallback: .status(201))
        let store = makeStore()
        let client = makeClient(store: store, enableOfflineStorage: true)

        // The process died between the write to the store and the purge, so
        // the next launch finds the same report again.
        XCTAssertEqual(launch(makeSource(id: "same"), client), .stored)
        let relaunchSource = makeSource(id: "same")
        XCTAssertEqual(launch(relaunchSource, client), .stored)

        XCTAssertEqual(relaunchSource.purgeCount, 1)
        XCTAssertEqual(store.snapshot().count, 1)

        flush(client)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testDifferentCrashesAreBothStored() {
        let store = makeStore()
        let client = makeClient(store: store, enableOfflineStorage: true)

        launch(makeSource(id: "first"), client)
        launch(makeSource(id: "second"), client)

        XCTAssertEqual(store.snapshot().count, 2)
    }

    func testFallsBackToDirectSendWhenTheStoreCannotBeWritten() throws {
        StubURLProtocol.reset(outcomes: [.status(503), .failure(.notConnectedToInternet), .status(201)])
        let store = try makeUnwritableStore()
        let source = makeSource()

        XCTAssertEqual(launch(source, makeClient(store: store, enableOfflineStorage: true)), .stillPending)
        XCTAssertEqual(launch(source, makeClient(store: store, enableOfflineStorage: true)), .stillPending)
        XCTAssertEqual(source.purgeCount, 0)
        XCTAssertTrue(source.hasPendingReport)
        XCTAssertTrue(store.snapshot().isEmpty, "A report that is not on disk must not be kept in memory either")

        XCTAssertEqual(launch(source, makeClient(store: store, enableOfflineStorage: true)), .delivered)
        XCTAssertEqual(source.purgeCount, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 3)
    }

    // MARK: No report

    func testNothingHappensWithoutAPendingReport() {
        let source = FakeCrashReportSource(report: nil)
        let store = makeStore()

        XCTAssertNil(launch(source, makeClient(store: store, enableOfflineStorage: true)))
        XCTAssertNil(launch(source, makeClient(store: store, enableOfflineStorage: false)))

        XCTAssertEqual(source.loadCount, 2)
        XCTAssertEqual(source.purgeCount, 0)
        XCTAssertEqual(StubURLProtocol.requests.count, 0)
        XCTAssertFalse(fileExists())
    }

    // MARK: Request shape

    func testCrashReportRequestMatchesAnOrdinaryErrorRequest() throws {
        StubURLProtocol.reset(fallback: .status(201))
        let error = makeCrashError()

        // Reference: the same error through the public send path.
        let referenceClient = makeClient(store: makeStore(), enableOfflineStorage: false)
        let sent = expectation(description: "reference send")
        referenceClient.sendError(error) { _ in sent.fulfill() }
        wait(for: [sent], timeout: 10)

        // Direct path (offline storage off).
        launch(
            FakeCrashReportSource(report: PendingCrashReport(id: "a", error: error)),
            makeClient(store: makeStore(), enableOfflineStorage: false)
        )

        // Through the offline store.
        let storingClient = makeClient(store: makeStore(), enableOfflineStorage: true)
        launch(FakeCrashReportSource(report: PendingCrashReport(id: "b", error: error)), storingClient)
        flush(storingClient)

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 3)
        let reference = try XCTUnwrap(requests.first)
        let referenceBody = try XCTUnwrap(json(reference.body))
        XCTAssertEqual(referenceBody["resolved_stack_trace"] as? String, "{\"format\":\"structured\"}")

        for request in requests.dropFirst() {
            XCTAssertEqual(request.url, reference.url)
            XCTAssertEqual(request.url?.path, "/api/errors")
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.headers["X-API-Key"], apiKey)
            XCTAssertEqual(request.headers["Content-Type"], reference.headers["Content-Type"])
            XCTAssertEqual(json(request.body), referenceBody)
        }
    }

    // MARK: Identifier

    func testIdentifierIsStableAndTellsReportsApart() {
        let first = Data("crash report one".utf8)
        let second = Data("crash report two".utf8)

        XCTAssertEqual(PendingCrashReport.identifier(for: first), PendingCrashReport.identifier(for: first))
        XCTAssertNotEqual(PendingCrashReport.identifier(for: first), PendingCrashReport.identifier(for: second))
        XCTAssertNotEqual(PendingCrashReport.identifier(for: Data()), PendingCrashReport.identifier(for: Data([0])))
    }

    func testOutcomesThatAllowPurge() {
        XCTAssertTrue(PendingCrashReportOutcome.delivered.allowsPurge)
        XCTAssertTrue(PendingCrashReportOutcome.rejected.allowsPurge)
        XCTAssertTrue(PendingCrashReportOutcome.stored.allowsPurge)
        XCTAssertTrue(PendingCrashReportOutcome.unsendable.allowsPurge)
        XCTAssertFalse(PendingCrashReportOutcome.stillPending.allowsPurge)
    }
}
