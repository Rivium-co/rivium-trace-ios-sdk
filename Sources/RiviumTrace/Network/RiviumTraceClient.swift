import Foundation

/// HTTP client for RiviumTrace API
public class RiviumTraceClient: @unchecked Sendable {

    private let config: RiviumTraceConfig
    private let session: URLSession
    private let baseURL: String

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

    public init(config: RiviumTraceConfig) {
        self.config = config
        self.baseURL = config.apiUrl

        let configuration = URLSessionConfiguration.default
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
        let url = "\(baseURL)/api/errors"

        post(url: url, body: error.toDictionary()) { result in
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
        let url = "\(baseURL)/api/errors"

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        post(url: url, body: error.toDictionary()) { result in
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

        post(url: url, body: message.toDictionary()) { result in
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
        guard let url = URL(string: url) else {
            completion(.failure(RiviumTraceClientError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let sanitizedBody = Self.sanitizeForJSON(body)
            request.httpBody = try JSONSerialization.data(withJSONObject: sanitizedBody)
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
