import Foundation

/// Represents an error to be sent to RiviumTrace
/// Structure matches Android and Web SDKs for consistent backend processing
public struct RiviumTraceError {
    public let message: String
    public let stackTrace: String?
    /// Optional pre-resolved, structured stack trace. When set, the dashboard
    /// renders this as Sentry-style frames instead of the plain-text
    /// [stackTrace]. Native crashes populate this with a parsed PLCrashReport
    /// JSON; plain Swift errors leave it nil.
    public let resolvedStackTrace: String?
    public let platform: String
    public let environment: String
    public let releaseVersion: String?
    public let timestamp: Int64
    public let userAgent: String?
    public let breadcrumbs: [[String: Any]]
    public let extra: [String: Any]
    public let level: String
    public let tags: [String: String]
    public let url: String?

    public init(
        message: String,
        stackTrace: String? = nil,
        resolvedStackTrace: String? = nil,
        platform: String = "ios",
        environment: String = "production",
        releaseVersion: String? = nil,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        userAgent: String? = nil,
        breadcrumbs: [[String: Any]] = [],
        extra: [String: Any] = [:],
        level: String = MessageLevel.error.rawValue,
        tags: [String: String] = [:],
        url: String? = nil
    ) {
        self.message = message
        self.stackTrace = stackTrace
        self.resolvedStackTrace = resolvedStackTrace
        self.platform = platform
        self.environment = environment
        self.releaseVersion = releaseVersion
        self.timestamp = timestamp
        self.userAgent = userAgent
        self.breadcrumbs = breadcrumbs
        self.extra = extra
        self.level = level
        self.tags = tags
        self.url = url
    }

