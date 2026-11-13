import Foundation
import Security

/// Release health: one session per app launch, and a new one when the app
/// comes back after `backgroundTimeout` in the background. Each session is
/// reported once as `ok` when it starts and once more as `crashed` when it
/// crashed: an uncaught exception at once, a native crash at the next launch.
/// Rivium Trace counts every session and crash once, so a report may be sent
/// again safely.
///
/// Sends only a random install id (made on the device, never a device id), a
/// random session id, the start time, the release, the environment, the
/// platform and the user id the app set. Reports that could not be sent are
/// kept on disk and sent later (at most `maxQueued`).
///
/// All state and file access live on one private serial queue; nothing here
/// blocks the caller except `markCrashed`, which runs while the process dies.
final class ReleaseHealth: @unchecked Sendable {

    /// Sends an encoded `{"sessions": [...]}` body; the completion gets the
    /// HTTP status, or `nil` when there was no answer.
    typealias Transport = (Data, @escaping (Int?) -> Void) -> Void

    static let fileName = "rivium_trace_release_health.json"
    static let maxQueued = 50
    static let maxBatch = 100
    static let defaultBackgroundTimeout: TimeInterval = 30 * 60

    struct Report: Codable, Equatable {
        let sid: String
        let did: String
        let status: String
        let started: String
        let release: String
        let environment: String
        let platform: String
        let userId: String?
    }

    struct Session: Codable, Equatable {
        let sid: String
        let started: String
        let release: String
        let environment: String
        let platform: String
        var crashed: Bool
    }

    struct State: Codable {
        var did: String?
        var current: Session?
        var queue: [Report]
    }

    private let platform: String
    private let environment: String
    private let release: String
    private let userId: () -> String?
    private let fileURL: URL?
    private let transport: Transport
    private let previousCrashAt: Date?
    private let clock: () -> Date
    private let backgroundTimeout: TimeInterval

