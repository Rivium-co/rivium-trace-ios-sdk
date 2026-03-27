import Foundation

/// Helper class for tracking performance of custom operations
///
/// Usage:
/// ```swift
/// // Track a network request
/// let tracker = PerformanceTracker(operation: "GET /api/users")
/// // ... perform operation
/// tracker.finish(status: .ok)
///
/// // Track with automatic timing
/// PerformanceTracker.track("fetchUserProfile") {
///     await api.fetchProfile()
/// }
/// ```
public class PerformanceTracker: @unchecked Sendable {

    // MARK: - Properties

    private let operation: String
    private let operationType: String
    private let startTime: Date
    private var tags: [String: String]
    private var metadata: [String: Any]
    private var httpMethod: String?
    private var httpUrl: String?
    private var httpHost: String?

    // MARK: - Initialization

    /// Create a new performance tracker
    ///
    /// - Parameters:
    ///   - operation: Name of the operation being tracked (e.g., "GET /api/users")
    ///   - operationType: Type of operation ("http", "db", "custom")
    ///   - tags: Optional tags for categorization
    public init(
        operation: String,
        operationType: String = "custom",
        tags: [String: String] = [:]
    ) {
        self.operation = operation
        self.operationType = operationType
        self.startTime = Date()
        self.tags = tags
        self.metadata = [:]
    }

    /// Create a tracker for an HTTP request
    public static func forHttpRequest(
        method: String,
        url: String,
        host: String? = nil
    ) -> PerformanceTracker {
        let urlObj = URL(string: url)
        let path = urlObj?.path ?? url
        let tracker = PerformanceTracker(
            operation: "\(method) \(path)",
            operationType: "http"
        )
        tracker.httpMethod = method
        tracker.httpUrl = url
        tracker.httpHost = host ?? urlObj?.host
        return tracker
    }

    /// Create a tracker for a database query
    public static func forDbQuery(
        queryType: String,
        table: String? = nil
    ) -> PerformanceTracker {
        let operation = table != nil ? "\(queryType) \(table!)" : queryType
        return PerformanceTracker(operation: operation, operationType: "db")
    }

    // MARK: - Configuration

    /// Add a tag to the span
    public func setTag(_ key: String, value: String) {
        tags[key] = value
    }

    /// Add metadata to the span
    public func setMetadata(_ key: String, value: Any) {
        metadata[key] = value
    }

    /// Set HTTP-specific details
    public func setHttpDetails(method: String, url: String, host: String? = nil) {
        self.httpMethod = method
        self.httpUrl = url
        self.httpHost = host ?? URL(string: url)?.host
    }

    // MARK: - Completion

    /// Finish tracking and report the span
    ///
    /// - Parameters:
    ///   - status: Final status of the operation
    ///   - statusCode: HTTP status code (for HTTP operations)
    ///   - errorMessage: Error message if status is error
    public func finish(
        status: SpanStatus = .ok,
        statusCode: Int? = nil,
        errorMessage: String? = nil
    ) {
        let durationMs = Date().timeIntervalSince(startTime) * 1000

        let endTime = Date()
        let span = PerformanceSpan(
            operation: operation,
            operationType: operationType,
            traceId: PerformanceSpan.generateTraceId(),
            spanId: PerformanceSpan.generateSpanId(),
            parentSpanId: nil,
            httpMethod: httpMethod,
            httpUrl: httpUrl,
            httpStatusCode: statusCode,
            httpHost: httpHost,
            durationMs: durationMs,
            startTime: startTime,
            endTime: endTime,
            platform: "ios",
            environment: nil, // Will be filled by RiviumTrace
            releaseVersion: nil, // Will be filled by RiviumTrace
            status: status.rawValue,
            errorMessage: errorMessage,
            tags: tags,
            metadata: metadata
        )

        RiviumTrace.shared.reportPerformanceSpan(span, completion: nil)
    }

    /// Finish with error
    public func finishWithError(_ error: Error, statusCode: Int? = nil) {
        finish(
            status: .error,
            statusCode: statusCode,
            errorMessage: error.localizedDescription
        )
    }

    // MARK: - Static Helpers

    /// Track an operation with automatic timing
    ///
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - operationType: Type of operation
    ///   - block: The operation to perform
    /// - Returns: Result of the operation
    public static func track<T>(
        _ operation: String,
        operationType: String = "custom",
        block: () throws -> T
    ) rethrows -> T {
        let tracker = PerformanceTracker(operation: operation, operationType: operationType)

        do {
            let result = try block()
            tracker.finish(status: .ok)
            return result
        } catch {
            tracker.finishWithError(error)
            throw error
        }
    }

    /// Track an async operation with automatic timing
    @available(iOS 13.0, macOS 10.15, *)
    public static func trackAsync<T>(
        _ operation: String,
        operationType: String = "custom",
        block: () async throws -> T
    ) async rethrows -> T {
        let tracker = PerformanceTracker(operation: operation, operationType: operationType)

        do {
            let result = try await block()
            tracker.finish(status: .ok)
            return result
        } catch {
            tracker.finishWithError(error)
            throw error
        }
    }
}

// MARK: - SpanStatus

/// Status of a performance span
public enum SpanStatus: String {
    case ok = "ok"
    case error = "error"
    case timeout = "timeout"
    case cancelled = "cancelled"
}
