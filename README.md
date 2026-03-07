# RiviumTrace iOS SDK

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Official iOS SDK for [RiviumTrace](https://rivium.co/cloud/rivium-trace) - Error tracking, crash detection, and performance monitoring for iOS, macOS, tvOS, and watchOS apps.

**[RiviumTrace Landing Page](https://rivium.co/cloud/rivium-trace)** | **[Documentation](https://rivium.co/cloud/rivium-trace/docs/sdks-ios)** | **[Issues](https://github.com/Rivium-co/rivium-trace-ios-sdk/issues)**

## Features

- **Error Tracking** - Automatically capture uncaught exceptions and crashes
- **ANR Detection** - Detect Application Not Responding events (main thread blocked)
- **Signal Crash Detection** - Detect SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGPIPE, SIGSYS, SIGTRAP
- **Crash Detection** - Detect native crashes from previous sessions via marker system
- **Breadcrumbs** - Track user actions leading up to errors
- **Performance Monitoring** - HTTP request timing, custom span tracking, and batched reporting
- **Logging** - Structured logging with batching, exponential backoff retries, and level-based filtering
- **HTTP Tracking** - Automatic HTTP breadcrumbs and error capturing via URLProtocol
- **Tags & Context** - User sessions, global extras, tags, and custom metadata
- **Multi-Platform** - iOS 12+, macOS 10.14+, tvOS 12+, watchOS 5+
- **Zero Dependencies** - Pure Foundation-based, no external libraries

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Rivium-co/rivium-trace-ios-sdk.git", from: "0.1.0")
]
```

Or in Xcode: **File → Add Packages** → Enter the repository URL.

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'RiviumTrace', '~> 0.1'
```

Then run:

```bash
pod install
```

### Carthage

Add to your `Cartfile`:

```
github "Rivium-co/rivium-trace-ios-sdk" ~> 0.1
```

## Quick Start

### 1. Initialize the SDK

In your `AppDelegate`:

```swift
import RiviumTrace

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let config = RiviumTraceConfigBuilder(apiKey: "rv_live_your_api_key")
            .environment("production")
            .release(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .debug(false)
            .captureUncaughtExceptions(true)
            .captureSignalCrashes(true)
            .captureAnr(true)
            .anrTimeoutMs(5000)
            .build()

        RiviumTrace.shared.initialize(config: config)

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        RiviumTrace.shared.close()
    }
}
```

### 2. Capture Errors

```swift
// Capture error
do {
    try riskyOperation()
} catch {
    RiviumTrace.shared.captureError(error)
}

// Capture with extra context
RiviumTrace.shared.captureError(
    error,
    message: "Failed to process payment",
    extra: ["order_id": "123", "amount": 99.99]
)

// Capture NSException
RiviumTrace.shared.captureException(
    exception,
    message: "Legacy ObjC exception",
    extra: ["module": "PaymentBridge"]
)

// Capture message
RiviumTrace.shared.captureMessage(
    "User completed checkout",
    level: .info,
    extra: ["items": 3]
)
```

### 3. Add Breadcrumbs

Breadcrumbs are automatically added for:
- App foreground/background
- System events

Add custom breadcrumbs:

```swift
// User action
RiviumTrace.shared.addUserBreadcrumb("Added item to cart", data: ["product_id": "abc"])

// Navigation
RiviumTrace.shared.addNavigationBreadcrumb(from: "HomeScreen", to: "ProductScreen")

// HTTP request
RiviumTrace.shared.addHttpBreadcrumb(method: "GET", url: "https://api.example.com/users", statusCode: 200, duration: 0.15)

// Custom
RiviumTrace.shared.addBreadcrumb("Custom event", type: .info, data: ["key": "value"])
```

### 4. User Context

```swift
// Set user ID
RiviumTrace.shared.setUserId("user-123")

// Get user ID
let userId = RiviumTrace.shared.getUserId()

// Add custom context
RiviumTrace.shared.setExtra("subscription", value: "premium")
RiviumTrace.shared.setTag("build_type", value: "release")
```

## Context & Tags

### Global Extra Context

Set persistent context that is automatically included with all errors and messages:

```swift
// Set individual extra
RiviumTrace.shared.setExtra("organizationId", value: "org-123")
RiviumTrace.shared.setExtra("feature", value: "checkout-v2")

// Set multiple extras at once
RiviumTrace.shared.setExtras([
    "organizationId": "org-123",
    "feature": "checkout-v2",
    "experiment": "new-flow"
])

// Clear all extras
RiviumTrace.shared.clearExtras()
```

### Tags

Tags are key-value string pairs attached to all events:

```swift
// Set individual tag
RiviumTrace.shared.setTag("team", value: "payments")
RiviumTrace.shared.setTag("region", value: "us-east")

// Set multiple tags at once
RiviumTrace.shared.setTags(["team": "payments", "version": "2.1"])

// Clear all tags
RiviumTrace.shared.clearTags()
```

## Performance Monitoring

### Automatic HTTP Tracking

Enable automatic HTTP performance tracking via URLProtocol:

```swift
// Enable globally (works with default URLSession)
RiviumTrace.shared.enablePerformanceTracking()

// Disable when no longer needed
RiviumTrace.shared.disablePerformanceTracking()
```

### Custom URLSession with Performance Tracking

For custom URLSession configurations:

```swift
// Get a configuration with performance tracking enabled
let config = RiviumTrace.shared.performanceSessionConfiguration()
let session = URLSession(configuration: config)
```

### Configure Performance Tracking

```swift
// Exclude specific hosts from tracking
RiviumTrace.shared.setPerformanceExcludedHosts(["analytics.example.com", "ads.example.com"])

// Only report requests longer than 100ms
RiviumTrace.shared.setPerformanceMinDuration(100)
```

### Track HTTP Requests Manually

```swift
let startTime = Date()
let (data, response) = try await URLSession.shared.data(for: request)
RiviumTrace.shared.trackHttpRequest(
    request: request,
    response: response as? HTTPURLResponse,
    startTime: startTime
)
```

### Manual Span Reporting

```swift
// Report a custom performance span
let span = PerformanceSpan.custom(
    operation: "image_processing",
    durationMs: 1500,
    startTime: Date(timeIntervalSinceNow: -1.5),
    operationType: "custom",
    tags: ["format": "webp"]
)
RiviumTrace.shared.reportPerformanceSpan(span)

// Report a database query span
let dbSpan = PerformanceSpan.forDbQuery(
    queryType: "SELECT",
    tableName: "users",
    durationMs: 45,
    startTime: Date(timeIntervalSinceNow: -0.045),
    rowsAffected: 10
)
RiviumTrace.shared.reportPerformanceSpan(dbSpan)

// Report multiple spans in a batch
RiviumTrace.shared.reportPerformanceSpanBatch([span, dbSpan])
```

## Logging

### Enable Logging

```swift
RiviumTrace.shared.enableLogging(
    sourceId: "my-ios-app",          // Optional: group logs by source
    sourceName: "My iOS App",        // Optional: human-readable name
    batchSize: 50,                   // Logs per batch (default: 50)
    flushInterval: 5.0               // Auto-flush interval in seconds (default: 5)
)
```

### Log Messages

```swift
// Convenience methods for each level
RiviumTrace.shared.trace("Entering checkout flow")
RiviumTrace.shared.logDebugMessage("Cart items loaded", metadata: ["item_count": 3])
RiviumTrace.shared.info("User started checkout")
RiviumTrace.shared.warn("Inventory low for item SKU-123", metadata: ["stock": 2])
RiviumTrace.shared.logErrorMessage("Failed to apply discount code")
RiviumTrace.shared.fatal("Database connection lost")

// Generic log with explicit level
RiviumTrace.shared.log("Custom message", level: .info, metadata: ["key": "value"])
```

### Flush & Buffer Management

```swift
// Check pending log count
let pending = RiviumTrace.shared.pendingLogCount

// Force flush all buffered logs immediately
RiviumTrace.shared.flushLogs { success in
    print("Flush result: \(success)")
}
```

### Logging Features

- **Batching** - Logs are buffered and sent in configurable batches (default: 50)
- **Auto-flush** - Timer flushes logs at a configurable interval (default: 5s)
- **Exponential backoff** - Failed sends retry with delays: 1s, 2s, 4s, 8s... up to 60s
- **Buffer limit** - Max 1000 logs in buffer; oldest logs dropped when exceeded
- **Lazy timer** - Flush timer only runs when the buffer has logs
- **Lifecycle-aware** - Automatically flushes when app goes to background

## Automatic HTTP Breadcrumb Tracking

Enable automatic HTTP breadcrumb tracking and error capturing:

```swift
// Option 1: Enable globally
RiviumTraceURLProtocol.enable()

// Option 2: Use RiviumTrace session
let session = URLSession.riviumTraceSession()
session.dataTask(with: url) { data, response, error in
    // HTTP request automatically tracked as breadcrumb
}.resume()

// Configure HTTP error capturing
RiviumTraceURLProtocol.captureHttpErrors = true     // Capture 5xx server errors (default: true)
RiviumTraceURLProtocol.captureClientErrors = false   // Also capture 4xx client errors (default: false)
```

### Automatic Privacy Protection

The HTTP tracker automatically redacts sensitive query parameters:
- `token`, `api_key`, `apikey`, `key`, `secret`
- `password`, `pwd`, `auth`, `authorization`
- `access_token`, `refresh_token`, `session`

## Crash Detection

### How It Works

RiviumTrace uses a marker-based crash detection system that works for all crash types:

1. **On SDK Init**: Creates a crash marker file
2. **On Graceful Shutdown**: Deletes the marker via `RiviumTrace.shared.close()`
3. **On Next Launch**: If marker exists, a crash occurred - sends report

### Types of Crashes Detected

| Crash Type | Detection | Notes |
|------------|-----------|-------|
| Swift/ObjC Exceptions | Real-time | Captured immediately |
| ANR Events | Real-time | Main thread blocked for 5+ seconds |
| Signal Crashes (SIGSEGV, etc.) | Next Launch | Via crash marker |
| Memory Crashes | Next Launch | Via crash marker |

### Graceful Shutdown

The SDK automatically handles graceful shutdown via app lifecycle notifications. You can also call it manually:

```swift
// Manual cleanup (optional - auto-handled via notifications)
RiviumTrace.shared.close()
```

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `apiKey` | Required | Your API key from Rivium Console (`rv_live_xxx` or `rv_test_xxx`) |
| `environment` | `"production"` | Environment name (production, staging, etc.) |
| `release` | nil | App version string (auto-detected if nil) |
| `debug` | false | Enable debug logging |
| `enabled` | true | Enable/disable SDK |
| `captureUncaughtExceptions` | true | Capture uncaught exceptions |
| `captureSignalCrashes` | true | Capture signal crashes (SIGSEGV, etc.) |
| `captureAnr` | true | Detect ANR events (main thread blocked) |
| `anrTimeoutMs` | 5000 | ANR detection timeout (milliseconds) |
| `maxBreadcrumbs` | 20 | Maximum breadcrumbs to store |
| `httpTimeout` | 30 | HTTP request timeout (seconds) |
| `enableOfflineStorage` | true | Cache errors when offline |
| `sampleRate` | 1.0 | Error capture sample rate (0.0 - 1.0) |

## SwiftUI Integration

```swift
import SwiftUI
import RiviumTrace

@main
struct MyApp: App {

    init() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_live_your_api_key")
            .environment("production")
            .build()
        RiviumTrace.shared.initialize(config: config)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## API Reference

### RiviumTrace

**Initialization & Lifecycle:**
- `initialize(config:)` - Initialize SDK with configuration
- `initialize(apiKey:)` - Initialize SDK with just an API key
- `isReady` - Check if SDK is initialized
- `close()` - Cleanup SDK, flush pending data

**Error Capture:**
- `captureError(_:message:extra:tags:completion:)` - Capture a Swift Error
- `captureException(_:message:extra:tags:completion:)` - Capture an NSException
- `captureMessage(_:level:extra:tags:completion:)` - Capture a message

**User & Session:**
- `setUserId(_:)` - Set user ID
- `getUserId()` - Get current user ID

**Global Context (Extras):**
- `setExtra(_:value:)` - Set a single extra context value
- `setExtras(_:)` - Set multiple extra context values
- `clearExtras()` - Clear all extras

**Tags:**
- `setTag(_:value:)` - Set a single tag
- `setTags(_:)` - Set multiple tags
- `clearTags()` - Clear all tags

**Breadcrumbs:**
- `addBreadcrumb(_:type:data:)` - Add generic breadcrumb
- `addNavigationBreadcrumb(from:to:)` - Add navigation breadcrumb
- `addUserBreadcrumb(_:data:)` - Add user action breadcrumb
- `addHttpBreadcrumb(method:url:statusCode:duration:)` - Add HTTP breadcrumb
- `clearBreadcrumbs()` - Clear all breadcrumbs

**Performance Monitoring:**
- `reportPerformanceSpan(_:completion:)` - Report a PerformanceSpan object
- `reportPerformanceSpanBatch(_:completion:)` - Report multiple spans
- `trackHttpRequest(request:response:startTime:error:)` - Track HTTP request performance
- `enablePerformanceTracking()` - Enable automatic HTTP tracking
- `disablePerformanceTracking()` - Disable automatic HTTP tracking
- `performanceSessionConfiguration(baseConfiguration:)` - Get URLSessionConfiguration with tracking
- `setPerformanceExcludedHosts(_:)` - Exclude hosts from tracking
- `setPerformanceMinDuration(_:)` - Set minimum span duration

**Logging:**
- `enableLogging(sourceId:sourceName:batchSize:flushInterval:)` - Enable logging
- `log(_:level:metadata:)` - Log a message
- `trace(_:metadata:)` - Log at trace level
- `logDebugMessage(_:metadata:)` - Log at debug level
- `info(_:metadata:)` - Log at info level
- `warn(_:metadata:)` - Log at warn level
- `logErrorMessage(_:metadata:)` - Log at error level
- `fatal(_:metadata:)` - Log at fatal level
- `flushLogs(completion:)` - Flush all pending logs
- `pendingLogCount` - Get buffered log count

### PerformanceSpan

- `PerformanceSpan.fromHttpRequest(...)` - Create span from HTTP request
- `PerformanceSpan.forDbQuery(...)` - Create span for database query
- `PerformanceSpan.custom(...)` - Create custom span
- `PerformanceSpan.generateTraceId()` - Generate random trace ID
- `PerformanceSpan.generateSpanId()` - Generate random span ID

## Platform Support

| Platform | Minimum Version | Status |
|----------|----------------|--------|
| iOS | 12.0 | Supported |
| macOS | 10.14 | Supported |
| tvOS | 12.0 | Supported |
| watchOS | 5.0 | Supported |

## Minimum Requirements

- **Swift 5.5+**
- **Xcode 13+**
- **No external dependencies**

## License

MIT - see [LICENSE](LICENSE) for details.

## Support

- Landing Page: https://rivium.co/cloud/rivium-trace
- Documentation: https://rivium.co/cloud/rivium-trace/docs/sdks-ios
- Issues: https://github.com/Rivium-co/rivium-trace-ios-sdk/issues
- Email: support@rivium.co
