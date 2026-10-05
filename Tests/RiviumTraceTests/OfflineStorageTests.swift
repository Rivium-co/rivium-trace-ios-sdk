import XCTest
@testable import RiviumTrace

// MARK: - Stubbed transport

/// Answers every request of a session from a queue of scripted outcomes
/// instead of the network, and records what was sent.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    enum Outcome {
        case status(Int)
        case failure(URLError.Code)
    }

    struct Recorded {
        let url: URL?
        let method: String?
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var outcomes: [Outcome] = []
    nonisolated(unsafe) private static var fallback: Outcome = .status(200)
    nonisolated(unsafe) private static var recorded: [Recorded] = []

    static func reset(outcomes: [Outcome] = [], fallback: Outcome = .status(200)) {
        lock.lock()
        self.outcomes = outcomes
        self.fallback = fallback
        self.recorded = []
        lock.unlock()
    }

    static var requests: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private static func next(recording request: Recorded) -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        return outcomes.isEmpty ? fallback : outcomes.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        let outcome = Self.next(recording: Recorded(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request)
        ))

        switch outcome {
        case .status(let code):
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"),
                statusCode: code,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    /// Inside a URLProtocol the body arrives as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Offline storage tests

final class OfflineStorageTests: XCTestCase {

    private let apiKey = "rv_live_offline_test_key"
    private var directory: URL!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        // A directory that does not exist yet, so tests can tell whether the
        // disk was touched at all.
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rivium-trace-offline-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent(OfflineErrorStore.fileName)
        StubURLProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Helpers

    private func makeStore(maxEntries: Int = OfflineErrorStore.defaultMaxEntries) -> OfflineErrorStore {
        return OfflineErrorStore(fileURL: fileURL, maxEntries: maxEntries)
    }

    private func makeClient(
        store: OfflineErrorStore,
        enableOfflineStorage: Bool = true,
        apiKey: String? = nil
    ) -> RiviumTraceClient {
        let config = RiviumTraceConfig(
            apiKey: apiKey ?? self.apiKey,
            httpTimeout: 5,
            enableOfflineStorage: enableOfflineStorage,
            apiUrl: "https://trace.test.invalid"
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        return RiviumTraceClient(config: config, sessionConfiguration: sessionConfiguration, offlineStore: store)
    }

    private func makeError(_ message: String) -> RiviumTraceError {
        return RiviumTraceError(message: message, stackTrace: "frame 0", environment: "test")
    }

    /// Send one error and wait for the client's completion.
    @discardableResult
    private func send(_ message: String, with client: RiviumTraceClient) -> Bool {
        let done = expectation(description: "send \(message)")
        var succeeded = false
        client.sendError(makeError(message)) { result in
            if case .success = result { succeeded = true }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return succeeded
    }

    /// Run one resend pass and wait until it has ended.
    private func flush(_ client: RiviumTraceClient) {
        let done = expectation(description: "resend pass")
        client.flushOfflineErrors { done.fulfill() }
        wait(for: [done], timeout: 10)
    }

    private func body(_ index: Int) -> Data {
        return Data("{\"message\":\"stored \(index)\"}".utf8)
    }

    private func messages(in store: OfflineErrorStore) -> [String] {
        return store.snapshot().compactMap { entry in
            (try? JSONSerialization.jsonObject(with: entry.body) as? [String: Any])?["message"] as? String
        }
    }

    private func fileExists() -> Bool {
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: Storing

    func testErrorIsStoredOnNetworkFailure() throws {
        StubURLProtocol.reset(fallback: .failure(.notConnectedToInternet))
        let store = makeStore()
        let client = makeClient(store: store)

        XCTAssertFalse(send("offline error", with: client))

        let entries = store.snapshot()
        XCTAssertEqual(entries.count, 1)

        // What is stored is the body of the request that failed.
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.path, "/api/errors")
        XCTAssertEqual(entries.first?.body, requests.first?.body)
        XCTAssertEqual(messages(in: store), ["offline error"])

        // The API key never reaches the disk.
        let fileText = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(fileText.contains(apiKey))
        XCTAssertFalse(fileText.contains("X-API-Key"))
    }

    func testEveryNetworkLevelFailureIsStored() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .timedOut, .networkConnectionLost,
            .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed
        ]
        let store = makeStore()
        let client = makeClient(store: store)

        for code in codes {
            StubURLProtocol.reset(fallback: .failure(code))
            send("failure \(code.rawValue)", with: client)
        }

        XCTAssertEqual(store.snapshot().count, codes.count)
    }

    func testErrorIsNotStoredOnHttpErrorResponse() {
        let store = makeStore()
        let client = makeClient(store: store)

        for status in [400, 401, 404, 429, 500, 503] {
            StubURLProtocol.reset(fallback: .status(status))
            XCTAssertFalse(send("http \(status)", with: client))
        }

        XCTAssertTrue(store.snapshot().isEmpty)
        XCTAssertFalse(fileExists())
    }

    func testNonNetworkFailureIsNotStored() {
        StubURLProtocol.reset(fallback: .failure(.cancelled))
        let store = makeStore()
        let client = makeClient(store: store)

        XCTAssertFalse(send("cancelled", with: client))

        XCTAssertTrue(store.snapshot().isEmpty)
        XCTAssertFalse(fileExists())
    }

    func testSuccessfulSendStoresNothing() {
        let store = makeStore()
        let client = makeClient(store: store)

        XCTAssertTrue(send("fine", with: client))
        flush(client)

        XCTAssertTrue(store.snapshot().isEmpty)
        XCTAssertFalse(fileExists())
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testMessagesAreNotStored() {
        StubURLProtocol.reset(fallback: .failure(.notConnectedToInternet))
        let store = makeStore()
        let client = makeClient(store: store)

        let done = expectation(description: "message")
        client.sendMessage(makeError("a message")) { _ in done.fulfill() }
        wait(for: [done], timeout: 10)

        XCTAssertTrue(store.snapshot().isEmpty)
        XCTAssertFalse(fileExists())
    }

    func testSynchronousSendStoresBeforeReturning() {
        StubURLProtocol.reset(fallback: .failure(.notConnectedToInternet))
        let store = makeStore()
        let client = makeClient(store: store)

        XCTAssertFalse(client.sendErrorSync(makeError("crash report")))

        // No waiting: the file must already be there.
        XCTAssertTrue(fileExists())
        XCTAssertEqual(messages(in: makeStore()), ["crash report"])
    }

    func testDisabledOptionStoresNothing() {
        StubURLProtocol.reset(fallback: .failure(.notConnectedToInternet))
        let store = makeStore()
        let client = makeClient(store: store, enableOfflineStorage: false)

        XCTAssertFalse(send("offline but disabled", with: client))
        XCTAssertFalse(client.sendErrorSync(makeError("offline but disabled, sync")))
        flush(client)

        XCTAssertFalse(fileExists())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDisabledOptionDoesNotResendExistingFile() {
        let store = makeStore()
        store.add(body(0), synchronously: true)
        StubURLProtocol.reset()

        let client = makeClient(store: makeStore(), enableOfflineStorage: false)
        flush(client)
        XCTAssertTrue(send("live", with: client))

        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(messages(in: makeStore()), ["stored 0"])
    }

    // MARK: Cap

    func testCapOfOneHundredDropsOldest() {
        let store = makeStore()
        for index in 0..<105 {
            store.add(body(index))
        }

        let stored = messages(in: store)
        XCTAssertEqual(stored.count, 100)
        XCTAssertEqual(stored.first, "stored 5")
        XCTAssertEqual(stored.last, "stored 104")

        // The file holds the same hundred.
        XCTAssertEqual(messages(in: makeStore()), stored)
    }

    func testCapAppliesToErrorsStoredByTheClient() {
        StubURLProtocol.reset(fallback: .failure(.timedOut))
        let store = makeStore(maxEntries: 3)
        let client = makeClient(store: store)

        for index in 0..<5 {
            send("error \(index)", with: client)
        }

        XCTAssertEqual(messages(in: store), ["error 2", "error 3", "error 4"])
    }

    // MARK: Persistence

    func testStoredErrorsSurviveANewStore() {
        let first = makeStore()
        first.add(body(1))
        first.add(body(2))
        XCTAssertEqual(first.snapshot().count, 2)

        XCTAssertEqual(messages(in: makeStore()), ["stored 1", "stored 2"])
    }

    func testStoredBodyIsKeptByteForByte() {
        let original = Data("{\"b\":1.10,\"a\":\"\\u00e9 \\/ x\",\"n\":12345678901234567890}".utf8)
        makeStore().add(original, synchronously: true)

        XCTAssertEqual(makeStore().snapshot().first?.body, original)
    }

    func testCorruptFileIsTreatedAsEmptyAndOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ this is not json".utf8).write(to: fileURL)

        let store = makeStore()
        XCTAssertTrue(store.snapshot().isEmpty)

        store.add(body(7), synchronously: true)
        XCTAssertEqual(messages(in: store), ["stored 7"])

        // The file is valid again.
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [Any]
        XCTAssertEqual(parsed?.count, 1)
        XCTAssertEqual(messages(in: makeStore()), ["stored 7"])
    }

    func testFileWithUnexpectedShapeIsTreatedAsEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try Data("{\"not\":\"an array\"}".utf8).write(to: fileURL)
        XCTAssertTrue(makeStore().snapshot().isEmpty)

        // Entries that are not usable are skipped, the rest are kept.
        try Data("[1, {\"id\":\"x\"}, {\"id\":\"ok\",\"body\":\"{\\\"message\\\":\\\"stored 3\\\"}\"}]".utf8)
            .write(to: fileURL)
        XCTAssertEqual(messages(in: makeStore()), ["stored 3"])
    }

    func testCorruptFileDoesNotBreakSending() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: fileURL)

        let client = makeClient(store: makeStore())
        flush(client)
        XCTAssertTrue(send("after corrupt file", with: client))
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testStoredFileIsExcludedFromBackup() throws {
        makeStore().add(body(0), synchronously: true)

        let values = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    // MARK: Resending

    func testResendKeepsOn408And429() {
        let store = makeStore()
        for index in 0..<2 {
            store.add(body(index))
        }
        StubURLProtocol.reset(outcomes: [.status(408), .status(429)])
        let client = makeClient(store: store)

        flush(client)

        XCTAssertEqual(store.snapshot().count, 2)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testResendRemovesOn2xxAnd4xx() {
        let store = makeStore()
        for index in 0..<4 {
            store.add(body(index))
        }
        StubURLProtocol.reset(outcomes: [.status(200), .status(404), .status(201), .status(422)])
        let client = makeClient(store: store)

        flush(client)

        XCTAssertTrue(store.snapshot().isEmpty)
        XCTAssertTrue(makeStore().snapshot().isEmpty)

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 4)
        // Oldest first, the stored body unchanged, the current key and headers.
        XCTAssertEqual(requests.map { $0.body }, (0..<4).map { body($0) })
        for request in requests {
            XCTAssertEqual(request.url?.absoluteString, "https://trace.test.invalid/api/errors")
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.headers["X-API-Key"], apiKey)
            XCTAssertEqual(request.headers["Content-Type"], "application/json")
        }
    }

    func testResendUsesTheCurrentApiKey() {
        makeStore().add(body(0), synchronously: true)
        let client = makeClient(store: makeStore(), apiKey: "rv_live_rotated_key")

        flush(client)

        XCTAssertEqual(StubURLProtocol.requests.first?.headers["X-API-Key"], "rv_live_rotated_key")
    }

    func testResendKeepsOn5xxAndContinues() {
        let store = makeStore()
        for index in 0..<3 {
            store.add(body(index))
        }
        StubURLProtocol.reset(outcomes: [.status(500), .status(200), .status(503)])
        let client = makeClient(store: store)

        flush(client)

        XCTAssertEqual(StubURLProtocol.requests.count, 3)
        XCTAssertEqual(messages(in: store), ["stored 0", "stored 2"])
        XCTAssertEqual(messages(in: makeStore()), ["stored 0", "stored 2"])
    }

    func testResendStopsAtFirstNetworkFailureAndKeepsTheRest() {
        let store = makeStore()
        for index in 0..<4 {
            store.add(body(index))
        }
        StubURLProtocol.reset(outcomes: [.status(200), .failure(.networkConnectionLost)], fallback: .status(200))
        let client = makeClient(store: store)

        flush(client)

        // The third and fourth were never attempted.
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(messages(in: store), ["stored 1", "stored 2", "stored 3"])

        // A later pass picks them up, and a failed resend is not stored twice.
        flush(client)
        XCTAssertEqual(StubURLProtocol.requests.count, 5)
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testSuccessfulSendTriggersResend() {
        StubURLProtocol.reset(fallback: .failure(.notConnectedToInternet))
        let store = makeStore()
        let client = makeClient(store: store)
        send("while offline", with: client)
        XCTAssertEqual(store.snapshot().count, 1)

        // Back online: the next error goes through and takes the stored one along.
        StubURLProtocol.reset()
        XCTAssertTrue(send("back online", with: client))
        flush(client) // returns once the pass started by the send has ended

        let deadline = Date().addingTimeInterval(10)
        while !store.snapshot().isEmpty && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(store.snapshot().isEmpty)

        let sent = StubURLProtocol.requests.compactMap { request in
            (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any])?["message"] as? String
        }
        XCTAssertEqual(sent, ["back online", "while offline"])
    }

    func testOverlappingPassesSendEachStoredErrorOnce() {
        let store = makeStore()
        for index in 0..<10 {
            store.add(body(index))
        }
        let client = makeClient(store: store)
        let other = makeClient(store: store)

        let done = expectation(description: "all passes")
        done.expectedFulfillmentCount = 6
        for _ in 0..<3 {
            client.flushOfflineErrors { done.fulfill() }
            other.flushOfflineErrors { done.fulfill() }
        }
        wait(for: [done], timeout: 10)
        flush(client)

        XCTAssertTrue(store.snapshot().isEmpty)
        let bodies = StubURLProtocol.requests.map { $0.body }
        XCTAssertEqual(bodies.count, 10)
        XCTAssertEqual(Set(bodies).count, 10)
    }

    func testResendAfterShutdownDoesNotCrashAndKeepsErrors() {
        let store = makeStore()
        store.add(body(0))
        let client = makeClient(store: store)

        client.shutdown()
        flush(client)
        XCTAssertFalse(send("after shutdown", with: client))

        XCTAssertEqual(StubURLProtocol.requests.count, 0)
        XCTAssertEqual(messages(in: store), ["stored 0"])

        // The pass was closed properly: another client can still run one.
        let next = makeClient(store: store)
        flush(next)
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testNetworkFailureClassification() {
        XCTAssertTrue(RiviumTraceClient.isNetworkFailure(URLError(.notConnectedToInternet)))
        XCTAssertTrue(RiviumTraceClient.isNetworkFailure(URLError(.timedOut)))
        XCTAssertTrue(RiviumTraceClient.isNetworkFailure(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        ))

        XCTAssertFalse(RiviumTraceClient.isNetworkFailure(URLError(.cancelled)))
        XCTAssertFalse(RiviumTraceClient.isNetworkFailure(URLError(.badURL)))
        XCTAssertFalse(RiviumTraceClient.isNetworkFailure(RiviumTraceClientError.httpError(500)))
        XCTAssertFalse(RiviumTraceClient.isNetworkFailure(RiviumTraceClientError.invalidResponse))
    }
}
