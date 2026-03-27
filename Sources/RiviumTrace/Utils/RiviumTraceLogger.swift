import Foundation
import os.log

/// Internal logger for RiviumTrace SDK
public class RiviumTraceLogger: @unchecked Sendable {
    public static let shared = RiviumTraceLogger()

    private let subsystem = "co.rivium.trace.sdk"
    private let category = "RiviumTrace"

    private var _logger: Any?

    private let legacyLog = OSLog(subsystem: "co.rivium.trace.sdk", category: "RiviumTrace")

    public var isDebugEnabled: Bool = false

    @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
    private var logger: Logger {
        if let existing = _logger as? Logger {
            return existing
        }
        let newLogger = Logger(subsystem: subsystem, category: category)
        _logger = newLogger
        return newLogger
    }

    private init() {}

    public func debug(_ message: String) {
        guard isDebugEnabled else { return }

        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            logger.debug("[\(self.category)] \(message)")
        } else {
            os_log("[%{public}@] %{public}@", log: legacyLog, type: .debug, category, message)
        }
    }

    public func info(_ message: String) {
        guard isDebugEnabled else { return }

        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            logger.info("[\(self.category)] \(message)")
        } else {
            os_log("[%{public}@] %{public}@", log: legacyLog, type: .info, category, message)
        }
    }

    public func warn(_ message: String) {
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            logger.warning("[\(self.category)] \(message)")
        } else {
            os_log("[%{public}@] %{public}@", log: legacyLog, type: .default, category, message)
        }
    }

    public func error(_ message: String) {
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            logger.error("[\(self.category)] \(message)")
        } else {
            os_log("[%{public}@] %{public}@", log: legacyLog, type: .error, category, message)
        }
    }
}

// Convenience global functions
internal func logDebug(_ message: String) {
    RiviumTraceLogger.shared.debug(message)
}

internal func logInfo(_ message: String) {
    RiviumTraceLogger.shared.info(message)
}

internal func logWarn(_ message: String) {
    RiviumTraceLogger.shared.warn(message)
}

internal func logError(_ message: String) {
    RiviumTraceLogger.shared.error(message)
}
