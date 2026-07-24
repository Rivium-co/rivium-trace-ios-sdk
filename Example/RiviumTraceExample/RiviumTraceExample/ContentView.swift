import SwiftUI
import RiviumTrace

struct ContentView: View {
    @State private var statusMessage = ""
    @State private var showingSecondView = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Test error tracking, logging, and performance features")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    // Error Tracking Section
                    SectionHeader(title: "Error Tracking")

                    DemoButton(title: "Capture Exception", color: .blue) {
                        captureException()
                    }

                    DemoButton(title: "Capture Message", color: .blue) {
                        captureMessage()
                    }

                    DemoButton(title: "Trigger Crash (will crash app!)", color: .red) {
                        triggerCrash()
                    }

                    // Breadcrumbs Section
                    SectionHeader(title: "Breadcrumbs")

                    DemoButton(title: "Add Breadcrumb", color: .green) {
                        addBreadcrumb()
                    }

                    NavigationLink(destination: SecondView(), isActive: $showingSecondView) {
                        EmptyView()
                    }

                    DemoButton(title: "Navigate (auto breadcrumb)", color: .green) {
                        RiviumTrace.shared.addUserBreadcrumb("Navigating to SecondView")
                        RiviumTrace.shared.captureMessage(
                            "User navigating to SecondView",
                            level: .info,
                            extra: ["from": "ContentView", "to": "SecondView"]
                        )
                        showingSecondView = true
                    }

                    DemoButton(title: "HTTP Request", color: .green) {
                        httpRequest()
                    }

                    // User Context Section
                    SectionHeader(title: "User Context")

                    DemoButton(title: "Set User ID", color: .purple) {
                        setUserId()
                    }

                    // Performance Section
                    SectionHeader(title: "Performance")

                    DemoButton(title: "Track Performance (Manual Spans)", color: .orange) {
                        trackPerformance()
                    }

                    DemoButton(title: "Performance Tracking (Auto HTTP)", color: .orange) {
                        performanceAutoTracking()
                    }

                    DemoButton(title: "DB Query Span", color: .orange) {
                        dbQuerySpan()
                    }

                    DemoButton(title: "Track Operation (Auto-timed)", color: .orange) {
                        trackOperation()
                    }

                    DemoButton(title: "Batch Span Reporting", color: .orange) {
                        batchSpans()
                    }

                    // Logging Section
                    SectionHeader(title: "Logging")

                    DemoButton(title: "Send Logs", color: .teal) {
                        sendLogs()
                    }

                    // Advanced Features Section
                    SectionHeader(title: "Advanced Features")

                    DemoButton(title: "Check Crash Detection", color: .gray) {
                        checkCrashDetection()
                    }

                    DemoButton(title: "Sample Rate Demo (10 errors)", color: .gray) {
                        sampleRateDemo()
                    }

                    // Native Crash Tests — kill the app with real POSIX signals
                    // so PLCrashReporter writes a report to disk. On next launch
                    // the SDK drains it and posts the Sentry-shape event.
                    // These must be exercised outside the Xcode debugger; LLDB
                    // intercepts signals before PLCrashReporter can see them.
                    SectionHeader(title: "Native Crash Tests (kills app)")

                    DemoButton(title: "Native Crash (SIGSEGV)", color: .red) {
                        triggerNativeCrash(kind: "signal")
                    }

                    DemoButton(title: "Native Crash (abort)", color: .red) {
                        triggerNativeCrash(kind: "abort")
                    }

                    DemoButton(title: "ANR (block main 25s)", color: .orange) {
                        triggerNativeCrash(kind: "anr")
                    }

