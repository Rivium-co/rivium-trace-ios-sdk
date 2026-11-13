import XCTest
@testable import RiviumTrace

/// Answers each request from a script (status code, or nil for no answer) and
/// records the sessions sent.
private final class FakeTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Int?] = []
    var fallback: Int? = 202
    private(set) var batches: [[[String: Any]]] = []

    func script(_ answers: [Int?]) {
        lock.lock(); self.answers = answers; lock.unlock()
    }

    var sent: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return batches.flatMap { $0 }
    }

    func send(_ body: Data, _ completion: @escaping (Int?) -> Void) {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let sessions = json?["sessions"] as? [[String: Any]] ?? []
        lock.lock()
        batches.append(sessions)
        let answer = answers.isEmpty ? fallback : answers.removeFirst()
        lock.unlock()
        completion(answer)
    }
}

/// A clock the test moves by hand.
private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

final class ReleaseHealthTests: XCTestCase {

    private var directory: URL!
    private var fileURL: URL!
    private var transport: FakeTransport!
    private var clock: TestClock!
    private var userId: String?

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-health-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("state.json")
        transport = FakeTransport()
        clock = TestClock()
        userId = nil
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// One app launch: a new instance on the same file.
    private func launch(previousCrashAt: Date? = nil) -> ReleaseHealth {
        let transport = self.transport!
        let clock = self.clock!
        let health = ReleaseHealth(
            platform: "ios",
            environment: "test",
            release: "1.0.0",
            userId: { [weak self] in self?.userId },
            fileURL: fileURL,
            transport: { body, completion in transport.send(body, completion) },
            previousCrashAt: previousCrashAt,
            clock: { clock.now }
        )
        health.start()
        health.waitUntilIdle()
        return health
    }