    private let queue = DispatchQueue(label: "co.rivium.trace.release-health", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()

    // Only touched on `queue`.
    private var installId = ""
    private var current: Session?
    private var reports: [Report] = []
    private var backgroundSince: Date?
    private var started = false
    private var flushing = false
    private var flushWaiters: [() -> Void] = []

    // The id errors carry; read from any thread.
    private let idLock = NSLock()
    private var currentId: String

    /// - Parameters:
    ///   - fileURL: Where the state is kept; `nil` keeps it in memory only.
    ///   - previousCrashAt: When the previous run left a native crash
    ///     report, the time it was written; `nil` when there is none.
    init(
        platform: String,
        environment: String,
        release: String?,
        userId: @escaping () -> String?,
        fileURL: URL?,
        transport: @escaping Transport,
        previousCrashAt: Date?,
        clock: @escaping () -> Date = Date.init,
        backgroundTimeout: TimeInterval = ReleaseHealth.defaultBackgroundTimeout
    ) {
        self.platform = platform
        self.environment = environment
        self.release = release ?? ""
        self.userId = userId
        self.fileURL = fileURL
        self.transport = transport
        self.previousCrashAt = previousCrashAt
        self.clock = clock
        self.backgroundTimeout = backgroundTimeout
        self.currentId = Self.makeId()
        queue.setSpecific(key: queueKey, value: true)
    }

    /// The default file, next to the offline errors.
    static func defaultFileURL() -> URL? {
        return OfflineErrorStore.defaultDirectory()?.appendingPathComponent(fileName)
    }

    /// The current session's id (known from construction on).
    var sessionId: String {
        idLock.lock()
        defer { idLock.unlock() }
        return currentId
    }

    // MARK: - Events

    /// Starts the first session of this launch. Before that, reports the
    /// previous launch's session as crashed when a native crash report was
    /// written after it started.
    func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            load()
            if var previous = current, !previous.crashed,
               let crashAt = previousCrashAt,
               let since = Self.parse(previous.started),
               crashAt >= since {
                previous.crashed = true
                current = previous
                enqueue(previous, status: "crashed")
            }
            newSession(id: sessionId)
            save()
            flushOnQueue()
        }
    }

    /// The process is about to die of an uncaught exception: the current
    /// session crashed. Written to disk before this returns, then sent with a
    /// short wait.
    func markCrashed(wait: TimeInterval) {
        if DispatchQueue.getSpecific(key: queueKey) == true { return }
        let marked: Bool = queue.sync { [self] in
            guard started, var session = current, !session.crashed else { return false }
            session.crashed = true
            current = session
            enqueue(session, status: "crashed")
            save()
            return true
        }
        guard marked, wait > 0 else { return }
        let done = DispatchSemaphore(value: 0)
        flush { done.signal() }
        _ = done.wait(timeout: .now() + wait)
    }

    /// The app went to the background.
    func paused() {
        let now = clock()
        queue.async { [self] in backgroundSince = now }
    }

    /// The app came back: a new session after `backgroundTimeout` away;
    /// waiting reports are sent.
    func resumed() {
        let now = clock()
        queue.async { [self] in
            let since = backgroundSince
            backgroundSince = nil
            if started, let since = since, now.timeIntervalSince(since) >= backgroundTimeout {
                newSession(id: Self.makeId())
                save()
            }
            flushOnQueue()
        }
    }

    /// Sends the waiting reports; `completion` runs when that attempt is over.
    func flush(completion: (() -> Void)? = nil) {
        queue.async { [self] in
            if let completion = completion { flushWaiters.append(completion) }
            flushOnQueue()
        }
    }

    /// Blocks until the work queued so far is done (tests).
    func waitUntilIdle() {
        queue.sync {}
    }

    // MARK: - Queue only

    private func flushOnQueue() {
        guard !flushing else { return }
        guard !reports.isEmpty else {
            finishFlush()
            return
        }
        let batch = Array(reports.prefix(Self.maxBatch))
        let body: Data
        do {
            body = try JSONEncoder().encode(["sessions": batch])
        } catch {
            logDebug("Release health: reports could not be encoded, dropped")
            reports.removeAll()
            save()
            finishFlush()
            return
        }
        flushing = true
        transport(body) { [self] code in
            onQueue { self.handleAnswer(code, batch: batch) }
        }
    }

    private func handleAnswer(_ code: Int?, batch: [Report]) {
        flushing = false
        guard let code = code else {
            logDebug("Release health: reports kept for later (no answer)")
            finishFlush()
            return
        }
        let done = (200...299).contains(code) || [400, 401, 403, 413].contains(code)
        guard done else {
            logDebug("Release health: server answered \(code), reports kept")
            finishFlush()
            return
        }
        reports.removeAll { report in batch.contains { $0.sid == report.sid && $0.status == report.status } }
        save()
        if code >= 300 {
            logWarn("Release health reports refused (\(code)), dropped")
        }
        if code < 300 && !reports.isEmpty {
            flushOnQueue()
        } else {
            finishFlush()
        }
    }

    private func finishFlush() {
        let waiters = flushWaiters
        flushWaiters = []
        waiters.forEach { $0() }
    }

    private func onQueue(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            work()
        } else {
            queue.async(execute: work)
        }
    }

    private func newSession(id: String) {
        let session = Session(
            sid: id,
            started: Self.format(clock()),
            release: release,
            environment: environment,
            platform: platform,
            crashed: false
        )
        current = session
        idLock.lock()
        currentId = id
        idLock.unlock()
        enqueue(session, status: "ok")
    }

    private func enqueue(_ session: Session, status: String) {
        let uid = userId()
        reports.append(Report(
            sid: session.sid,
            did: installId,
            status: status,
            started: session.started,
            release: session.release,
            environment: session.environment,
            platform: session.platform,
            userId: (uid?.isEmpty ?? true) ? nil : uid
        ))
        if reports.count > Self.maxQueued {
            reports.removeFirst(reports.count - Self.maxQueued)
        }
    }

    private func load() {
        var did: String?
        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
            do {
                let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
                did = state.did
                current = state.current
                reports = Array(state.queue.suffix(Self.maxQueued))
            } catch {
                logDebug("Release health: stored state unreadable, starting fresh")
                current = nil
                reports = []
            }
        }
        if let did = did, Self.isValidId(did) {
            installId = did
        } else {
            installId = Self.makeId()
        }
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(State(did: installId, current: current, queue: reports))
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url, options: .atomic)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)
        } catch {
            logDebug("Release health: state not saved (\(error.localizedDescription))")
        }
    }

    // MARK: - Helpers

    /// 32 lowercase hex characters from the system's secure random source.
    static func makeId() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func isValidId(_ id: String) -> Bool {
        return id.count == 32 && id.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    static func format(_ date: Date) -> String {
        return formatter().string(from: date)
    }

    static func parse(_ text: String) -> Date? {
        return formatter().date(from: text)
    }
}
