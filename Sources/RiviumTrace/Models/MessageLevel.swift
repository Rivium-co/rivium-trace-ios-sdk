import Foundation

/// Severity level for messages and errors
public enum MessageLevel: String, Codable {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    case fatal = "fatal"

    /// Create from string (case-insensitive)
    public static func from(_ string: String) -> MessageLevel {
        return MessageLevel(rawValue: string.lowercased()) ?? .info
    }
}
