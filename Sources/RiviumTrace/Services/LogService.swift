import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Service for batching and sending logs to RiviumTrace
///
/// Features (matching Better Stack/Logtail):
/// - Lazy timer: only runs when buffer has logs
/// - Exponential backoff: retries with increasing delays (1s, 2s, 4s, 8s...)
/// - Max buffer size: drops oldest logs when buffer exceeds limit
/// - Lifecycle hooks: flushes on app background
public class LogService: @unchecked Sendable {
    // MARK: - Properties

    private let apiKey: String
    private let sourceId: String?
    private let sourceName: String?
    private let platform: String
    private let environment: String
    private let release: String?
    private let batchSize: Int
    private let flushInterval: TimeInterval
    private let maxBufferSize: Int

    private var buffer: [LogEntry] = []
    private var flushTimer: Timer?
    private var isFlushing = false
    private var retryAttempt = 0
    private var isAppActive = true
    private let queue = DispatchQueue(label: "co.rivium.trace.logservice", qos: .utility)
    private let session: URLSession

    private let apiEndpoint: String

    // Exponential backoff constants
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 60.0
    private let maxRetryAttempts = 10

    // MARK: - Initialization

    public init(
        apiKey: String,
        apiUrl: String = "https://trace.rivium.co",
        sourceId: String? = nil,
        sourceName: String? = nil,
        platform: String = "ios",
        environment: String = "production",
        release: String? = nil,
        batchSize: Int = 50,
        flushInterval: TimeInterval = 30.0,
        maxBufferSize: Int = 1000
    ) {
        self.apiKey = apiKey
        self.apiEndpoint = apiUrl
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.platform = platform
        self.environment = environment
        self.release = release
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.maxBufferSize = maxBufferSize

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        // Register for app lifecycle notifications
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }

    deinit {
        #if canImport(UIKit)
        NotificationCenter.default.removeObserver(self)
        #endif
        flushTimer?.invalidate()
        flush(completion: nil)
    }

    // MARK: - Lifecycle Hooks

    #if canImport(UIKit)
    @objc private func appDidEnterBackground() {
        isAppActive = false
        flush(completion: nil)
    }

    @objc private func appWillEnterForeground() {
        isAppActive = true
        retryAttempt = 0
        if !buffer.isEmpty {
            scheduleFlush()
        }
    }
    #endif

    // MARK: - Exponential Backoff

    private func getRetryDelay() -> TimeInterval {
        let delay = baseRetryDelay * pow(2.0, Double(retryAttempt))
        return min(delay, maxRetryDelay)
    }

    // MARK: - Buffer Management

