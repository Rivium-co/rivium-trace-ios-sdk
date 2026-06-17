import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// RiviumTrace iOS SDK
///
/// Error tracking SDK for iOS applications.
/// Supports iOS 12+, macOS 10.14+, tvOS 12+, watchOS 5+
///
/// Usage:
/// ```swift
/// // In AppDelegate.application(_:didFinishLaunchingWithOptions:)
/// let config = RiviumTraceConfigBuilder(apiKey: "your-api-key")
///     .environment("production")
///     .debug(false)
///     .build()
/// RiviumTrace.shared.initialize(config: config)
///
/// // Capture exceptions
/// RiviumTrace.shared.captureError(error)
///
/// // Capture messages
/// RiviumTrace.shared.captureMessage("User completed onboarding", level: .info)
///
/// // Add breadcrumbs
/// RiviumTrace.shared.addBreadcrumb("Button clicked", type: .user)
/// ```
public class RiviumTrace: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance
    public static let shared = RiviumTrace()

    // MARK: - Properties

    private var config: RiviumTraceConfig?
    private var client: RiviumTraceClient?

    private var isInitialized = false
    private var sessionId: String = UUID().uuidString
    private var userId: String?
    private var userAgent: String?

    private var extraContext: [String: Any] = [:]
    private var tags: [String: String] = [:]

    private var logService: LogService?
    private var previousExceptionHandler: NSExceptionHandler?

    private let queue = DispatchQueue(label: "co.rivium.trace.main")

    // MARK: - Initialization

    private init() {}

    /// Initialize RiviumTrace SDK
    ///
    /// - Parameter config: SDK configuration
    public func initialize(config: RiviumTraceConfig) {
        guard !isInitialized else {
            logWarn("RiviumTrace already initialized")
            return
        }

        self.config = config
        self.client = RiviumTraceClient(config: config)
        self.userAgent = DeviceInfo.shared.userAgent

        // Ensure the configured API host is never tracked as a performance span
        RiviumTraceURLProtocol.setApiUrl(config.apiUrl)

        // Set debug mode
        RiviumTraceLogger.shared.isDebugEnabled = config.debug

        logInfo("Initializing RiviumTrace SDK v\(RiviumTraceSDK.version)")
        logDebug("Config: API Key=\(String(config.apiKey.prefix(10)))..., env=\(config.environment)")

        guard config.enabled else {
            logInfo("RiviumTrace SDK is disabled")
            return
        }

        // Configure breadcrumbs
        BreadcrumbService.shared.setMaxBreadcrumbs(config.maxBreadcrumbs)

        // Setup uncaught exception handler
        if config.captureUncaughtExceptions {
            setupUncaughtExceptionHandler()
        }

        // Native crash capture (POSIX signals + Mach exceptions) via PLCrashReporter.
        // Step 1: drain any crash report left by the previous session.
        // Step 2: install handlers for this session.
        if config.captureSignalCrashes {
            sendPendingNativeCrashIfAny()
            NativeCrashReporter.shared.install()
        }

        // Setup ANR detection
        if config.captureAnr {
            setupAnrDetection()
        }

        // Setup app lifecycle observers
        setupAppLifecycleObservers()

        // Add system breadcrumb
        BreadcrumbService.shared.addSystem("RiviumTrace SDK initialized", data: [
            "sdk_version": RiviumTraceSDK.version,
            "environment": config.environment
        ])

        isInitialized = true
        logInfo("RiviumTrace SDK initialized successfully")
    }

    /// Initialize with simple API key string
    public func initialize(apiKey: String) {
        initialize(config: RiviumTraceConfig.simple(apiKey: apiKey))
    }

    /// Check if SDK is initialized
    public var isReady: Bool {
        return isInitialized
    }

    // MARK: - Error Capture

    /// Capture an error
    ///
    /// - Parameters:
    ///   - error: The error to capture
    ///   - message: Optional custom message
    ///   - extra: Additional context data
    ///   - tags: Tags for categorization
    ///   - completion: Callback with success status
    public func captureError(
        _ error: Error,
        message: String? = nil,
        extra: [String: Any] = [:],
        tags: [String: String] = [:],
        completion: ((Bool) -> Void)? = nil
    ) {
        guard ensureInitialized() else {
            completion?(false)
            return
        }

        guard let cfg = config else { return }

        // Apply sample rate
        if cfg.sampleRate < 1.0 && Double.random(in: 0...1) > cfg.sampleRate {
            logDebug("Error dropped due to sample rate")
            completion?(false)
            return
        }

        // Add error breadcrumb
        BreadcrumbService.shared.addError("Error: \(type(of: error))", data: [
            "description": error.localizedDescription
        ])

        let riviumTraceError = RiviumTraceError.from(
            error: error,
            message: message,
            environment: cfg.environment,
            releaseVersion: cfg.release ?? DeviceInfo.shared.appVersion,
            userAgent: userAgent,
            breadcrumbs: BreadcrumbService.shared.getBreadcrumbs(),
            extra: mergeExtra(extra),
            tags: mergeTags(tags)
        )

        client?.sendError(riviumTraceError) { result in
            if case .success = result {
                completion?(true)
            } else {
                completion?(false)
            }
        }
    }

    /// Capture an NSException
    public func captureException(
        _ exception: NSException,
        message: String? = nil,
        extra: [String: Any] = [:],
        tags: [String: String] = [:],
        completion: ((Bool) -> Void)? = nil
    ) {
        guard ensureInitialized() else {
            completion?(false)
            return
        }

        guard let cfg = config else { return }

        BreadcrumbService.shared.addError("Exception: \(exception.name.rawValue)", data: [
            "reason": exception.reason ?? ""
        ])

        let riviumTraceError = RiviumTraceError.from(
            exception: exception,
            message: message,
            environment: cfg.environment,
            releaseVersion: cfg.release ?? DeviceInfo.shared.appVersion,
            userAgent: userAgent,
            breadcrumbs: BreadcrumbService.shared.getBreadcrumbs(),
            extra: mergeExtra(extra),
            tags: mergeTags(tags)
        )

        client?.sendError(riviumTraceError) { result in
            if case .success = result {
                completion?(true)
            } else {
                completion?(false)
            }
        }
    }

    /// Capture a message
    ///
    /// - Parameters:
    ///   - message: The message to capture
    ///   - level: Message severity level
    ///   - extra: Additional context data
    ///   - tags: Tags for categorization
    ///   - completion: Callback with success status
    public func captureMessage(
        _ message: String,
        level: MessageLevel = .info,
        extra: [String: Any] = [:],
        tags: [String: String] = [:],
        completion: ((Bool) -> Void)? = nil
    ) {
        guard ensureInitialized() else {
            completion?(false)
            return
        }

        guard let cfg = config else { return }

        let msg = RiviumTraceError.message(
            message,
            level: level,
            environment: cfg.environment,
            releaseVersion: cfg.release ?? DeviceInfo.shared.appVersion,
            userAgent: userAgent,
            breadcrumbs: BreadcrumbService.shared.getBreadcrumbs(),
            extra: mergeExtra(extra),
            tags: mergeTags(tags)
        )

        client?.sendMessage(msg) { result in
            if case .success = result {
                completion?(true)
            } else {
                completion?(false)
            }
        }
    }

    // MARK: - Performance Monitoring

    /// Report a performance span (HTTP request, DB query, etc.)
    ///
    /// - Parameters:
    ///   - span: The performance span to report
    ///   - completion: Callback with success status
    public func reportPerformanceSpan(_ span: PerformanceSpan, completion: ((Bool) -> Void)? = nil) {
        guard ensureInitialized() else {
            completion?(false)
            return
        }

        client?.sendPerformanceSpan(span) { result in
            if case .success = result {
                completion?(true)
            } else {
                completion?(false)
            }
        }
    }

    /// Report multiple performance spans in a batch
    ///
    /// - Parameters:
    ///   - spans: Array of performance spans to report
    ///   - completion: Callback with success status
    public func reportPerformanceSpanBatch(_ spans: [PerformanceSpan], completion: ((Bool) -> Void)? = nil) {
        guard ensureInitialized() else {
            completion?(false)
            return
        }

        client?.sendPerformanceSpanBatch(spans) { result in
            if case .success = result {
                completion?(true)
            } else {
                completion?(false)
            }
        }
    }

    /// Track an HTTP request performance
    ///
    /// - Parameters:
    ///   - request: The URLRequest
    ///   - response: The HTTPURLResponse
    ///   - startTime: When the request started
    ///   - error: Optional error if request failed
    public func trackHttpRequest(
        request: URLRequest,
        response: HTTPURLResponse?,
        startTime: Date,
        error: Error? = nil
    ) {
        guard ensureInitialized() else { return }
        guard let cfg = config else { return }

        let duration = Date().timeIntervalSince(startTime) * 1000 // Convert to ms
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        let path = request.url?.path ?? ""
        let host = request.url?.host ?? ""

        let endTime = Date()
        let span = PerformanceSpan(
            operation: "\(method) \(path)",
            operationType: "http",
            traceId: PerformanceSpan.generateTraceId(),
            spanId: PerformanceSpan.generateSpanId(),
            parentSpanId: nil,
            httpMethod: method,
            httpUrl: url,
            httpStatusCode: response?.statusCode,
            httpHost: host,
            durationMs: duration,
            startTime: startTime,
            endTime: endTime,
            platform: "ios",
            environment: cfg.environment,
            releaseVersion: cfg.release ?? DeviceInfo.shared.appVersion,
            status: error != nil ? "error" : (response?.statusCode ?? 0 >= 400 ? "error" : "ok"),
            errorMessage: error?.localizedDescription,
            tags: [:],
            metadata: [:]
        )

        reportPerformanceSpan(span, completion: nil)

        // Also add breadcrumb
        addHttpBreadcrumb(
            method: method,
            url: url,
            statusCode: response?.statusCode,
            duration: duration / 1000 // Convert back to seconds for breadcrumb
        )
    }

    // MARK: - Breadcrumbs

    /// Add a breadcrumb
    public func addBreadcrumb(_ message: String, type: BreadcrumbType = .info, data: [String: Any] = [:]) {
        BreadcrumbService.shared.add(message, type: type, data: data)
    }

    /// Add a navigation breadcrumb
    public func addNavigationBreadcrumb(from: String?, to: String) {
        BreadcrumbService.shared.addNavigation(from: from, to: to)
    }

    /// Add a user action breadcrumb
    public func addUserBreadcrumb(_ action: String, data: [String: Any] = [:]) {
        BreadcrumbService.shared.addUser(action, data: data)
    }

    /// Add an HTTP request breadcrumb
    public func addHttpBreadcrumb(method: String, url: String, statusCode: Int? = nil, duration: TimeInterval? = nil) {
        BreadcrumbService.shared.addHttp(method: method, url: url, statusCode: statusCode, duration: duration)
    }

    /// Clear all breadcrumbs
    public func clearBreadcrumbs() {
        BreadcrumbService.shared.clear()
    }

    // MARK: - Context & Tags

    /// Set the user ID
    public func setUserId(_ id: String?) {
        userId = id
        if let id = id {
            BreadcrumbService.shared.addSystem("User ID set", data: ["user_id": id])
        }
    }

    /// Get current user ID
    public func getUserId() -> String? {
        return userId
    }

    /// Set extra context data
    public func setExtra(_ key: String, value: Any?) {
        extraContext[key] = value
    }

    /// Set multiple extra context values
    public func setExtras(_ extras: [String: Any]) {
        for (key, value) in extras {
            extraContext[key] = value
        }
    }

    /// Clear extra context
    public func clearExtras() {
        extraContext.removeAll()
    }

    /// Set a tag
    public func setTag(_ key: String, value: String) {
        tags[key] = value
    }

    /// Set multiple tags
    public func setTags(_ newTags: [String: String]) {
        for (key, value) in newTags {
            tags[key] = value
        }
    }

    /// Clear all tags
    public func clearTags() {
        tags.removeAll()
    }

    // MARK: - Performance Tracking Setup

    /// Enable automatic HTTP performance tracking
    ///
    /// This registers a URLProtocol that intercepts all URLSession requests
    /// and reports timing data to RiviumTrace APM.
    ///
    /// Note: This only works with the default URLSession configuration.
    /// For custom sessions, use `performanceSessionConfiguration()` instead.
    public func enablePerformanceTracking() {
        RiviumTraceURLProtocol.register()
        logDebug("Automatic HTTP performance tracking enabled")
    }

    /// Disable automatic HTTP performance tracking
    public func disablePerformanceTracking() {
        RiviumTraceURLProtocol.unregister()
        logDebug("Automatic HTTP performance tracking disabled")
    }

    /// Get a URLSessionConfiguration with performance tracking enabled
    ///
    /// Use this to create custom URLSessions that still report performance data.
    ///
    /// Usage:
    /// ```swift
    /// let config = RiviumTrace.shared.performanceSessionConfiguration()
    /// let session = URLSession(configuration: config)
    /// ```
    public func performanceSessionConfiguration(baseConfiguration: URLSessionConfiguration = .default) -> URLSessionConfiguration {
        let config = baseConfiguration
        config.protocolClasses = [RiviumTraceURLProtocol.self] + (config.protocolClasses ?? [])
        return config
    }

    /// Set hosts to exclude from performance tracking
    ///
    /// Use this to exclude third-party analytics or other services you don't want to track.
    /// RiviumTrace's own API is always excluded automatically.
    public func setPerformanceExcludedHosts(_ hosts: [String]) {
        RiviumTraceURLProtocol.setExcludedHosts(hosts)
    }

    /// Set minimum duration (ms) for performance spans
    ///
    /// Spans shorter than this threshold are not reported.
    /// Default is 0 (report all spans).
    public func setPerformanceMinDuration(_ ms: Double) {
        RiviumTraceURLProtocol.setMinDurationMs(ms)
    }

    // MARK: - Logging

    /// Enable logging with optional configuration
    ///
    /// - Parameters:
    ///   - sourceId: Identifier for this log source (e.g., "my-ios-app")
    ///   - sourceName: Human-readable name for this source
    ///   - batchSize: Number of logs to batch before sending (default: 50)
    ///   - flushInterval: How often to flush logs in seconds (default: 5)
    public func enableLogging(
        sourceId: String? = nil,
        sourceName: String? = nil,
        batchSize: Int = 50,
        flushInterval: TimeInterval = 5.0
    ) {
        guard ensureInitialized(), let cfg = config else { return }

        logService = LogService(
            apiKey: cfg.apiKey,
            apiUrl: cfg.apiUrl,
            sourceId: sourceId,
            sourceName: sourceName,
            platform: "ios",
            environment: cfg.environment,
            release: cfg.release ?? DeviceInfo.shared.appVersion,
            batchSize: batchSize,
            flushInterval: flushInterval
        )

        logDebug("Logging enabled with sourceId: \(sourceId ?? "nil")")
    }

    /// Log a message with the specified level
    ///
    /// - Parameters:
    ///   - message: The log message
    ///   - level: Log level (trace, debug, info, warn, error, fatal)
    ///   - metadata: Additional metadata to attach to the log
    public func log(
        _ message: String,
        level: LogLevel = .info,
        metadata: [String: Any]? = nil
    ) {
        guard ensureInitialized() else { return }

        // Auto-enable logging if not already enabled
        if logService == nil {
            enableLogging()
        }

        logService?.log(message, level: level, metadata: metadata, userId: userId)
    }

    /// Log a trace-level message
    public func trace(_ message: String, metadata: [String: Any]? = nil) {
        log(message, level: .trace, metadata: metadata)
    }

    /// Log a debug-level message (different from SDK debug logs)
    public func logDebugMessage(_ message: String, metadata: [String: Any]? = nil) {
        log(message, level: .debug, metadata: metadata)
    }

    /// Log an info-level message
    public func info(_ message: String, metadata: [String: Any]? = nil) {
        log(message, level: .info, metadata: metadata)
    }

    /// Log a warning-level message
    public func warn(_ message: String, metadata: [String: Any]? = nil) {
        log(message, level: .warn, metadata: metadata)
    }

    /// Log an error-level message (for non-exception errors)
    public func logErrorMessage(_ message: String, metadata: [String: Any]? = nil) {
        log(message, level: .error, metadata: metadata)
    }

    /// Log a fatal-level message
    public func fatal(_ message: String, metadata: [String: Any]? = nil) {
        log(message, level: .fatal, metadata: metadata)
    }

    /// Flush all pending logs immediately
    public func flushLogs(completion: ((Bool) -> Void)? = nil) {
        logService?.flush(completion: completion)
    }

    /// Get the number of logs currently buffered
    public var pendingLogCount: Int {
        return logService?.bufferSize ?? 0
    }

    // MARK: - Lifecycle

    /// Close the SDK (call on app termination for graceful shutdown)
    public func close() {
        logDebug("RiviumTrace SDK closing...")

        // Flush pending logs
        logService?.flush(completion: nil)

        // Stop ANR watchdog
        ANRWatchdogService.shared.stop()

        // Shutdown network client
        client?.shutdown()

        BreadcrumbService.shared.addSystem("RiviumTrace SDK closed")

        logInfo("RiviumTrace SDK closed")
    }

    // MARK: - ANR Detection

    private func setupAnrDetection() {
        guard let cfg = config else { return }

        ANRWatchdogService.shared.start(timeoutMs: cfg.anrTimeoutMs) { [weak self] stackTrace in
            guard let self = self, let cfg = self.config else { return }

            logWarn("ANR detected, sending report...")

            let error = RiviumTraceError.anr(
                stackTrace: stackTrace,
                environment: cfg.environment,
                releaseVersion: cfg.release ?? DeviceInfo.shared.appVersion,
                userAgent: self.userAgent,
                anrDurationMs: cfg.anrTimeoutMs
            )

            self.client?.sendError(error, completion: nil)
        }

        logDebug("ANR detection started with timeout: \(cfg.anrTimeoutMs)ms")
    }

    // MARK: - Private Methods

    private func ensureInitialized() -> Bool {
        guard isInitialized else {
            logError("RiviumTrace SDK not initialized. Call RiviumTrace.shared.initialize() first.")
            return false
        }
        guard config?.enabled == true else {
            logDebug("RiviumTrace SDK is disabled")
            return false
        }
        return true
    }

    private func mergeExtra(_ extra: [String: Any]) -> [String: Any] {
        var merged = extraContext
        merged["user_id"] = userId
        merged["session_id"] = sessionId
        merged["device_info"] = DeviceInfo.shared.deviceInfo
        for (key, value) in extra {
            merged[key] = value
        }
        return merged
    }

    private func mergeTags(_ newTags: [String: String]) -> [String: String] {
        var merged = tags
        for (key, value) in newTags {
            merged[key] = value
        }
        return merged
    }

    private func sendPendingNativeCrashIfAny() {
        guard let cfg = config else { return }
        guard let error = NativeCrashReporter.shared.loadPendingCrashReport(
            environment: cfg.environment,
            releaseVersion: cfg.release ?? DeviceInfo.shared.appVersion,
            userAgent: userAgent
        ) else { return }

        logInfo("Sending native crash from previous session")
        // Send synchronously so the report is delivered before any other init
        // step risks pushing it out of the network queue.
        _ = client?.sendErrorSync(error)
    }

    private func setupUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            RiviumTrace.shared.handleUncaughtException(exception)
        }
        logDebug("Uncaught exception handler installed")
    }

    private func handleUncaughtException(_ exception: NSException) {
        logError("Uncaught exception: \(exception.name.rawValue) - \(exception.reason ?? "")")

        guard let cfg = config else { return }

        let error = RiviumTraceError.from(
            exception: exception,
            message: "Uncaught exception: \(exception.name.rawValue)",
            environment: cfg.environment,
            releaseVersion: cfg.release ?? DeviceInfo.shared.appVersion,
            userAgent: userAgent,
            breadcrumbs: BreadcrumbService.shared.getBreadcrumbs(),
            extra: mergeExtra(["error_type": "uncaught_exception"]),
            tags: tags
        )

        // Send synchronously to ensure delivery before crash
        _ = client?.sendErrorSync(error)
    }

    private func setupAppLifecycleObservers() {
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        #endif

        #if os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        #endif

        logDebug("App lifecycle observers registered")
    }

    @objc private func appDidEnterBackground() {
        BreadcrumbService.shared.addSystem("App entered background")
    }

    @objc private func appWillEnterForeground() {
        BreadcrumbService.shared.addSystem("App entered foreground")
    }

    @objc private func appWillTerminate() {
        close()
    }
}

// MARK: - Convenience Type Alias

/// Convenience type alias for NSException handler
public typealias NSExceptionHandler = (NSException) -> Void
