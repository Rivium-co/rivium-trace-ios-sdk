import Foundation

/// Represents a performance span for APM tracking
///
/// A span represents a unit of work or operation (HTTP request, DB query, etc.)
/// with timing information.
public struct PerformanceSpan {
    public let operation: String
    public let operationType: String
    public let traceId: String?
    public let spanId: String?
    public let parentSpanId: String?

    // HTTP-specific fields
    public let httpMethod: String?
    public let httpUrl: String?
    public let httpStatusCode: Int?
    public let httpHost: String?

    // Timing
    public let durationMs: Double
    public let startTime: Date
    public let endTime: Date

    // Context
    public let platform: String
    public let environment: String?
    public let releaseVersion: String?

    // Status
    public let status: String
    public let errorMessage: String?

    // Additional data
    public let tags: [String: String]
    public let metadata: [String: Any]

    // MARK: - Static Helpers

    /// Generate a random trace ID
    public static func generateTraceId() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32).lowercased()
    }

    /// Generate a random span ID
    public static func generateSpanId() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
    }

    // MARK: - Initializers

    /// Create a span from an HTTP request
    public static func fromHttpRequest(
        method: String,
        url: String,
        statusCode: Int?,
        durationMs: Double,
        startTime: Date,
        environment: String? = nil,
        releaseVersion: String? = nil,
        traceId: String? = nil,
        errorMessage: String? = nil,
        tags: [String: String] = [:]
    ) -> PerformanceSpan {
        // Extract host from URL
        let host: String? = URL(string: url)?.host

        // Determine status
        let status: String
        if let code = statusCode {
            status = code >= 400 ? "error" : "ok"
        } else {
            status = "error"
        }

        return PerformanceSpan(
            operation: "\(method) \(extractPath(from: url))",
            operationType: "http",
            traceId: traceId ?? generateTraceId(),
            spanId: generateSpanId(),
            parentSpanId: nil,
            httpMethod: method,
            httpUrl: url,
            httpStatusCode: statusCode,
            httpHost: host,
            durationMs: durationMs,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(durationMs / 1000.0),
            platform: "ios",
            environment: environment,
            releaseVersion: releaseVersion,
            status: status,
            errorMessage: errorMessage,
            tags: tags,
            metadata: [:]
        )
    }

    /// Create a span for a database query
    public static func forDbQuery(
        queryType: String,
        tableName: String,
        durationMs: Double,
        startTime: Date,
        rowsAffected: Int? = nil,
        environment: String? = nil,
        releaseVersion: String? = nil,
        errorMessage: String? = nil,
        tags: [String: String] = [:]
    ) -> PerformanceSpan {
        var mergedTags = tags
        mergedTags["db_table"] = tableName
        mergedTags["query_type"] = queryType
        if let rows = rowsAffected {
            mergedTags["rows_affected"] = String(rows)
        }

        return PerformanceSpan(
            operation: "\(queryType) \(tableName)",
            operationType: "db",
            traceId: generateTraceId(),
            spanId: generateSpanId(),
            parentSpanId: nil,
            httpMethod: nil,
            httpUrl: nil,
            httpStatusCode: nil,
            httpHost: nil,
            durationMs: durationMs,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(durationMs / 1000.0),
            platform: "ios",
            environment: environment,
            releaseVersion: releaseVersion,
            status: errorMessage != nil ? "error" : "ok",
            errorMessage: errorMessage,
            tags: mergedTags,
            metadata: [:]
        )
    }

    /// Create a custom performance span
    public static func custom(
        operation: String,
        durationMs: Double,
        startTime: Date,
        operationType: String = "custom",
        status: String = "ok",
        environment: String? = nil,
        releaseVersion: String? = nil,
        errorMessage: String? = nil,
        tags: [String: String] = [:]
    ) -> PerformanceSpan {
        return PerformanceSpan(
            operation: operation,
            operationType: operationType,
            traceId: generateTraceId(),
            spanId: generateSpanId(),
            parentSpanId: nil,
            httpMethod: nil,
            httpUrl: nil,
            httpStatusCode: nil,
            httpHost: nil,
            durationMs: durationMs,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(durationMs / 1000.0),
            platform: "ios",
            environment: environment,
            releaseVersion: releaseVersion,
            status: status,
            errorMessage: errorMessage,
            tags: tags,
            metadata: [:]
        )
    }

    private static func extractPath(from url: String) -> String {
        guard let urlObj = URL(string: url) else {
            return String(url.prefix(50))
        }
        let path = urlObj.path.isEmpty ? "/" : urlObj.path
        return path.count > 50 ? String(path.prefix(50)) + "..." : path
    }

    // MARK: - Serialization

    /// Convert to dictionary for JSON serialization
    public func toDictionary() -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var dict: [String: Any] = [
            "operation": operation,
            "operation_type": operationType,
            "duration_ms": durationMs,
            "start_time": dateFormatter.string(from: startTime),
            "end_time": dateFormatter.string(from: endTime),
            "platform": platform,
            "status": status
        ]

        if let traceId = traceId { dict["trace_id"] = traceId }
        if let spanId = spanId { dict["span_id"] = spanId }
        if let parentSpanId = parentSpanId { dict["parent_span_id"] = parentSpanId }
        if let httpMethod = httpMethod { dict["http_method"] = httpMethod }
        if let httpUrl = httpUrl { dict["http_url"] = httpUrl }
        if let httpStatusCode = httpStatusCode { dict["http_status_code"] = httpStatusCode }
        if let httpHost = httpHost { dict["http_host"] = httpHost }
        if let environment = environment { dict["environment"] = environment }
        if let releaseVersion = releaseVersion { dict["release_version"] = releaseVersion }
        if let errorMessage = errorMessage { dict["error_message"] = errorMessage }
        if !tags.isEmpty { dict["tags"] = tags }
        if !metadata.isEmpty { dict["metadata"] = metadata }

        return dict
    }
}