    private func storedQueue() throws -> [ReleaseHealth.Report] {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ReleaseHealth.State.self, from: data).queue
    }

    private func statuses() -> [String] {
        return transport.sent.map { $0["status"] as? String ?? "?" }
    }

    // MARK: -

    func testFirstLaunchSendsOneOkSession() throws {
        userId = "user-1"
        let health = launch()

        let sent = transport.sent
        XCTAssertEqual(sent.count, 1)
        let session = try XCTUnwrap(sent.first)
        XCTAssertEqual(session["status"] as? String, "ok")
        XCTAssertEqual(session["sid"] as? String, health.sessionId)
        XCTAssertEqual(session["platform"] as? String, "ios")
        XCTAssertEqual(session["environment"] as? String, "test")
        XCTAssertEqual(session["release"] as? String, "1.0.0")
        XCTAssertEqual(session["userId"] as? String, "user-1")
        XCTAssertEqual(session["started"] as? String, "2027-01-15T08:00:00.000Z")
        let did = try XCTUnwrap(session["did"] as? String)
        XCTAssertTrue(ReleaseHealth.isValidId(did))
        XCTAssertTrue(ReleaseHealth.isValidId(health.sessionId))
        XCTAssertEqual(try storedQueue().count, 0)
    }

    func testNoUserIdIsLeftOut() {
        _ = launch()
        XCTAssertNil(transport.sent.first?["userId"])
    }

    func testInstallIdStaysTheSameAcrossLaunches() {
        let first = launch()
        clock.advance(60)
        let second = launch()
        let sent = transport.sent
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0]["did"] as? String, sent[1]["did"] as? String)
        XCTAssertNotEqual(first.sessionId, second.sessionId)
    }

    func testUncaughtCrashIsReportedOnce() {
        let health = launch()
        health.markCrashed(wait: 2)
        health.markCrashed(wait: 2)
        health.waitUntilIdle()
        XCTAssertEqual(statuses(), ["ok", "crashed"])
        XCTAssertEqual(transport.sent[1]["sid"] as? String, health.sessionId)

        // The next launch does not report it again, even with a crash report.
        clock.advance(10)
        _ = launch(previousCrashAt: clock.now.addingTimeInterval(-5))
        XCTAssertEqual(statuses(), ["ok", "crashed", "ok"])
    }

    func testUncaughtCrashIsKeptWhenItCannotBeSent() throws {
        let health = launch()
        transport.fallback = nil
        health.markCrashed(wait: 2)
        health.waitUntilIdle()
        XCTAssertEqual(try storedQueue().map { $0.status }, ["crashed"])
    }

    func testNativeCrashOfPreviousLaunchIsReportedAtNextLaunch() {
        let first = launch()
        clock.advance(120)
        let crashAt = clock.now
        clock.advance(30)
        let second = launch(previousCrashAt: crashAt)

        let sent = transport.sent
        XCTAssertEqual(statuses(), ["ok", "crashed", "ok"])
        XCTAssertEqual(sent[1]["sid"] as? String, first.sessionId)
        XCTAssertEqual(sent[1]["started"] as? String, sent[0]["started"] as? String)
        XCTAssertEqual(sent[2]["sid"] as? String, second.sessionId)
    }

    func testCrashReportOlderThanThePreviousSessionIsIgnored() {
        let crashAt = clock.now.addingTimeInterval(-60)
        _ = launch()
        clock.advance(30)
        _ = launch(previousCrashAt: crashAt)
        XCTAssertEqual(statuses(), ["ok", "ok"])
    }

    func testCleanRelaunchIsNotACrash() {
        _ = launch()
        clock.advance(30)
        _ = launch(previousCrashAt: nil)
        XCTAssertEqual(statuses(), ["ok", "ok"])
    }

    func testThirtyMinutesInBackgroundStartsANewSession() {
        let health = launch()
        let first = health.sessionId
        health.paused()
        clock.advance(30 * 60)
        health.resumed()
        health.waitUntilIdle()
        XCTAssertEqual(statuses(), ["ok", "ok"])
        XCTAssertNotEqual(health.sessionId, first)
        XCTAssertEqual(transport.sent[1]["sid"] as? String, health.sessionId)
    }

    func testShortBackgroundKeepsTheSession() {
        let health = launch()
        let first = health.sessionId
        health.paused()
        clock.advance(29 * 60)
        health.resumed()
        health.waitUntilIdle()
        XCTAssertEqual(statuses(), ["ok"])
        XCTAssertEqual(health.sessionId, first)
    }

    func testResumeWithoutPauseKeepsTheSession() {
        let health = launch()
        clock.advance(60 * 60)
        health.resumed()
        health.waitUntilIdle()
        XCTAssertEqual(statuses(), ["ok"])
    }

    func testOfflineReportsAreKeptAndSentLater() throws {
        transport.fallback = nil
        _ = launch()
        XCTAssertEqual(try storedQueue().map { $0.status }, ["ok"])

        transport.script([500])
        clock.advance(60)
        _ = launch()
        XCTAssertEqual(try storedQueue().count, 2, "kept on a server error")

        transport.script([404])
        clock.advance(60)
        let third = launch()
        XCTAssertEqual(try storedQueue().count, 3, "kept on 404")

        transport.fallback = 202
        third.flush()
        third.waitUntilIdle()
        XCTAssertEqual(try storedQueue().count, 0)
        XCTAssertEqual(transport.batches.last?.count, 3, "sent in one batch")
    }

    func testRefusedReportsAreDropped() throws {
        for code in [400, 401, 403, 413] {
            try? FileManager.default.removeItem(at: fileURL)
            transport.script([code])
            _ = launch()
            XCTAssertEqual(try storedQueue().count, 0, "dropped on \(code)")
        }
    }

    func testQueueKeepsAtMostFiftyNewest() throws {
        transport.fallback = nil
        let health = launch()
        for _ in 0..<60 {
            health.paused()
            clock.advance(31 * 60)
            health.resumed()
        }
        health.waitUntilIdle()
        let queue = try storedQueue()
        XCTAssertEqual(queue.count, ReleaseHealth.maxQueued)
        XCTAssertEqual(queue.last?.sid, health.sessionId)
    }

    func testCorruptStateStartsFresh() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: fileURL)
        _ = launch(previousCrashAt: clock.now)
        XCTAssertEqual(statuses(), ["ok"])
        XCTAssertTrue(ReleaseHealth.isValidId(transport.sent[0]["did"] as? String ?? ""))
        XCTAssertNoThrow(try storedQueue())
    }

    func testBadInstallIdIsReplaced() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"did":"DEVICE-ID","queue":[]}"#.utf8).write(to: fileURL)
        _ = launch()
        let did = transport.sent.first?["did"] as? String ?? ""
        XCTAssertTrue(ReleaseHealth.isValidId(did))
    }

    func testStartTwiceIsOneSession() {
        let health = launch()
        health.start()
        health.waitUntilIdle()
        XCTAssertEqual(statuses(), ["ok"])
    }

    // MARK: - Config

    func testReleaseHealthIsOnByDefault() {
        XCTAssertTrue(RiviumTraceConfig(apiKey: "rv_live_test").enableReleaseHealth)
        XCTAssertTrue(RiviumTraceConfigBuilder(apiKey: "rv_live_test").build().enableReleaseHealth)
    }

    func testReleaseHealthCanBeTurnedOff() {
        XCTAssertFalse(RiviumTraceConfig(apiKey: "rv_live_test", enableReleaseHealth: false).enableReleaseHealth)
        XCTAssertFalse(RiviumTraceConfigBuilder(apiKey: "rv_live_test").enableReleaseHealth(false).build().enableReleaseHealth)
    }
}
