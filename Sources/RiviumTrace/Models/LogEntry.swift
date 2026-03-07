import Foundation

/// Log level for RiviumTrace logging
public enum LogLevel: String, Codable {
    case trace = "trace"
    case debug = "debug"
    case info = "info"
    case warn = "warn"
    case error = "error"
    case fatal = "fatal"
}

/// A single log entry to be sent to RiviumTrace
public struct LogEntry: Codable {
    public let message: String
    public let level: LogLevel
    public let timestamp: Date
    public let metadata: [String: AnyCodable]?
    public let userId: String?

    public init(
        message: String,
        level: LogLevel = .info,
        timestamp: Date = Date(),
        metadata: [String: Any]? = nil,
        userId: String? = nil
    ) {
        self.message = message
        self.level = level
        self.timestamp = timestamp
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.userId = userId
    }

    enum CodingKeys: String, CodingKey {
        case message
        case level
        case timestamp
        case metadata
        case userId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        let levelString = try container.decode(String.self, forKey: .level)
        level = LogLevel(rawValue: levelString) ?? .info
        let timestampString = try container.decode(String.self, forKey: .timestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        timestamp = formatter.date(from: timestampString) ?? Date()
        metadata = try container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(level.rawValue, forKey: .level)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: timestamp), forKey: .timestamp)

        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encodeIfPresent(userId, forKey: .userId)
    }
}
