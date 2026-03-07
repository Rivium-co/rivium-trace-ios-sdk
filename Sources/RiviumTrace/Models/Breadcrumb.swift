import Foundation

/// Type of breadcrumb
public enum BreadcrumbType: String, Codable {
    case navigation = "navigation"
    case user = "user"
    case http = "http"
    case state = "state"
    case info = "info"
    case error = "error"
    case system = "system"

    /// Create from string (case-insensitive)
    public static func from(_ string: String) -> BreadcrumbType {
        return BreadcrumbType(rawValue: string.lowercased()) ?? .info
    }
}

/// Breadcrumb - represents a single event in the user's journey
public struct Breadcrumb: Codable {
    public let message: String
    public let type: BreadcrumbType
    public let timestamp: Date
    public let data: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case message, type, timestamp, data
    }

    public init(
        message: String,
        type: BreadcrumbType = .info,
        timestamp: Date = Date(),
        data: [String: Any] = [:]
    ) {
        self.message = message
        self.type = type
        self.timestamp = timestamp
        self.data = data.mapValues { AnyCodable($0) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        type = try container.decode(BreadcrumbType.self, forKey: .type)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .data) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(data, forKey: .data)
    }

    /// Convert to dictionary for JSON serialization
    public func toDictionary() -> [String: Any] {
        return [
            "message": message,
            "type": type.rawValue,
            "timestamp": Int64(timestamp.timeIntervalSince1970 * 1000),
            "data": data.mapValues { $0.value }
        ]
    }

    // MARK: - Factory Methods

    /// Create a navigation breadcrumb
    public static func navigation(from: String?, to: String) -> Breadcrumb {
        let message = from != nil ? "Navigation: \(from!) -> \(to)" : "Navigation: -> \(to)"
        return Breadcrumb(
            message: message,
            type: .navigation,
            data: ["from": from as Any, "to": to]
        )
    }

    /// Create a user action breadcrumb
    public static func user(_ action: String, data: [String: Any] = [:]) -> Breadcrumb {
        return Breadcrumb(message: action, type: .user, data: data)
    }

    /// Create an HTTP request breadcrumb
    public static func http(method: String, url: String, statusCode: Int? = nil, duration: TimeInterval? = nil) -> Breadcrumb {
        var message = "HTTP \(method) \(url)"
        if let code = statusCode {
            message += " (\(code))"
        }

        var breadcrumbData: [String: Any] = [
            "method": method,
            "url": url
        ]
        if let code = statusCode {
            breadcrumbData["status_code"] = code
        }
        if let dur = duration {
            breadcrumbData["duration_ms"] = Int(dur * 1000)
        }

        return Breadcrumb(message: message, type: .http, data: breadcrumbData)
    }

    /// Create a state change breadcrumb
    public static func state(_ message: String, data: [String: Any] = [:]) -> Breadcrumb {
        return Breadcrumb(message: message, type: .state, data: data)
    }

    /// Create a system breadcrumb
    public static func system(_ message: String, data: [String: Any] = [:]) -> Breadcrumb {
        return Breadcrumb(message: message, type: .system, data: data)
    }

    /// Create an error breadcrumb
    public static func error(_ message: String, data: [String: Any] = [:]) -> Breadcrumb {
        return Breadcrumb(message: message, type: .error, data: data)
    }
}