    private func enforceMaxBufferSize() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.buffer.count > self.maxBufferSize {
                let dropCount = self.buffer.count - self.maxBufferSize
                self.buffer.removeFirst(dropCount)
                logWarn("Buffer overflow: dropped \(dropCount) oldest logs")
            }
        }
    }

    // MARK: - Timer

    /// Schedule a one-shot flush timer (only if buffer has logs)
    private func scheduleFlush() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.flushTimer?.invalidate()

            // Don't schedule if app is inactive
            guard self.isAppActive else { return }

            // Only schedule if there are logs to send
            guard !self.buffer.isEmpty else { return }

            // Use exponential backoff delay if retrying, otherwise normal interval
            let delay = self.retryAttempt > 0 ? self.getRetryDelay() : self.flushInterval

            self.flushTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.flush(completion: nil)
            }
        }
    }

    /// Cancel the flush timer
    private func cancelFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.flushTimer?.invalidate()
            self?.flushTimer = nil
        }
    }

    // MARK: - Public Methods

    /// Add a log entry to the buffer
    public func add(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.buffer.append(entry)

            // Enforce max buffer size (drop oldest if exceeds limit)
            if self.buffer.count > self.maxBufferSize {
                let dropCount = self.buffer.count - self.maxBufferSize
                self.buffer.removeFirst(dropCount)
                logWarn("Buffer overflow: dropped \(dropCount) oldest logs")
            }

            if self.buffer.count >= self.batchSize {
                self.flush(completion: nil)
            } else if self.flushTimer == nil {
                // Schedule flush only if timer isn't already running
                self.scheduleFlush()
            }
        }
    }

    /// Add a log with convenience parameters
    public func log(
        _ message: String,
        level: LogLevel = .info,
        metadata: [String: Any]? = nil,
        userId: String? = nil
    ) {
        let entry = LogEntry(
            message: message,
            level: level,
            timestamp: Date(),
            metadata: metadata,
            userId: userId
        )
        add(entry)
    }

    /// Send a single log immediately (bypasses batching)
    public func sendImmediate(_ entry: LogEntry, completion: ((Bool) -> Void)? = nil) {
        var payload: [String: Any] = [
            "message": entry.message,
            "level": entry.level.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
            "platform": platform,
            "environment": environment,
            "sourceType": "sdk"
        ]

        if let release = release {
            payload["release"] = release
        }
        if let sourceId = sourceId {
            payload["sourceId"] = sourceId
        }
        if let sourceName = sourceName {
            payload["sourceName"] = sourceName
        }
        if let userId = entry.userId {
            payload["userId"] = userId
        }
        if let metadata = entry.metadata {
            payload["metadata"] = metadata.mapValues { $0.value }
        }

        sendRequest(endpoint: "/api/logs/ingest", payload: payload, completion: completion)
    }

    /// Flush all buffered logs to the server
    public func flush(completion: ((Bool) -> Void)?) {
        // Cancel timer since we're flushing now
        cancelFlushTimer()

        queue.async { [weak self] in
            guard let self = self else {
                completion?(false)
                return
            }

            guard !self.buffer.isEmpty, !self.isFlushing else {
                completion?(true)
                return
            }

            self.isFlushing = true
            let logsToSend = self.buffer
            self.buffer.removeAll()

            // If no sourceId, send individual logs
            guard let sourceId = self.sourceId else {
                let group = DispatchGroup()
                var allSucceeded = true

                for entry in logsToSend {
                    group.enter()
                    self.sendImmediate(entry) { success in
                        if !success { allSucceeded = false }
                        group.leave()
                    }
                }

                group.notify(queue: self.queue) {
                    self.isFlushing = false
                    completion?(allSucceeded)
                }
                return
            }

            // Batch send
            let formatter = ISO8601DateFormatter()
            var logs: [[String: Any]] = []

            for entry in logsToSend {
                var logDict: [String: Any] = [
                    "message": entry.message,
                    "level": entry.level.rawValue,
                    "timestamp": formatter.string(from: entry.timestamp),
                    "platform": self.platform,
                    "environment": self.environment
                ]

                if let release = self.release {
                    logDict["release"] = release
                }
                if let userId = entry.userId {
                    logDict["userId"] = userId
                }
                if let metadata = entry.metadata {
                    logDict["metadata"] = metadata.mapValues { $0.value }
                }

                logs.append(logDict)
            }

            var payload: [String: Any] = [
                "sourceId": sourceId,
                "sourceType": "sdk",
                "logs": logs
            ]

            if let sourceName = self.sourceName {
                payload["sourceName"] = sourceName
            }

            self.sendRequest(endpoint: "/api/logs/ingest/batch", payload: payload) { [weak self] success in
                self?.queue.async {
                    guard let self = self else { return }
                    if success {
                        self.retryAttempt = 0 // Reset on success
                    } else {
                        // Put logs back in buffer for retry
                        self.buffer.insert(contentsOf: logsToSend, at: 0)
                        // Enforce max buffer size after re-adding
                        if self.buffer.count > self.maxBufferSize {
                            let dropCount = self.buffer.count - self.maxBufferSize
                            self.buffer.removeFirst(dropCount)
                        }
                        // Increment retry attempt and schedule with backoff
                        if self.retryAttempt < self.maxRetryAttempts {
                            self.retryAttempt += 1
                            self.scheduleFlush()
                        } else {
                            logError("Max retry attempts reached, logs will be dropped")
                            self.retryAttempt = 0
                        }
                    }
                    self.isFlushing = false
                    completion?(success)
                }
            }
        }
    }

    /// Get the number of buffered logs
    public var bufferSize: Int {
        return queue.sync { buffer.count }
    }

    // MARK: - Private Methods

    private func sendRequest(endpoint: String, payload: [String: Any], completion: ((Bool) -> Void)?) {
        guard let url = URL(string: apiEndpoint + endpoint) else {
            completion?(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("RiviumTrace-SDK/\(RiviumTraceSDK.version) (ios)", forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            logError("Failed to serialize log payload: \(error)")
            completion?(false)
            return
        }

        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                logError("Failed to send logs: \(error.localizedDescription)")
                completion?(false)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion?(false)
                return
            }

            let success = httpResponse.statusCode >= 200 && httpResponse.statusCode < 300
            if success {
                logDebug("Logs sent successfully")
            } else {
                logWarn("Failed to send logs: HTTP \(httpResponse.statusCode)")
            }
            completion?(success)
        }
        task.resume()
    }
}
