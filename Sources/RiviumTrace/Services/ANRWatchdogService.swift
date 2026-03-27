import Foundation

/// ANR (Application Not Responding) Watchdog Service
/// Detects main thread hangs that could cause the app to appear frozen
public class ANRWatchdogService: @unchecked Sendable {

    /// Shared instance
    public static let shared = ANRWatchdogService()

    /// ANR timeout in milliseconds (default: 5000ms = 5 seconds)
    private var timeoutMs: Int64 = 5000

    /// Timer for monitoring main thread
    private var watchdogTimer: DispatchSourceTimer?

    /// Flag to track main thread responsiveness
    private var isMainThreadResponsive = true

    /// Last main thread response time
    private var lastResponseTime: Date = Date()

    /// Is the watchdog running
    private var isRunning = false

    /// Callback when ANR is detected
    private var anrCallback: ((String) -> Void)?

    /// Watchdog queue
    private let watchdogQueue = DispatchQueue(label: "co.rivium.trace.anrwatchdog", qos: .utility)

    private init() {}

    /// Start the ANR watchdog
    /// - Parameters:
    ///   - timeoutMs: ANR detection timeout in milliseconds (default: 5000)
    ///   - callback: Callback when ANR is detected with stack trace
    public func start(timeoutMs: Int64 = 5000, callback: @escaping (String) -> Void) {
        guard !isRunning else {
            logDebug("ANR Watchdog already running")
            return
        }

        self.timeoutMs = timeoutMs
        self.anrCallback = callback
        self.isMainThreadResponsive = true
        self.lastResponseTime = Date()
        self.isRunning = true

        // Create watchdog timer on background queue
        watchdogTimer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        watchdogTimer?.schedule(deadline: .now(), repeating: .milliseconds(Int(timeoutMs / 2)))

        watchdogTimer?.setEventHandler { [weak self] in
            self?.checkMainThread()
        }

        watchdogTimer?.resume()

        logDebug("ANR Watchdog started with timeout: \(timeoutMs)ms")
    }

    /// Stop the ANR watchdog
    public func stop() {
        guard isRunning else { return }

        watchdogTimer?.cancel()
        watchdogTimer = nil
        isRunning = false
        anrCallback = nil

        logDebug("ANR Watchdog stopped")
    }

    /// Check main thread responsiveness
    private func checkMainThread() {
        // Set flag to false before checking
        isMainThreadResponsive = false

        // Dispatch to main thread to check if it's responsive
        DispatchQueue.main.async { [weak self] in
            self?.isMainThreadResponsive = true
            self?.lastResponseTime = Date()
        }

        // Wait a short time to see if main thread responds
        watchdogQueue.asyncAfter(deadline: .now() + .milliseconds(Int(timeoutMs / 4))) { [weak self] in
            guard let self = self, self.isRunning else { return }

            if !self.isMainThreadResponsive {
                let timeSinceLastResponse = Date().timeIntervalSince(self.lastResponseTime)

                if timeSinceLastResponse * 1000 >= Double(self.timeoutMs) {
                    self.handleANRDetected()
                }
            }
        }
    }

    /// Handle ANR detection
    private func handleANRDetected() {
        logWarn("ANR detected - main thread blocked for >\(timeoutMs)ms")

        // Capture main thread stack trace
        let stackTrace = captureMainThreadStackTrace()

        // Add breadcrumb
        BreadcrumbService.shared.addSystem("ANR detected", data: [
            "duration_ms": timeoutMs,
            "stack_trace": stackTrace
        ])

        // Notify callback
        anrCallback?(stackTrace)
    }

    /// Capture main thread stack trace
    private func captureMainThreadStackTrace() -> String {
        let symbols = Thread.callStackSymbols
        return "Main Thread Stack Trace:\n" + StackTraceParser.formatReadable(symbols)
    }

    /// Check if watchdog is running
    public var isActive: Bool {
        return isRunning
    }
}