                    // Status message
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("RiviumTrace SDK Example")
        }
    }

    // MARK: - Error Tracking

    private func captureException() {
        RiviumTrace.shared.addUserBreadcrumb("Clicked capture exception button")

        let error = NSError(
            domain: "co.rivium.trace.example",
            code: 1001,
            userInfo: [NSLocalizedDescriptionKey: "Test exception from RiviumTrace Example App"]
        )

        RiviumTrace.shared.captureError(
            error,
            extra: ["button": "capture_exception", "screen": "main"]
        ) { success in
            DispatchQueue.main.async {
                statusMessage = success ? "Exception captured!" : "Failed to capture"
            }
        }
    }

    private func captureMessage() {
        RiviumTrace.shared.addUserBreadcrumb("Clicked capture message button")

        RiviumTrace.shared.captureMessage(
            "User clicked the test button",
            level: .info,
            extra: ["action": "test_button_click"]
        ) { success in
            DispatchQueue.main.async {
                statusMessage = success ? "Message captured!" : "Failed to capture"
            }
        }
    }

    private func triggerCrash() {
        RiviumTrace.shared.addUserBreadcrumb("User triggered intentional crash")
        RiviumTrace.shared.captureMessage("About to crash intentionally", level: .warning)

        // This will crash the app - SDK will capture it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            fatalError("Intentional crash for testing RiviumTrace")
        }
    }

    // MARK: - Breadcrumbs

    private func addBreadcrumb() {
        RiviumTrace.shared.addBreadcrumb(
            "Custom breadcrumb added",
            type: .user,
            data: ["timestamp": Int(Date().timeIntervalSince1970 * 1000)]
        )

        RiviumTrace.shared.captureMessage(
            "Breadcrumb test - custom breadcrumb added",
            level: .info,
            extra: ["test_type": "breadcrumb"]
        ) { success in
            DispatchQueue.main.async {
                statusMessage = success
                    ? "Breadcrumb added and sent!"
                    : "Breadcrumb added locally but failed to send"
            }
        }
    }

    private func httpRequest() {
        RiviumTrace.shared.addUserBreadcrumb("Making HTTP request")
        statusMessage = "Making HTTP request..."

        let url = URL(string: "https://httpbin.org/get")!
        let startTime = Date()

        URLSession.shared.dataTask(with: url) { _, response, error in
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0

            // Add HTTP breadcrumb manually
            RiviumTrace.shared.addHttpBreadcrumb(
                method: "GET",
                url: "https://httpbin.org/get",
                statusCode: statusCode,
                duration: Date().timeIntervalSince(startTime)
            )

            if let error = error {
                RiviumTrace.shared.captureError(error, message: "HTTP Request failed")
                DispatchQueue.main.async {
                    statusMessage = "HTTP Request failed: \(error.localizedDescription)"
                }
                return
            }

            RiviumTrace.shared.captureMessage(
                "HTTP request completed",
                level: .info,
                extra: [
                    "method": "GET",
                    "url": "https://httpbin.org/get",
                    "status_code": statusCode
                ]
            ) { success in
                DispatchQueue.main.async {
                    statusMessage = success
                        ? "HTTP Request successful: \(statusCode)"
                        : "HTTP Request done but failed to send to API"
                }
            }
        }.resume()
    }

    // MARK: - User Context

    private func setUserId() {
        let userId = "user_\(Int(Date().timeIntervalSince1970 * 1000))"
        RiviumTrace.shared.setUserId(userId)

        RiviumTrace.shared.captureMessage(
            "User ID updated",
            level: .info,
            extra: ["user_id": userId]
        ) { success in
            DispatchQueue.main.async {
                statusMessage = success
                    ? "User ID set: \(userId)"
                    : "User ID set locally but failed to send to API"
            }
        }
    }

    // MARK: - Performance

    private func trackPerformance() {
        RiviumTrace.shared.addUserBreadcrumb("Testing performance tracking")
        statusMessage = "Tracking performance..."

        DispatchQueue.global().async {
            // 1. Simulated API call span
            let startTime1 = Date()
            Thread.sleep(forTimeInterval: 0.35)
            let span1 = PerformanceSpan.fromHttpRequest(
                method: "GET",
                url: "https://api.example.com/users",
                statusCode: 200,
                durationMs: Date().timeIntervalSince(startTime1) * 1000,
                startTime: startTime1,
                tags: ["endpoint": "users"]
            )
            RiviumTrace.shared.reportPerformanceSpan(span1)

            // 2. Simulated slow DB query span
            let startTime2 = Date()
            Thread.sleep(forTimeInterval: 0.15)
            let span2 = PerformanceSpan.forDbQuery(
                queryType: "SELECT",
                tableName: "users",
                durationMs: Date().timeIntervalSince(startTime2) * 1000,
                startTime: startTime2,
                rowsAffected: 42,
                tags: ["query_type": "SELECT"]
            )
            RiviumTrace.shared.reportPerformanceSpan(span2)

            // 3. Simulated failed request span
            let startTime3 = Date()
            Thread.sleep(forTimeInterval: 0.1)
            let span3 = PerformanceSpan.fromHttpRequest(
                method: "POST",
                url: "https://api.example.com/orders",
                statusCode: 500,
                durationMs: Date().timeIntervalSince(startTime3) * 1000,
                startTime: startTime3,
                errorMessage: "Internal Server Error",
                tags: ["endpoint": "orders"]
            )
            RiviumTrace.shared.reportPerformanceSpan(span3)

            DispatchQueue.main.async {
                statusMessage = "3 performance spans sent to RiviumTrace"
            }
        }
    }

    private func performanceAutoTracking() {
        RiviumTrace.shared.addUserBreadcrumb("Testing performance auto-tracking")
        statusMessage = "Making auto-tracked HTTP requests..."

        // Enable performance tracking (auto HTTP via URLProtocol)
        RiviumTrace.shared.enablePerformanceTracking()

        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: 0)
            var code1 = 0
            var code2 = 0

            // Request 1 - auto-tracked as performance span
            let url1 = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!
            URLSession.shared.dataTask(with: url1) { _, response, _ in
                code1 = (response as? HTTPURLResponse)?.statusCode ?? 0
                semaphore.signal()
            }.resume()
            semaphore.wait()

            // Request 2 - also auto-tracked
            let url2 = URL(string: "https://jsonplaceholder.typicode.com/users/1")!
            URLSession.shared.dataTask(with: url2) { _, response, _ in
                code2 = (response as? HTTPURLResponse)?.statusCode ?? 0
                semaphore.signal()
            }.resume()
            semaphore.wait()

            DispatchQueue.main.async {
                statusMessage = "2 HTTP requests auto-tracked: \(code1), \(code2)"
            }
        }
    }

    private func dbQuerySpan() {
        statusMessage = "Reporting DB query spans..."

        DispatchQueue.global().async {
            // Simulate a SELECT query
            let startTime1 = Date()
            Thread.sleep(forTimeInterval: 0.015)
            let span1 = PerformanceSpan.forDbQuery(
                queryType: "SELECT",
                tableName: "users",
                durationMs: Date().timeIntervalSince(startTime1) * 1000,
                startTime: startTime1,
                rowsAffected: 42
            )
            RiviumTrace.shared.reportPerformanceSpan(span1)

            // Simulate an INSERT query
            let startTime2 = Date()
            Thread.sleep(forTimeInterval: 0.025)
            let span2 = PerformanceSpan.forDbQuery(
                queryType: "INSERT",
                tableName: "orders",
                durationMs: Date().timeIntervalSince(startTime2) * 1000,
                startTime: startTime2,
                rowsAffected: 1,
                tags: ["priority": "high"]
            )
            RiviumTrace.shared.reportPerformanceSpan(span2)

            DispatchQueue.main.async {
                statusMessage = "2 DB query spans sent to RiviumTrace"
            }
        }
    }

    private func trackOperation() {
        statusMessage = "Running tracked operation..."

        DispatchQueue.global().async {
            // trackOperation auto-measures the duration and reports a span
            let result: String = PerformanceTracker.track("simulateApiCall", operationType: "custom") {
                Thread.sleep(forTimeInterval: 0.35)
                return "success"
            }

            // Track an operation that fails
            do {
                let _: Void = try PerformanceTracker.track("failingOperation", operationType: "custom") {
                    Thread.sleep(forTimeInterval: 0.1)
                    throw NSError(
                        domain: "co.rivium.trace.example",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Simulated operation failure"]
                    )
                }
            } catch {
                // Expected - the span is reported with status "error"
            }

            DispatchQueue.main.async {
                statusMessage = "2 operations tracked (1 ok, 1 error). Result: \(result)"
            }
        }
    }

    private func batchSpans() {
        statusMessage = "Sending batch of spans..."

        DispatchQueue.global().async {
            let now = Date()
            let spans = [
                PerformanceSpan.fromHttpRequest(
                    method: "GET",
                    url: "https://api.example.com/products",
                    statusCode: 200,
                    durationMs: 120,
                    startTime: now.addingTimeInterval(-0.12)
                ),
                PerformanceSpan.forDbQuery(
                    queryType: "SELECT",
                    tableName: "products",
                    durationMs: 8,
                    startTime: now.addingTimeInterval(-0.008),
                    rowsAffected: 50
                ),
                PerformanceSpan.custom(
                    operation: "renderProductList",
                    durationMs: 45,
                    startTime: now.addingTimeInterval(-0.045),
                    operationType: "render"
                )
            ]

            RiviumTrace.shared.reportPerformanceSpanBatch(spans) { success in
                DispatchQueue.main.async {
                    statusMessage = success
                        ? "Batch of \(spans.count) spans sent!"
                        : "Failed to send batch"
                }
            }
        }
    }

    // MARK: - Logging

    private func sendLogs() {
        RiviumTrace.shared.trace("Entering checkout flow")
        RiviumTrace.shared.logDebugMessage("Cart items loaded", metadata: ["item_count": 3])
        RiviumTrace.shared.info("User started checkout")
        RiviumTrace.shared.warn("Inventory low for item SKU-123", metadata: ["stock": 2])
        RiviumTrace.shared.logErrorMessage("Failed to apply discount code")
        RiviumTrace.shared.fatal("Database connection lost")

        RiviumTrace.shared.flushLogs()
        statusMessage = "6 logs sent to RiviumTrace"
    }

    // MARK: - Advanced Features

    private func checkCrashDetection() {
        RiviumTrace.shared.captureMessage(
            "Crash detection is automatic. Use 'Trigger Crash' then reopen the app to test.",
            level: .info,
            extra: [
                "feature": "crash_detection",
                "how_it_works": "Session marker file + clean exit marker",
                "max_crash_age_hours": 24
            ]
        ) { success in
            DispatchQueue.main.async {
                statusMessage = """
                Crash detection is automatic on SDK init.
                1) Press 'Trigger Crash'
                2) Reopen app
                3) SDK auto-reports the crash
                """
            }
        }
    }

    private func sampleRateDemo() {
        statusMessage = "Sending 10 errors with sampleRate: 1.0..."

        var sentCount = 0
        let totalErrors = 10
        let lock = NSLock()

        DispatchQueue.global().async {
            let group = DispatchGroup()

            for i in 0..<totalErrors {
                group.enter()
                let error = NSError(
                    domain: "co.rivium.trace.example",
                    code: 2000 + i,
                    userInfo: [NSLocalizedDescriptionKey: "Sample rate test error #\(i)"]
                )

                RiviumTrace.shared.captureError(
                    error,
                    message: "Sample rate test",
                    extra: ["error_index": i, "total_errors": totalErrors]
                ) { success in
                    if success {
                        lock.lock()
                        sentCount += 1
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            // Wait for callbacks
            _ = group.wait(timeout: .now() + 5.0)

            DispatchQueue.main.async {
                statusMessage = "Sample rate: \(sentCount)/\(totalErrors) errors sent (rate: 1.0)"
            }
        }
    }

    // MARK: - Native crash triggers
    //
    // Real POSIX signals so PLCrashReporter records a report to disk. The
    // report is drained + POSTed on the next launch. Nothing to do app-side
    // beyond relaunching after the crash. Must be tested with the app
    // detached from LLDB (release build or after `flutter run` disconnect),
    // otherwise the debugger intercepts signals first.
    private func triggerNativeCrash(kind: String) {
        RiviumTrace.shared.addBreadcrumb(
            "User triggered native crash (\(kind))",
            type: .info
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            switch kind {
            case "abort":
                abort()
            case "anr":
                // iOS watchdog kills apps that block the main thread for ~20s.
                Thread.sleep(forTimeInterval: 25)
            default:
                // SIGSEGV via null-region raw pointer store. Swift's
                // UnsafeMutablePointer.init(bitPattern:) traps at address 0
                // via a Swift-runtime check, so we cast a raw pointer at
                // 0x1 (also invalid) and let the CPU fault.
                let raw = UnsafeMutableRawPointer(bitPattern: 0x1)!
                raw.storeBytes(of: Int(42), as: Int.self)
            }
        }
    }
}

// MARK: - Helper Views

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal)
            .padding(.top, 12)
    }
}

struct DemoButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .padding(.horizontal)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
