import Foundation

/// HTTP client for RiviumTrace API
public class RiviumTraceClient: @unchecked Sendable {

    private let config: RiviumTraceConfig
    private let session: URLSession
    private let baseURL: String

    /// Disk store for errors that could not be sent; `nil` when
    /// `enableOfflineStorage` is off, so the disk is never touched.
    private let offlineStore: OfflineErrorStore?

    /// Guards `isShutDown` and task creation: creating a task on an
    /// invalidated session raises an exception.
    private let sessionLock = NSLock()
    private var isShutDown = false

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    public convenience init(config: RiviumTraceConfig) {
        self.init(config: config, sessionConfiguration: .default, offlineStore: .shared)
    }

    /// - Parameters:
    ///   - sessionConfiguration: Base configuration for the client's session.
    ///   - offlineStore: Store for unsent errors; ignored when the config
    ///     turns offline storage off.
    init(
        config: RiviumTraceConfig,
        sessionConfiguration configuration: URLSessionConfiguration,
        offlineStore: OfflineErrorStore
    ) {
        self.config = config
        self.baseURL = config.apiUrl
        self.offlineStore = config.enableOfflineStorage ? offlineStore : nil

        configuration.timeoutIntervalForRequest = config.httpTimeout
        configuration.timeoutIntervalForResource = config.httpTimeout * 2
        configuration.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "User-Agent": "RiviumTrace-SDK/\(RiviumTraceSDK.version) (ios)"
        ]

        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Error Reporting

    /// Send an error to RiviumTrace
    public func sendError(_ error: RiviumTraceError, completion: ((Result<Void, Error>) -> Void)? = nil) {
        postError(error, storeSynchronously: false) { result in
            switch result {
            case .success:
                logDebug("Error sent successfully")
                completion?(.success(()))
            case .failure(let error):
                logError("Failed to send error: \(error.localizedDescription)")
                completion?(.failure(error))
            }
        }
    }

    /// Send an error synchronously (for use in crash handlers)
    public func sendErrorSync(_ error: RiviumTraceError) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        // The caller may be about to terminate, so a report that cannot be
        // sent is written to the offline store before this returns.
        postError(error, storeSynchronously: true) { result in
            if case .success = result {
                success = true
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + config.httpTimeout)
        return success
    }

    /// Send a message to RiviumTrace
    public func sendMessage(_ message: RiviumTraceError, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let url = "\(baseURL)/api/messages"

        post(url: url, body: Self.payload(for: message)) { result in
            switch result {
            case .success:
                logDebug("Message sent successfully")
                completion?(.success(()))
            case .failure(let error):
                logError("Failed to send message: \(error.localizedDescription)")
                completion?(.failure(error))
            }
        }
    }

    // MARK: - Offline errors

    private var errorsURL: String {
        return "\(baseURL)/api/errors"
    }

    /// POST an error report. A report that fails with a network-level error
    /// is kept in the offline store (when enabled); a successful send is the
    /// cue to retry anything stored earlier.
    private func postError(
        _ error: RiviumTraceError,
        storeSynchronously: Bool,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let body: Data
        do {
            body = try Self.encodeBody(Self.payload(for: error))
        } catch {
            completion(.failure(error))
            return
        }

        let store = offlineStore
        send(url: errorsURL, body: body) { [weak self] result in
            switch result {
            case .success:
                completion(result)
                self?.flushOfflineErrors()
            case .failure(let failure):
                if let store = store, Self.isNetworkFailure(failure) {
                    store.add(body, synchronously: storeSynchronously)
                }
                completion(result)
            }
        }
    }