    /// Convert to dictionary for JSON serialization
    /// Same structure as Android and Web SDKs
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "message": message,
            "platform": platform,
            "environment": environment,
            "timestamp": timestamp,
            "level": level,
            "tags": tags,
            "breadcrumbs": breadcrumbs,
            "extra": extra
        ]

        if let stackTrace = stackTrace {
            dict["stack_trace"] = stackTrace
        }
        if let resolvedStackTrace = resolvedStackTrace {
            dict["resolved_stack_trace"] = resolvedStackTrace
        }
        if let releaseVersion = releaseVersion {
            dict["release_version"] = releaseVersion
        }
        if let userAgent = userAgent {
            dict["user_agent"] = userAgent
        }
        if let url = url {
            dict["url"] = url
        }

        return dict
    }

    // MARK: - Factory Methods

    /// Create from an Error
    public static func from(
        error: Error,
        message: String? = nil,
        environment: String = "production",
        releaseVersion: String? = nil,
        userAgent: String? = nil,
        breadcrumbs: [Breadcrumb] = [],
        extra: [String: Any] = [:],
        tags: [String: String] = [:]
    ) -> RiviumTraceError {
        let errorMessage = message ?? error.localizedDescription
        let rawSymbols = Thread.callStackSymbols
        let readableTrace = StackTraceParser.formatReadable(rawSymbols)

        var errorExtra = extra
        errorExtra["error_type"] = String(describing: type(of: error))
        errorExtra["error_description"] = error.localizedDescription

        if let nsError = error as NSError? {
            errorExtra["error_domain"] = nsError.domain
            errorExtra["error_code"] = nsError.code
            if !nsError.userInfo.isEmpty {
                errorExtra["error_user_info"] = nsError.userInfo.description
            }
        }

        // Binary images + raw addresses for server-side dSYM symbolication
        errorExtra["binary_images"] = BinaryImageCollector.collectAppImages().map { $0.toDictionary() }
        errorExtra["raw_addresses"] = StackTraceParser.captureRawAddresses()

        return RiviumTraceError(
            message: errorMessage,
            stackTrace: readableTrace,
            environment: environment,
            releaseVersion: releaseVersion,
            userAgent: userAgent,
            breadcrumbs: breadcrumbs.map { $0.toDictionary() },
            extra: errorExtra,
            tags: tags
        )
    }

    /// Create from an NSException
    public static func from(
        exception: NSException,
        message: String? = nil,
        environment: String = "production",
        releaseVersion: String? = nil,
        userAgent: String? = nil,
        breadcrumbs: [Breadcrumb] = [],
        extra: [String: Any] = [:],
        tags: [String: String] = [:]
    ) -> RiviumTraceError {
        let errorMessage = message ?? exception.reason ?? exception.name.rawValue
        let rawSymbols = exception.callStackSymbols
        let readableTrace = StackTraceParser.formatReadable(rawSymbols)

        var errorExtra = extra
        errorExtra["exception_name"] = exception.name.rawValue
        errorExtra["exception_reason"] = exception.reason

        // Binary images + raw addresses for server-side dSYM symbolication
        errorExtra["binary_images"] = BinaryImageCollector.collectAppImages().map { $0.toDictionary() }
        errorExtra["raw_addresses"] = StackTraceParser.captureRawAddresses(from: exception)

        return RiviumTraceError(
            message: errorMessage,
            stackTrace: readableTrace,
            environment: environment,
            releaseVersion: releaseVersion,
            userAgent: userAgent,
            breadcrumbs: breadcrumbs.map { $0.toDictionary() },
            extra: errorExtra,
            level: MessageLevel.fatal.rawValue,
            tags: tags
        )
    }

    /// Create a message (non-exception) error
    public static func message(
        _ message: String,
        level: MessageLevel = .info,
        environment: String = "production",
        releaseVersion: String? = nil,
        userAgent: String? = nil,
        breadcrumbs: [Breadcrumb] = [],
        extra: [String: Any] = [:],
        tags: [String: String] = [:]
    ) -> RiviumTraceError {
        return RiviumTraceError(
            message: message,
            stackTrace: nil,
            environment: environment,
            releaseVersion: releaseVersion,
            userAgent: userAgent,
            breadcrumbs: breadcrumbs.map { $0.toDictionary() },
            extra: extra,
            level: level.rawValue,
            tags: tags
        )
    }

    /// Create a native crash error
    public static func nativeCrash(
        crashInfo: String,
        signal: String? = nil,
        environment: String = "production",
        releaseVersion: String? = nil,
        userAgent: String? = nil,
        timeSinceCrashSeconds: Int64? = nil
    ) -> RiviumTraceError {
        var extra: [String: Any] = [
            "error_type": "native_crash",
            "crash_info": crashInfo
        ]
        if let signal = signal {
            extra["signal"] = signal
        }
        if let time = timeSinceCrashSeconds {
            extra["time_since_crash_seconds"] = time
        }

        // Binary images only — raw addresses are lost from previous session crash
        extra["binary_images"] = BinaryImageCollector.collectAppImages().map { $0.toDictionary() }

        return RiviumTraceError(
            message: "Native crash detected from previous session",
            stackTrace: "Native crash - No Swift stack trace available.\n\nCrash detected via crash marker file.\n\n\(crashInfo)",
            environment: environment,
            releaseVersion: releaseVersion,
            userAgent: userAgent,
            extra: extra,
            level: MessageLevel.fatal.rawValue
        )
    }

    /// Create an ANR (Application Not Responding) error
    public static func anr(
        stackTrace: String,
        environment: String = "production",
        releaseVersion: String? = nil,
        userAgent: String? = nil,
        anrDurationMs: Int64
    ) -> RiviumTraceError {
        var extra: [String: Any] = [
            "error_type": "anr",
            "anr_duration_ms": anrDurationMs
        ]

        // Binary images + raw addresses for server-side dSYM symbolication
        extra["binary_images"] = BinaryImageCollector.collectAppImages().map { $0.toDictionary() }
        extra["raw_addresses"] = StackTraceParser.captureRawAddresses()

        return RiviumTraceError(
            message: "Application Not Responding (ANR) - Main thread blocked for >\(anrDurationMs)ms",
            stackTrace: stackTrace,
            environment: environment,
            releaseVersion: releaseVersion,
            userAgent: userAgent,
            extra: extra,
            level: MessageLevel.error.rawValue
        )
    }
}