    /// Hand over the crash report of a previous session and report what
    /// became of it, so the caller knows whether its own copy may go.
    ///
    /// With offline storage on, the report is written to the offline store
    /// under `id` (a report already stored under that id is not added again)
    /// and sent by the next `flushOfflineErrors()`. Otherwise, or when the
    /// store cannot be written, it is sent directly.
    ///
    /// Writes a file when offline storage is on: not for the main thread.
    /// Never waits for the network; `completion` runs on a background queue
    /// unless the report was stored or cannot be encoded.
    func deliverCrashReport(
        _ error: RiviumTraceError,
        id: String,
        completion: @escaping (PendingCrashReportOutcome) -> Void
    ) {
        let body: Data
        do {
            body = try Self.encodeBody(Self.payload(for: error))
        } catch {
            completion(.unsendable)
            return
        }

        if let store = offlineStore, store.addAndWait(body, id: "crash-\(id)") {
            completion(.stored)
            return
        }

        send(url: errorsURL, body: body) { result in
            switch result {
            case .success:
                completion(.delivered)
            case .failure(RiviumTraceClientError.httpError(let status)) where Self.isFinalRejection(status):
                completion(.rejected)
            case .failure:
                completion(.stillPending)
            }
        }
    }

    /// True for an HTTP status that will not change on a retry: 4xx except
    /// 408 (request timeout) and 429 (too many requests).
    static func isFinalRejection(_ status: Int) -> Bool {
        return (400...499).contains(status) && status != 408 && status != 429
    }

    /// Try to send the errors kept in the offline store, oldest first.
    ///
    /// Returns immediately; the work happens off the calling thread. An entry
    /// is removed once the server answers 2xx or 4xx (a rejected report will
    /// never be accepted), kept on 408, 429 and 5xx (try again later), and
    /// the pass stops at the first network failure. Only one pass runs at a time.
    ///
    /// - Parameter completion: Called when the pass has ended, or right away
    ///   when there was nothing to do.
    func flushOfflineErrors(completion: (() -> Void)? = nil) {
        guard let store = offlineStore else {
            completion?()
            return
        }

        store.beginResend { [weak self] entries in
            guard let entries = entries else {
                completion?()
                return
            }
            guard let self = self else {
                store.endResend(completion)
                return
            }
            logInfo("Sending \(entries.count) stored offline errors")
            self.resend(entries[...], store: store, completion: completion)
        }
    }

    private func resend(
        _ remaining: ArraySlice<OfflineErrorStore.Entry>,
        store: OfflineErrorStore,
        completion: (() -> Void)?
    ) {
        guard let entry = remaining.first else {
            store.endResend(completion)
            return
        }

        send(url: errorsURL, body: entry.body) { [weak self] result in
            switch result {
            case .success:
                store.remove(id: entry.id)
                logDebug("Stored error sent successfully")
            case .failure(RiviumTraceClientError.httpError(let status)):
                if Self.isFinalRejection(status) {
                    store.remove(id: entry.id)
                    logWarn("Stored error rejected by server (\(status)), dropped")
                } else {
                    logDebug("Server answered \(status) for a stored error, will retry later")
                }
            case .failure:
                logDebug("Failed to send stored error, will retry later")
                store.endResend(completion)
                return
            }

            guard let self = self else {
                store.endResend(completion)
                return
            }
            self.resend(remaining.dropFirst(), store: store, completion: completion)
        }
    }

    /// True for failures of the connection itself (offline, timeout, host
    /// unreachable, connection dropped). An HTTP response is never one.
    static func isNetworkFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorTimedOut,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorSecureConnectionFailed,
             NSURLErrorCannotLoadFromNetwork,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive,
             NSURLErrorDataNotAllowed:
            return true
        default:
            return false
        }
    }

    // MARK: - Error context

    /// The JSON body for an error or message: `toDictionary()` plus the device,
    /// app and SDK context every event carries, whatever path built it
    /// (captureError, captureMessage, uncaught exception, native crash, ANR).
    /// Values the caller already put in `extra` win.
    static func payload(for error: RiviumTraceError) -> [String: Any] {
        var dict = error.toDictionary()
        var extra = dict["extra"] as? [String: Any] ?? [:]

        if extra["device_info"] == nil {
            extra["device_info"] = DeviceInfo.shared.deviceInfo
        }
        if extra["app_info"] == nil {
            let app = DeviceInfo.shared.appInfoDictionary
            if !app.isEmpty { extra["app_info"] = app }
        }
        var sdk = extra["_sdk"] as? [String: Any] ?? [:]
        if sdk["sdk_version"] == nil {
            sdk["sdk_version"] = RiviumTraceSDK.version
        }
        extra["_sdk"] = sdk

        dict["extra"] = extra
        return dict
    }

    // MARK: - Performance Monitoring

    /// Send a performance span to RiviumTrace APM
    public func sendPerformanceSpan(_ span: PerformanceSpan, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let url = "\(baseURL)/api/performance/spans"

        post(url: url, body: span.toDictionary()) { result in
            switch result {
            case .success:
                logDebug("Performance span sent: \(span.operation)")
                completion?(.success(()))
            case .failure(let error):
                logError("Failed to send performance span: \(error.localizedDescription)")
                completion?(.failure(error))
            }
        }
    }

    /// Send multiple performance spans in a batch
    public func sendPerformanceSpanBatch(_ spans: [PerformanceSpan], completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !spans.isEmpty else {
            completion?(.success(()))
            return
        }

        let url = "\(baseURL)/api/performance/spans/batch"
        let body: [String: Any] = [
            "spans": spans.map { $0.toDictionary() }
        ]

        post(url: url, body: body) { result in
            switch result {
            case .success:
                logDebug("Performance span batch sent: \(spans.count) spans")
                completion?(.success(()))
            case .failure(let error):
                logError("Failed to send performance span batch: \(error.localizedDescription)")
                completion?(.failure(error))
            }
        }
    }

    // MARK: - HTTP Methods

    private func get(url: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: url) else {
            completion(.failure(RiviumTraceClientError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(RiviumTraceClientError.invalidResponse))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(RiviumTraceClientError.httpError(httpResponse.statusCode)))
                return
            }

            completion(.success(data ?? Data()))
        }.resume()
    }

    private func post(url: String, body: [String: Any], completion: @escaping (Result<Data, Error>) -> Void) {
        guard URL(string: url) != nil else {
            completion(.failure(RiviumTraceClientError.invalidURL))
            return
        }

        let data: Data
        do {
            data = try Self.encodeBody(body)
        } catch {
            completion(.failure(error))
            return
        }

        send(url: url, body: data, completion: completion)
    }

    /// The request body for a payload, exactly as it goes on the wire.
    private static func encodeBody(_ body: [String: Any]) throws -> Data {
        let sanitizedBody = sanitizeForJSON(body)
        return try JSONSerialization.data(withJSONObject: sanitizedBody)
    }

    /// POST an already encoded JSON body with the current API key.
    private func send(url: String, body: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: url) else {
            completion(.failure(RiviumTraceClientError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = body

        sessionLock.lock()
        guard !isShutDown else {
            sessionLock.unlock()
            completion(.failure(URLError(.cancelled)))
            return
        }
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(RiviumTraceClientError.invalidResponse))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(RiviumTraceClientError.httpError(httpResponse.statusCode)))
                return
            }

            completion(.success(data ?? Data()))
        }
        sessionLock.unlock()
        task.resume()
    }

    /// Recursively sanitize a dictionary to ensure all values are JSON-serializable
    private static func sanitizeForJSON(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.mapValues { sanitizeForJSON($0) }
        case let array as [Any]:
            return array.map { sanitizeForJSON($0) }
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let int64 as Int64:
            return int64
        case let double as Double:
            return double
        case let float as Float:
            return float
        case let date as Date:
            return Int64(date.timeIntervalSince1970 * 1000)
        case is NSNull:
            return NSNull()
        default:
            return String(describing: value)
        }
    }

    private func getWithApiKey(url: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: url) else {
            completion(.failure(RiviumTraceClientError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(RiviumTraceClientError.invalidResponse))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(RiviumTraceClientError.httpError(httpResponse.statusCode)))
                return
            }

            completion(.success(data ?? Data()))
        }.resume()
    }

    private func postWithApiKey(url: String, body: [String: Any], completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: url) else {
            completion(.failure(RiviumTraceClientError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(RiviumTraceClientError.invalidResponse))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(RiviumTraceClientError.httpError(httpResponse.statusCode)))
                return
            }

            completion(.success(data ?? Data()))
        }.resume()
    }

    /// Shutdown the client
    public func shutdown() {
        sessionLock.lock()
        isShutDown = true
        sessionLock.unlock()
        session.invalidateAndCancel()
    }
}

/// Client errors
public enum RiviumTraceClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
