import XCTest
@testable import RiviumTrace

// MARK: - RiviumTraceConfig Tests

final class RiviumTraceConfigTests: XCTestCase {

    // MARK: Default Values

    func testConfigDefaultValues() {
        let config = RiviumTraceConfig(apiKey: "rv_test_abc123")

        XCTAssertEqual(config.apiKey, "rv_test_abc123")
        XCTAssertEqual(config.environment, "production")
        XCTAssertNil(config.release)
        XCTAssertFalse(config.debug)
        XCTAssertTrue(config.enabled)
        XCTAssertTrue(config.captureUncaughtExceptions)
        XCTAssertTrue(config.captureSignalCrashes)
        XCTAssertTrue(config.captureAnr)
        XCTAssertEqual(config.anrTimeoutMs, 5000)
        XCTAssertEqual(config.maxBreadcrumbs, 20)
        XCTAssertEqual(config.httpTimeout, 30)
        XCTAssertTrue(config.enableOfflineStorage)
        XCTAssertEqual(config.sampleRate, 1.0)
    }

    func testConfigCustomValues() {
        let config = RiviumTraceConfig(
            apiKey: "rv_live_xyz789",
            environment: "staging",
            release: "2.0.0",
            debug: true,
            enabled: false,
            captureUncaughtExceptions: false,
            captureSignalCrashes: false,
            captureAnr: false,
            anrTimeoutMs: 10000,
            maxBreadcrumbs: 50,
            httpTimeout: 60,
            enableOfflineStorage: false,
            sampleRate: 0.5
        )

        XCTAssertEqual(config.apiKey, "rv_live_xyz789")
        XCTAssertEqual(config.environment, "staging")
        XCTAssertEqual(config.release, "2.0.0")
        XCTAssertTrue(config.debug)
        XCTAssertFalse(config.enabled)
        XCTAssertFalse(config.captureUncaughtExceptions)
        XCTAssertFalse(config.captureSignalCrashes)
        XCTAssertFalse(config.captureAnr)
        XCTAssertEqual(config.anrTimeoutMs, 10000)
        XCTAssertEqual(config.maxBreadcrumbs, 50)
        XCTAssertEqual(config.httpTimeout, 60)
        XCTAssertFalse(config.enableOfflineStorage)
        XCTAssertEqual(config.sampleRate, 0.5)
    }

    // MARK: API Key Prefixes

    func testConfigAcceptsRvLivePrefix() {
        let config = RiviumTraceConfig(apiKey: "rv_live_key123")
        XCTAssertEqual(config.apiKey, "rv_live_key123")
    }

    func testConfigAcceptsRvTestPrefix() {
        let config = RiviumTraceConfig(apiKey: "rv_test_key123")
        XCTAssertEqual(config.apiKey, "rv_test_key123")
    }

    func testConfigAcceptsNlLivePrefix() {
        let config = RiviumTraceConfig(apiKey: "nl_live_key123")
        XCTAssertEqual(config.apiKey, "nl_live_key123")
    }

    func testConfigAcceptsNlTestPrefix() {
        let config = RiviumTraceConfig(apiKey: "nl_test_key123")
        XCTAssertEqual(config.apiKey, "nl_test_key123")
    }

    // MARK: Simple Factory

    func testSimpleConfigFactory() {
        let config = RiviumTraceConfig.simple(apiKey: "rv_test_simple")

        XCTAssertEqual(config.apiKey, "rv_test_simple")
        XCTAssertEqual(config.environment, "production")
        XCTAssertNil(config.release)
        XCTAssertFalse(config.debug)
        XCTAssertTrue(config.enabled)
        XCTAssertTrue(config.captureUncaughtExceptions)
        XCTAssertTrue(config.captureSignalCrashes)
        XCTAssertTrue(config.captureAnr)
        XCTAssertEqual(config.anrTimeoutMs, 5000)
        XCTAssertEqual(config.maxBreadcrumbs, 20)
        XCTAssertEqual(config.httpTimeout, 30)
        XCTAssertTrue(config.enableOfflineStorage)
        XCTAssertEqual(config.sampleRate, 1.0)
    }

    // MARK: Boundary Values

    func testConfigSampleRateZero() {
        let config = RiviumTraceConfig(apiKey: "rv_test_abc", sampleRate: 0.0)
        XCTAssertEqual(config.sampleRate, 0.0)
    }

    func testConfigSampleRateOne() {
        let config = RiviumTraceConfig(apiKey: "rv_test_abc", sampleRate: 1.0)
        XCTAssertEqual(config.sampleRate, 1.0)
    }

    func testConfigSampleRateMidRange() {
        let config = RiviumTraceConfig(apiKey: "rv_test_abc", sampleRate: 0.75)
        XCTAssertEqual(config.sampleRate, 0.75)
    }

    func testConfigMaxBreadcrumbsMinimum() {
        let config = RiviumTraceConfig(apiKey: "rv_test_abc", maxBreadcrumbs: 1)
        XCTAssertEqual(config.maxBreadcrumbs, 1)
    }

    func testConfigHttpTimeoutMinimum() {
        let config = RiviumTraceConfig(apiKey: "rv_test_abc", httpTimeout: 0.001)
        XCTAssertEqual(config.httpTimeout, 0.001, accuracy: 0.0001)
    }

    func testConfigAnrTimeoutMsMinimum() {
        let config = RiviumTraceConfig(apiKey: "rv_test_abc", anrTimeoutMs: 1)
        XCTAssertEqual(config.anrTimeoutMs, 1)
    }

    func testConfigReleaseNilByDefault() {
        let config = RiviumTraceConfig(apiKey: "rv_test_abc")
        XCTAssertNil(config.release)
    }

    func testConfigReleaseCanBeSet() {
        let config = RiviumTraceConfig(apiKey: "rv_test_abc", release: "3.2.1")
        XCTAssertEqual(config.release, "3.2.1")
    }
}

// MARK: - RiviumTraceConfigBuilder Tests

final class RiviumTraceConfigBuilderTests: XCTestCase {

    func testBuilderDefaults() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_builder")
            .build()

        XCTAssertEqual(config.apiKey, "rv_test_builder")
        XCTAssertEqual(config.environment, "production")
        XCTAssertNil(config.release)
        XCTAssertFalse(config.debug)
        XCTAssertTrue(config.enabled)
        XCTAssertTrue(config.captureUncaughtExceptions)
        XCTAssertTrue(config.captureSignalCrashes)
        XCTAssertTrue(config.captureAnr)
        XCTAssertEqual(config.anrTimeoutMs, 5000)
        XCTAssertEqual(config.maxBreadcrumbs, 20)
        XCTAssertEqual(config.httpTimeout, 30)
        XCTAssertTrue(config.enableOfflineStorage)
        XCTAssertEqual(config.sampleRate, 1.0)
    }

    func testBuilderEnvironment() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .environment("staging")
            .build()
        XCTAssertEqual(config.environment, "staging")
    }

    func testBuilderRelease() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .release("1.2.3")
            .build()
        XCTAssertEqual(config.release, "1.2.3")
    }

    func testBuilderReleaseNil() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .release(nil)
            .build()
        XCTAssertNil(config.release)
    }

    func testBuilderDebug() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .debug(true)
            .build()
        XCTAssertTrue(config.debug)
    }

    func testBuilderEnabled() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .enabled(false)
            .build()
        XCTAssertFalse(config.enabled)
    }

    func testBuilderCaptureUncaughtExceptions() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .captureUncaughtExceptions(false)
            .build()
        XCTAssertFalse(config.captureUncaughtExceptions)
    }

    func testBuilderCaptureSignalCrashes() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .captureSignalCrashes(false)
            .build()
        XCTAssertFalse(config.captureSignalCrashes)
    }

    func testBuilderCaptureAnr() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .captureAnr(false)
            .build()
        XCTAssertFalse(config.captureAnr)
    }

    func testBuilderAnrTimeoutMs() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .anrTimeoutMs(10000)
            .build()
        XCTAssertEqual(config.anrTimeoutMs, 10000)
    }

    func testBuilderMaxBreadcrumbs() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .maxBreadcrumbs(50)
            .build()
        XCTAssertEqual(config.maxBreadcrumbs, 50)
    }

    func testBuilderHttpTimeout() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .httpTimeout(120)
            .build()
        XCTAssertEqual(config.httpTimeout, 120)
    }

    func testBuilderEnableOfflineStorage() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .enableOfflineStorage(false)
            .build()
        XCTAssertFalse(config.enableOfflineStorage)
    }

    func testBuilderSampleRate() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .sampleRate(0.25)
            .build()
        XCTAssertEqual(config.sampleRate, 0.25)
    }

    func testBuilderFullChain() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_chain")
            .environment("development")
            .release("5.0.0")
            .debug(true)
            .enabled(false)
            .captureUncaughtExceptions(false)
            .captureSignalCrashes(false)
            .captureAnr(false)
            .anrTimeoutMs(3000)
            .maxBreadcrumbs(100)
            .httpTimeout(45)
            .enableOfflineStorage(false)
            .sampleRate(0.1)
            .build()

        XCTAssertEqual(config.apiKey, "rv_test_chain")
        XCTAssertEqual(config.environment, "development")
        XCTAssertEqual(config.release, "5.0.0")
        XCTAssertTrue(config.debug)
        XCTAssertFalse(config.enabled)
        XCTAssertFalse(config.captureUncaughtExceptions)
        XCTAssertFalse(config.captureSignalCrashes)
        XCTAssertFalse(config.captureAnr)
        XCTAssertEqual(config.anrTimeoutMs, 3000)
        XCTAssertEqual(config.maxBreadcrumbs, 100)
        XCTAssertEqual(config.httpTimeout, 45)
        XCTAssertFalse(config.enableOfflineStorage)
        XCTAssertEqual(config.sampleRate, 0.1)
    }

    func testBuilderOverwritesValues() {
        let config = RiviumTraceConfigBuilder(apiKey: "rv_test_abc")
            .environment("staging")
            .environment("production")
            .build()
        XCTAssertEqual(config.environment, "production")
    }
}

// MARK: - BreadcrumbType Tests

final class BreadcrumbTypeTests: XCTestCase {

    func testAllCasesRawValues() {
        XCTAssertEqual(BreadcrumbType.navigation.rawValue, "navigation")
        XCTAssertEqual(BreadcrumbType.user.rawValue, "user")
        XCTAssertEqual(BreadcrumbType.http.rawValue, "http")
        XCTAssertEqual(BreadcrumbType.state.rawValue, "state")
        XCTAssertEqual(BreadcrumbType.info.rawValue, "info")
        XCTAssertEqual(BreadcrumbType.error.rawValue, "error")
        XCTAssertEqual(BreadcrumbType.system.rawValue, "system")
    }

    func testFromStringLowercase() {
        XCTAssertEqual(BreadcrumbType.from("navigation"), .navigation)
        XCTAssertEqual(BreadcrumbType.from("user"), .user)
        XCTAssertEqual(BreadcrumbType.from("http"), .http)
        XCTAssertEqual(BreadcrumbType.from("state"), .state)
        XCTAssertEqual(BreadcrumbType.from("info"), .info)
        XCTAssertEqual(BreadcrumbType.from("error"), .error)
        XCTAssertEqual(BreadcrumbType.from("system"), .system)
    }

    func testFromStringUppercase() {
        XCTAssertEqual(BreadcrumbType.from("NAVIGATION"), .navigation)
        XCTAssertEqual(BreadcrumbType.from("USER"), .user)
        XCTAssertEqual(BreadcrumbType.from("HTTP"), .http)
        XCTAssertEqual(BreadcrumbType.from("ERROR"), .error)
    }

    func testFromStringMixedCase() {
        XCTAssertEqual(BreadcrumbType.from("Navigation"), .navigation)
        XCTAssertEqual(BreadcrumbType.from("Http"), .http)
        XCTAssertEqual(BreadcrumbType.from("System"), .system)
    }

    func testFromStringInvalidDefaultsToInfo() {
        XCTAssertEqual(BreadcrumbType.from("unknown"), .info)
        XCTAssertEqual(BreadcrumbType.from(""), .info)
        XCTAssertEqual(BreadcrumbType.from("nonsense"), .info)
        XCTAssertEqual(BreadcrumbType.from("navigations"), .info)
    }
}

// MARK: - Breadcrumb Tests

final class BreadcrumbTests: XCTestCase {

    func testBreadcrumbDefaultValues() {
        let before = Date()
        let breadcrumb = Breadcrumb(message: "test message")
        let after = Date()

        XCTAssertEqual(breadcrumb.message, "test message")
        XCTAssertEqual(breadcrumb.type, .info)
        XCTAssertTrue(breadcrumb.timestamp >= before)
        XCTAssertTrue(breadcrumb.timestamp <= after)
        XCTAssertTrue(breadcrumb.data.isEmpty)
    }

    func testBreadcrumbCustomValues() {
        let customDate = Date(timeIntervalSince1970: 1000)
        let breadcrumb = Breadcrumb(
            message: "custom",
            type: .error,
            timestamp: customDate,
            data: ["key": "value"]
        )

        XCTAssertEqual(breadcrumb.message, "custom")
        XCTAssertEqual(breadcrumb.type, .error)
        XCTAssertEqual(breadcrumb.timestamp, customDate)
        XCTAssertEqual(breadcrumb.data["key"]?.value as? String, "value")
    }

    func testBreadcrumbWithEmptyMessage() {
        let breadcrumb = Breadcrumb(message: "")
        XCTAssertEqual(breadcrumb.message, "")
    }

    func testBreadcrumbWithLongMessage() {
        let longMessage = String(repeating: "a", count: 10000)
        let breadcrumb = Breadcrumb(message: longMessage)
        XCTAssertEqual(breadcrumb.message, longMessage)
    }

    // MARK: toDictionary

    func testToDictionaryStructure() {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let breadcrumb = Breadcrumb(
            message: "test msg",
            type: .http,
            timestamp: fixedDate,
            data: ["status": 200]
        )
        let dict = breadcrumb.toDictionary()

        XCTAssertEqual(dict["message"] as? String, "test msg")
        XCTAssertEqual(dict["type"] as? String, "http")
        XCTAssertEqual(dict["timestamp"] as? Int64, Int64(fixedDate.timeIntervalSince1970 * 1000))
        XCTAssertNotNil(dict["data"])
    }

    func testToDictionaryTimestampIsMilliseconds() {
        let date = Date(timeIntervalSince1970: 1234567.0)
        let breadcrumb = Breadcrumb(message: "ts", timestamp: date)
        let dict = breadcrumb.toDictionary()
        let ts = dict["timestamp"] as? Int64
        XCTAssertEqual(ts, 1234567000)
    }

    func testToDictionaryTypeUsesRawValue() {
        for type: BreadcrumbType in [.navigation, .user, .http, .state, .info, .error, .system] {
            let breadcrumb = Breadcrumb(message: "test", type: type)
            let dict = breadcrumb.toDictionary()
            XCTAssertEqual(dict["type"] as? String, type.rawValue)
        }
    }

    func testToDictionaryIncludesData() {
        let breadcrumb = Breadcrumb(message: "test", data: ["key1": "val1", "key2": 42])
        let dict = breadcrumb.toDictionary()
        let data = dict["data"] as? [String: Any]
        XCTAssertNotNil(data)
        XCTAssertEqual(data?["key1"] as? String, "val1")
        XCTAssertEqual(data?["key2"] as? Int, 42)
    }

    func testToDictionaryEmptyData() {
        let breadcrumb = Breadcrumb(message: "test")
        let dict = breadcrumb.toDictionary()
        let data = dict["data"] as? [String: Any]
        XCTAssertNotNil(data)
        XCTAssertTrue(data?.isEmpty ?? false)
    }

    // MARK: Factory Methods

    func testNavigationFactoryWithFromAndTo() {
        let breadcrumb = Breadcrumb.navigation(from: "Home", to: "Profile")

        XCTAssertEqual(breadcrumb.type, .navigation)
        XCTAssertTrue(breadcrumb.message.contains("Home"))
        XCTAssertTrue(breadcrumb.message.contains("Profile"))
        XCTAssertTrue(breadcrumb.message.contains("->"))
        XCTAssertEqual(breadcrumb.data["from"]?.value as? String, "Home")
        XCTAssertEqual(breadcrumb.data["to"]?.value as? String, "Profile")
    }

    func testNavigationFactoryWithNilFrom() {
        let breadcrumb = Breadcrumb.navigation(from: nil, to: "Settings")

        XCTAssertEqual(breadcrumb.type, .navigation)
        XCTAssertTrue(breadcrumb.message.contains("Settings"))
        XCTAssertTrue(breadcrumb.message.contains("->"))
        XCTAssertFalse(breadcrumb.message.contains("nil"))
    }

    func testUserFactory() {
        let breadcrumb = Breadcrumb.user("Button tapped", data: ["button_id": "submit"])

        XCTAssertEqual(breadcrumb.type, .user)
        XCTAssertEqual(breadcrumb.message, "Button tapped")
        XCTAssertEqual(breadcrumb.data["button_id"]?.value as? String, "submit")
    }

    func testUserFactoryDefaultData() {
        let breadcrumb = Breadcrumb.user("Tap")
        XCTAssertEqual(breadcrumb.type, .user)
        XCTAssertTrue(breadcrumb.data.isEmpty)
    }

    func testHttpFactoryWithAllParameters() {
        let breadcrumb = Breadcrumb.http(method: "POST", url: "https://api.test.com/data", statusCode: 201, duration: 1.5)

        XCTAssertEqual(breadcrumb.type, .http)
        XCTAssertTrue(breadcrumb.message.contains("POST"))
        XCTAssertTrue(breadcrumb.message.contains("https://api.test.com/data"))
        XCTAssertTrue(breadcrumb.message.contains("201"))
        XCTAssertEqual(breadcrumb.data["method"]?.value as? String, "POST")
        XCTAssertEqual(breadcrumb.data["url"]?.value as? String, "https://api.test.com/data")
        XCTAssertEqual(breadcrumb.data["status_code"]?.value as? Int, 201)
        XCTAssertEqual(breadcrumb.data["duration_ms"]?.value as? Int, 1500)
    }

    func testHttpFactoryWithoutOptionalParameters() {
        let breadcrumb = Breadcrumb.http(method: "GET", url: "https://example.com")

        XCTAssertEqual(breadcrumb.type, .http)
        XCTAssertTrue(breadcrumb.message.contains("GET"))
        XCTAssertTrue(breadcrumb.message.contains("https://example.com"))
        XCTAssertNil(breadcrumb.data["status_code"])
        XCTAssertNil(breadcrumb.data["duration_ms"])
    }

    func testHttpFactoryWithStatusCodeOnly() {
        let breadcrumb = Breadcrumb.http(method: "DELETE", url: "https://api.com/resource", statusCode: 404)

        XCTAssertTrue(breadcrumb.message.contains("404"))
        XCTAssertEqual(breadcrumb.data["status_code"]?.value as? Int, 404)
        XCTAssertNil(breadcrumb.data["duration_ms"])
    }

    func testStateFactory() {
        let breadcrumb = Breadcrumb.state("App backgrounded", data: ["reason": "user"])

        XCTAssertEqual(breadcrumb.type, .state)
        XCTAssertEqual(breadcrumb.message, "App backgrounded")
        XCTAssertEqual(breadcrumb.data["reason"]?.value as? String, "user")
    }

    func testStateFactoryDefaultData() {
        let breadcrumb = Breadcrumb.state("State changed")
        XCTAssertTrue(breadcrumb.data.isEmpty)
    }

    func testSystemFactory() {
        let breadcrumb = Breadcrumb.system("Low memory warning", data: ["available_mb": 50])

        XCTAssertEqual(breadcrumb.type, .system)
        XCTAssertEqual(breadcrumb.message, "Low memory warning")
        XCTAssertEqual(breadcrumb.data["available_mb"]?.value as? Int, 50)
    }

    func testSystemFactoryDefaultData() {
        let breadcrumb = Breadcrumb.system("System event")
        XCTAssertTrue(breadcrumb.data.isEmpty)
    }

    func testErrorFactory() {
        let breadcrumb = Breadcrumb.error("Network timeout", data: ["retry_count": 3])

        XCTAssertEqual(breadcrumb.type, .error)
        XCTAssertEqual(breadcrumb.message, "Network timeout")
        XCTAssertEqual(breadcrumb.data["retry_count"]?.value as? Int, 3)
    }

    func testErrorFactoryDefaultData() {
        let breadcrumb = Breadcrumb.error("Something failed")
        XCTAssertTrue(breadcrumb.data.isEmpty)
    }
}

// MARK: - MessageLevel Tests

final class MessageLevelTests: XCTestCase {

    func testAllCasesRawValues() {
        XCTAssertEqual(MessageLevel.debug.rawValue, "debug")
        XCTAssertEqual(MessageLevel.info.rawValue, "info")
        XCTAssertEqual(MessageLevel.warning.rawValue, "warning")
        XCTAssertEqual(MessageLevel.error.rawValue, "error")
        XCTAssertEqual(MessageLevel.fatal.rawValue, "fatal")
    }

    func testFromStringLowercase() {
        XCTAssertEqual(MessageLevel.from("debug"), .debug)
        XCTAssertEqual(MessageLevel.from("info"), .info)
        XCTAssertEqual(MessageLevel.from("warning"), .warning)
        XCTAssertEqual(MessageLevel.from("error"), .error)
        XCTAssertEqual(MessageLevel.from("fatal"), .fatal)
    }

    func testFromStringUppercase() {
        XCTAssertEqual(MessageLevel.from("DEBUG"), .debug)
        XCTAssertEqual(MessageLevel.from("INFO"), .info)
        XCTAssertEqual(MessageLevel.from("WARNING"), .warning)
        XCTAssertEqual(MessageLevel.from("ERROR"), .error)
        XCTAssertEqual(MessageLevel.from("FATAL"), .fatal)
    }

    func testFromStringMixedCase() {
        XCTAssertEqual(MessageLevel.from("Debug"), .debug)
        XCTAssertEqual(MessageLevel.from("Warning"), .warning)
        XCTAssertEqual(MessageLevel.from("Fatal"), .fatal)
    }

    func testFromStringInvalidDefaultsToInfo() {
        XCTAssertEqual(MessageLevel.from("unknown"), .info)
        XCTAssertEqual(MessageLevel.from(""), .info)
        XCTAssertEqual(MessageLevel.from("warn"), .info) // "warn" is not a MessageLevel case
        XCTAssertEqual(MessageLevel.from("critical"), .info)
    }
}

// MARK: - LogLevel Tests

final class LogLevelTests: XCTestCase {

    func testAllCasesRawValues() {
        XCTAssertEqual(LogLevel.trace.rawValue, "trace")
        XCTAssertEqual(LogLevel.debug.rawValue, "debug")
        XCTAssertEqual(LogLevel.info.rawValue, "info")
        XCTAssertEqual(LogLevel.warn.rawValue, "warn")
        XCTAssertEqual(LogLevel.error.rawValue, "error")
        XCTAssertEqual(LogLevel.fatal.rawValue, "fatal")
    }

    func testLogLevelCodableRoundTrip() throws {
        for level: LogLevel in [.trace, .debug, .info, .warn, .error, .fatal] {
            let encoded = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(LogLevel.self, from: encoded)
            XCTAssertEqual(decoded, level)
        }
    }

    func testLogLevelEncodesToRawValue() throws {
        let encoded = try JSONEncoder().encode(LogLevel.warn)
        let string = String(data: encoded, encoding: .utf8)
        XCTAssertEqual(string, "\"warn\"")
    }
}

// MARK: - LogEntry Tests

final class LogEntryTests: XCTestCase {

    func testLogEntryDefaultValues() {
        let before = Date()
        let entry = LogEntry(message: "Hello")
        let after = Date()

        XCTAssertEqual(entry.message, "Hello")
        XCTAssertEqual(entry.level, .info)
        XCTAssertTrue(entry.timestamp >= before)
        XCTAssertTrue(entry.timestamp <= after)
        XCTAssertNil(entry.metadata)
        XCTAssertNil(entry.userId)
    }

    func testLogEntryCustomValues() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let entry = LogEntry(
            message: "Error occurred",
            level: .error,
            timestamp: date,
            metadata: ["key": "value"],
            userId: "user-123"
        )

        XCTAssertEqual(entry.message, "Error occurred")
        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(entry.timestamp, date)
        XCTAssertEqual(entry.metadata?["key"]?.value as? String, "value")
        XCTAssertEqual(entry.userId, "user-123")
    }

    func testLogEntryAllLevels() {
        for level: LogLevel in [.trace, .debug, .info, .warn, .error, .fatal] {
            let entry = LogEntry(message: "test", level: level)
            XCTAssertEqual(entry.level, level)
        }
    }

    func testLogEntryEncodeDecodeRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1700000000.123)
        let original = LogEntry(
            message: "Test log",
            level: .warn,
            timestamp: date,
            metadata: ["count": 42, "name": "test"],
            userId: "user-456"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LogEntry.self, from: data)

        XCTAssertEqual(decoded.message, original.message)
        XCTAssertEqual(decoded.level, original.level)
        XCTAssertEqual(decoded.userId, original.userId)
        // Timestamp should be close (ISO8601 fractional seconds precision)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, original.timestamp.timeIntervalSince1970, accuracy: 0.01)
    }

    func testLogEntryEncodeDecodeWithNilMetadata() throws {
        let original = LogEntry(message: "simple")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LogEntry.self, from: data)

        XCTAssertEqual(decoded.message, "simple")
        XCTAssertEqual(decoded.level, .info)
        XCTAssertNil(decoded.metadata)
        XCTAssertNil(decoded.userId)
    }

    func testLogEntryEncodeDecodeWithNilUserId() throws {
        let original = LogEntry(message: "no user", level: .debug, userId: nil)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LogEntry.self, from: data)

        XCTAssertNil(decoded.userId)
    }

    func testLogEntryEncodesTimestampAsISO8601() throws {
        let entry = LogEntry(message: "test", timestamp: Date(timeIntervalSince1970: 1700000000))
        let data = try JSONEncoder().encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let timestampString = json?["timestamp"] as? String
        XCTAssertNotNil(timestampString)
        // ISO8601 format should contain 'T' and 'Z'
        XCTAssertTrue(timestampString?.contains("T") ?? false)
    }

    func testLogEntryEncodesLevelAsRawValue() throws {
        let entry = LogEntry(message: "test", level: .fatal)
        let data = try JSONEncoder().encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["level"] as? String, "fatal")
    }

    func testLogEntryWithMetadataTypes() throws {
        let entry = LogEntry(
            message: "types",
            metadata: ["string": "hello", "int": 42, "double": 3.14, "bool": true]
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(LogEntry.self, from: data)

        XCTAssertEqual(decoded.metadata?["string"]?.value as? String, "hello")
        XCTAssertEqual(decoded.metadata?["int"]?.value as? Int, 42)
    }
}

// MARK: - RiviumTraceError Tests

final class RiviumTraceErrorTests: XCTestCase {

    // MARK: Init Defaults

    func testErrorDefaultValues() {
        let error = RiviumTraceError(message: "Something failed")

        XCTAssertEqual(error.message, "Something failed")
        XCTAssertNil(error.stackTrace)
        XCTAssertEqual(error.platform, "ios")
        XCTAssertEqual(error.environment, "production")
        XCTAssertNil(error.releaseVersion)
        XCTAssertTrue(error.timestamp > 0)
        XCTAssertNil(error.userAgent)
        XCTAssertTrue(error.breadcrumbs.isEmpty)
        XCTAssertTrue(error.extra.isEmpty)
        XCTAssertEqual(error.level, MessageLevel.error.rawValue)
        XCTAssertTrue(error.tags.isEmpty)
        XCTAssertNil(error.url)
    }

    func testErrorCustomValues() {
        let error = RiviumTraceError(
            message: "Custom error",
            stackTrace: "frame 0: main()\nframe 1: start()",
            platform: "ios",
            environment: "staging",
            releaseVersion: "2.0.0",
            timestamp: 1700000000000,
            userAgent: "TestAgent/1.0",
            breadcrumbs: [["message": "crumb"]],
            extra: ["key": "val"],
            level: "fatal",
            tags: ["env": "test"],
            url: "https://app.example.com"
        )

        XCTAssertEqual(error.message, "Custom error")
        XCTAssertEqual(error.stackTrace, "frame 0: main()\nframe 1: start()")
        XCTAssertEqual(error.platform, "ios")
        XCTAssertEqual(error.environment, "staging")
        XCTAssertEqual(error.releaseVersion, "2.0.0")
        XCTAssertEqual(error.timestamp, 1700000000000)
        XCTAssertEqual(error.userAgent, "TestAgent/1.0")
        XCTAssertEqual(error.breadcrumbs.count, 1)
        XCTAssertEqual(error.extra["key"] as? String, "val")
        XCTAssertEqual(error.level, "fatal")
        XCTAssertEqual(error.tags["env"], "test")
        XCTAssertEqual(error.url, "https://app.example.com")
    }

    // MARK: toDictionary

    func testToDictionaryRequiredFields() {
        let error = RiviumTraceError(message: "test")
        let dict = error.toDictionary()

        XCTAssertEqual(dict["message"] as? String, "test")
        XCTAssertEqual(dict["platform"] as? String, "ios")
        XCTAssertEqual(dict["environment"] as? String, "production")
        XCTAssertNotNil(dict["timestamp"])
        XCTAssertEqual(dict["level"] as? String, "error")
        XCTAssertNotNil(dict["tags"])
        XCTAssertNotNil(dict["breadcrumbs"])
        XCTAssertNotNil(dict["extra"])
    }

    func testToDictionaryOmitsNilStackTrace() {
        let error = RiviumTraceError(message: "test", stackTrace: nil)
        let dict = error.toDictionary()
        XCTAssertNil(dict["stack_trace"])
    }

    func testToDictionaryIncludesStackTrace() {
        let error = RiviumTraceError(message: "test", stackTrace: "frame0\nframe1")
        let dict = error.toDictionary()
        XCTAssertEqual(dict["stack_trace"] as? String, "frame0\nframe1")
    }

    func testToDictionaryOmitsNilReleaseVersion() {
        let error = RiviumTraceError(message: "test", releaseVersion: nil)
        let dict = error.toDictionary()
        XCTAssertNil(dict["release_version"])
    }

    func testToDictionaryIncludesReleaseVersion() {
        let error = RiviumTraceError(message: "test", releaseVersion: "1.0.0")
        let dict = error.toDictionary()
        XCTAssertEqual(dict["release_version"] as? String, "1.0.0")
    }

    func testToDictionaryOmitsNilUserAgent() {
        let error = RiviumTraceError(message: "test", userAgent: nil)
        let dict = error.toDictionary()
        XCTAssertNil(dict["user_agent"])
    }

    func testToDictionaryIncludesUserAgent() {
        let error = RiviumTraceError(message: "test", userAgent: "Agent/1.0")
        let dict = error.toDictionary()
        XCTAssertEqual(dict["user_agent"] as? String, "Agent/1.0")
    }

    func testToDictionaryOmitsNilUrl() {
        let error = RiviumTraceError(message: "test", url: nil)
        let dict = error.toDictionary()
        XCTAssertNil(dict["url"])
    }

    func testToDictionaryIncludesUrl() {
        let error = RiviumTraceError(message: "test", url: "https://app.com/page")
        let dict = error.toDictionary()
        XCTAssertEqual(dict["url"] as? String, "https://app.com/page")
    }

    func testToDictionaryIncludesTags() {
        let error = RiviumTraceError(message: "test", tags: ["version": "1.0", "build": "42"])
        let dict = error.toDictionary()
        let tags = dict["tags"] as? [String: String]
        XCTAssertEqual(tags?["version"], "1.0")
        XCTAssertEqual(tags?["build"], "42")
    }

    func testToDictionaryIncludesBreadcrumbs() {
        let crumbs: [[String: Any]] = [["message": "step1"], ["message": "step2"]]
        let error = RiviumTraceError(message: "test", breadcrumbs: crumbs)
        let dict = error.toDictionary()
        let breadcrumbs = dict["breadcrumbs"] as? [[String: Any]]
        XCTAssertEqual(breadcrumbs?.count, 2)
    }

    func testToDictionaryIncludesExtra() {
        let error = RiviumTraceError(message: "test", extra: ["detail": "more info"])
        let dict = error.toDictionary()
        let extra = dict["extra"] as? [String: Any]
        XCTAssertEqual(extra?["detail"] as? String, "more info")
    }

    // MARK: Factory: from(error:)

    func testFromErrorCapturesMessage() {
        let nsError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test failure"])
        let error = RiviumTraceError.from(error: nsError)

        XCTAssertEqual(error.message, "Test failure")
    }

    func testFromErrorCustomMessage() {
        let nsError = NSError(domain: "TestDomain", code: 42, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError, message: "Custom message")

        XCTAssertEqual(error.message, "Custom message")
    }

    func testFromErrorCapturesStackTrace() {
        let nsError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError)

        XCTAssertNotNil(error.stackTrace)
        XCTAssertFalse(error.stackTrace?.isEmpty ?? true)
    }

    func testFromErrorCapturesNSErrorDomain() {
        let nsError = NSError(domain: "com.example.test", code: 404, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError)

        XCTAssertEqual(error.extra["error_domain"] as? String, "com.example.test")
    }

    func testFromErrorCapturesNSErrorCode() {
        let nsError = NSError(domain: "TestDomain", code: 500, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError)

        XCTAssertEqual(error.extra["error_code"] as? Int, 500)
    }

    func testFromErrorMergesExtraData() {
        let nsError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError, extra: ["custom_key": "custom_val"])

        XCTAssertEqual(error.extra["custom_key"] as? String, "custom_val")
        // Should still have error_domain and error_code
        XCTAssertNotNil(error.extra["error_domain"])
        XCTAssertNotNil(error.extra["error_code"])
    }

    func testFromErrorSetsEnvironment() {
        let nsError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError, environment: "staging")

        XCTAssertEqual(error.environment, "staging")
    }

    func testFromErrorDefaultEnvironment() {
        let nsError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError)

        XCTAssertEqual(error.environment, "production")
    }

    func testFromErrorSetsReleaseVersion() {
        let nsError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError, releaseVersion: "3.0.0")

        XCTAssertEqual(error.releaseVersion, "3.0.0")
    }

    func testFromErrorSetsTags() {
        let nsError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError, tags: ["module": "auth"])

        XCTAssertEqual(error.tags["module"], "auth")
    }

    func testFromErrorPlatformIsIos() {
        let nsError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError)

        XCTAssertEqual(error.platform, "ios")
    }

    func testFromErrorCapturesErrorType() {
        let nsError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let error = RiviumTraceError.from(error: nsError)

        XCTAssertNotNil(error.extra["error_type"])
    }

    // MARK: Factory: message(_:level:)

    func testMessageFactoryBasic() {
        let error = RiviumTraceError.message("Info message")

        XCTAssertEqual(error.message, "Info message")
        XCTAssertEqual(error.level, MessageLevel.info.rawValue)
        XCTAssertNil(error.stackTrace)
    }

    func testMessageFactoryWithLevel() {
        let error = RiviumTraceError.message("Warning!", level: .warning)

        XCTAssertEqual(error.message, "Warning!")
        XCTAssertEqual(error.level, "warning")
        XCTAssertNil(error.stackTrace)
    }

    func testMessageFactoryNoStackTrace() {
        let error = RiviumTraceError.message("test", level: .fatal)
        XCTAssertNil(error.stackTrace)
    }

    func testMessageFactoryWithEnvironment() {
        let error = RiviumTraceError.message("test", environment: "development")
        XCTAssertEqual(error.environment, "development")
    }

    func testMessageFactoryWithAllLevels() {
        for level: MessageLevel in [.debug, .info, .warning, .error, .fatal] {
            let error = RiviumTraceError.message("test", level: level)
            XCTAssertEqual(error.level, level.rawValue)
        }
    }

    func testMessageFactoryWithBreadcrumbs() {
        let crumbs = [Breadcrumb(message: "step1"), Breadcrumb(message: "step2")]
        let error = RiviumTraceError.message("test", breadcrumbs: crumbs)
        XCTAssertEqual(error.breadcrumbs.count, 2)
    }

    func testMessageFactoryWithExtra() {
        let error = RiviumTraceError.message("test", extra: ["key": "val"])
        XCTAssertEqual(error.extra["key"] as? String, "val")
    }

    func testMessageFactoryWithTags() {
        let error = RiviumTraceError.message("test", tags: ["tag1": "v1"])
        XCTAssertEqual(error.tags["tag1"], "v1")
    }

    // MARK: Factory: nativeCrash

    func testNativeCrashFactoryMessage() {
        let error = RiviumTraceError.nativeCrash(crashInfo: "SIGSEGV at 0x0")

        XCTAssertTrue(error.message.contains("Native crash"))
        XCTAssertTrue(error.message.contains("previous session"))
    }

    func testNativeCrashFactoryLevel() {
        let error = RiviumTraceError.nativeCrash(crashInfo: "crash")
        XCTAssertEqual(error.level, MessageLevel.fatal.rawValue)
    }

    func testNativeCrashFactoryStackTrace() {
        let error = RiviumTraceError.nativeCrash(crashInfo: "SIGABRT info")

        XCTAssertNotNil(error.stackTrace)
        XCTAssertTrue(error.stackTrace?.contains("SIGABRT info") ?? false)
    }

    func testNativeCrashFactoryExtraContainsCrashInfo() {
        let error = RiviumTraceError.nativeCrash(crashInfo: "crash details")
        XCTAssertEqual(error.extra["crash_info"] as? String, "crash details")
        XCTAssertEqual(error.extra["error_type"] as? String, "native_crash")
    }

    func testNativeCrashFactoryWithSignal() {
        let error = RiviumTraceError.nativeCrash(crashInfo: "info", signal: "SIGSEGV")
        XCTAssertEqual(error.extra["signal"] as? String, "SIGSEGV")
    }

    func testNativeCrashFactoryWithTimeSinceCrash() {
        let error = RiviumTraceError.nativeCrash(crashInfo: "info", timeSinceCrashSeconds: 60)
        XCTAssertEqual(error.extra["time_since_crash_seconds"] as? Int64, 60)
    }

    func testNativeCrashFactoryWithEnvironment() {
        let error = RiviumTraceError.nativeCrash(crashInfo: "info", environment: "staging")
        XCTAssertEqual(error.environment, "staging")
    }

    func testNativeCrashFactoryDefaultEnvironment() {
        let error = RiviumTraceError.nativeCrash(crashInfo: "info")
        XCTAssertEqual(error.environment, "production")
    }

    // MARK: Factory: anr

    func testAnrFactoryMessage() {
        let error = RiviumTraceError.anr(stackTrace: "main thread stack", anrDurationMs: 6000)

        XCTAssertTrue(error.message.contains("ANR"))
        XCTAssertTrue(error.message.contains("6000"))
    }

    func testAnrFactoryLevel() {
        let error = RiviumTraceError.anr(stackTrace: "stack", anrDurationMs: 5000)
        XCTAssertEqual(error.level, MessageLevel.error.rawValue)
    }

    func testAnrFactoryStackTrace() {
        let error = RiviumTraceError.anr(stackTrace: "main thread blocked", anrDurationMs: 5000)
        XCTAssertEqual(error.stackTrace, "main thread blocked")
    }

    func testAnrFactoryExtraContainsDuration() {
        let error = RiviumTraceError.anr(stackTrace: "stack", anrDurationMs: 8000)
        XCTAssertEqual(error.extra["anr_duration_ms"] as? Int64, 8000)
        XCTAssertEqual(error.extra["error_type"] as? String, "anr")
    }

    func testAnrFactoryWithEnvironment() {
        let error = RiviumTraceError.anr(stackTrace: "stack", environment: "development", anrDurationMs: 5000)
        XCTAssertEqual(error.environment, "development")
    }

    func testAnrFactoryDefaultEnvironment() {
        let error = RiviumTraceError.anr(stackTrace: "stack", anrDurationMs: 5000)
        XCTAssertEqual(error.environment, "production")
    }
}

// MARK: - PerformanceSpan Tests

final class PerformanceSpanTests: XCTestCase {

    // MARK: ID Generation

    func testGenerateTraceIdLength() {
        let traceId = PerformanceSpan.generateTraceId()
        XCTAssertEqual(traceId.count, 32)
    }

    func testGenerateTraceIdIsLowercaseHex() {
        let traceId = PerformanceSpan.generateTraceId()
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(traceId.unicodeScalars.allSatisfy { hexCharacterSet.contains($0) })
    }

    func testGenerateTraceIdUniqueness() {
        let ids = (0..<100).map { _ in PerformanceSpan.generateTraceId() }
        let uniqueIds = Set(ids)
        XCTAssertEqual(uniqueIds.count, 100)
    }

    func testGenerateSpanIdLength() {
        let spanId = PerformanceSpan.generateSpanId()
        XCTAssertEqual(spanId.count, 16)
    }

    func testGenerateSpanIdIsLowercaseHex() {
        let spanId = PerformanceSpan.generateSpanId()
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(spanId.unicodeScalars.allSatisfy { hexCharacterSet.contains($0) })
    }

    func testGenerateSpanIdUniqueness() {
        let ids = (0..<100).map { _ in PerformanceSpan.generateSpanId() }
        let uniqueIds = Set(ids)
        XCTAssertEqual(uniqueIds.count, 100)
    }

    // MARK: fromHttpRequest

    func testHttpRequestSpanBasic() {
        let start = Date()
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET",
            url: "https://api.example.com/users",
            statusCode: 200,
            durationMs: 150.0,
            startTime: start
        )

        XCTAssertTrue(span.operation.contains("GET"))
        XCTAssertEqual(span.operationType, "http")
        XCTAssertEqual(span.httpMethod, "GET")
        XCTAssertEqual(span.httpUrl, "https://api.example.com/users")
        XCTAssertEqual(span.httpStatusCode, 200)
        XCTAssertEqual(span.durationMs, 150.0)
        XCTAssertEqual(span.startTime, start)
        XCTAssertEqual(span.platform, "ios")
        XCTAssertEqual(span.status, "ok")
        XCTAssertNotNil(span.traceId)
        XCTAssertNotNil(span.spanId)
        XCTAssertNil(span.parentSpanId)
    }

    func testHttpRequestSpanStatusOkFor200() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.com", statusCode: 200,
            durationMs: 100, startTime: Date()
        )
        XCTAssertEqual(span.status, "ok")
    }

    func testHttpRequestSpanStatusOkFor201() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "POST", url: "https://api.com", statusCode: 201,
            durationMs: 100, startTime: Date()
        )
        XCTAssertEqual(span.status, "ok")
    }

    func testHttpRequestSpanStatusOkFor301() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.com", statusCode: 301,
            durationMs: 100, startTime: Date()
        )
        XCTAssertEqual(span.status, "ok")
    }

    func testHttpRequestSpanStatusOkFor399() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.com", statusCode: 399,
            durationMs: 100, startTime: Date()
        )
        XCTAssertEqual(span.status, "ok")
    }

    func testHttpRequestSpanStatusErrorFor400() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.com", statusCode: 400,
            durationMs: 100, startTime: Date()
        )
        XCTAssertEqual(span.status, "error")
    }

    func testHttpRequestSpanStatusErrorFor404() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.com", statusCode: 404,
            durationMs: 100, startTime: Date()
        )
        XCTAssertEqual(span.status, "error")
    }

    func testHttpRequestSpanStatusErrorFor500() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.com", statusCode: 500,
            durationMs: 100, startTime: Date()
        )
        XCTAssertEqual(span.status, "error")
    }

    func testHttpRequestSpanStatusErrorForNilStatusCode() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.com", statusCode: nil,
            durationMs: 100, startTime: Date()
        )
        XCTAssertEqual(span.status, "error")
    }

    func testHttpRequestSpanExtractsHost() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.example.com/v1/users",
            statusCode: 200, durationMs: 100, startTime: Date()
        )
        XCTAssertEqual(span.httpHost, "api.example.com")
    }

    func testHttpRequestSpanHostNilForInvalidUrl() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "not a url",
            statusCode: 200, durationMs: 100, startTime: Date()
        )
        XCTAssertNil(span.httpHost)
    }

    func testHttpRequestSpanEndTime() {
        let start = Date(timeIntervalSince1970: 1000)
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.com",
            statusCode: 200, durationMs: 500, startTime: start
        )
        let expectedEnd = start.addingTimeInterval(0.5)
        XCTAssertEqual(span.endTime.timeIntervalSince1970, expectedEnd.timeIntervalSince1970, accuracy: 0.001)
    }

    func testHttpRequestSpanWithCustomTraceId() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.com",
            statusCode: 200, durationMs: 100, startTime: Date(),
            traceId: "custom_trace_id_123"
        )
        XCTAssertEqual(span.traceId, "custom_trace_id_123")
    }

    func testHttpRequestSpanWithEnvironment() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "GET", url: "https://api.com",
            statusCode: 200, durationMs: 100, startTime: Date(),
            environment: "staging"
        )
        XCTAssertEqual(span.environment, "staging")
    }

    // MARK: forDbQuery

    func testDbQuerySpanBasic() {
        let start = Date()
        let span = PerformanceSpan.forDbQuery(
            queryType: "SELECT",
            tableName: "users",
            durationMs: 25.0,
            startTime: start
        )

        XCTAssertTrue(span.operation.contains("SELECT"))
        XCTAssertTrue(span.operation.contains("users"))
        XCTAssertEqual(span.operationType, "db")
        XCTAssertEqual(span.durationMs, 25.0)
        XCTAssertEqual(span.platform, "ios")
        XCTAssertEqual(span.status, "ok")
        XCTAssertNil(span.httpMethod)
        XCTAssertNil(span.httpUrl)
        XCTAssertNil(span.httpStatusCode)
        XCTAssertNil(span.httpHost)
    }

    func testDbQuerySpanTagsIncludeTable() {
        let span = PerformanceSpan.forDbQuery(
            queryType: "INSERT",
            tableName: "orders",
            durationMs: 10,
            startTime: Date()
        )
        XCTAssertEqual(span.tags["db_table"], "orders")
        XCTAssertEqual(span.tags["query_type"], "INSERT")
    }

    func testDbQuerySpanWithRowsAffected() {
        let span = PerformanceSpan.forDbQuery(
            queryType: "UPDATE",
            tableName: "items",
            durationMs: 15,
            startTime: Date(),
            rowsAffected: 42
        )
        XCTAssertEqual(span.tags["rows_affected"], "42")
    }

    func testDbQuerySpanWithErrorMessage() {
        let span = PerformanceSpan.forDbQuery(
            queryType: "DELETE",
            tableName: "logs",
            durationMs: 5,
            startTime: Date(),
            errorMessage: "constraint violation"
        )
        XCTAssertEqual(span.status, "error")
        XCTAssertEqual(span.errorMessage, "constraint violation")
    }

    func testDbQuerySpanStatusOkWithoutError() {
        let span = PerformanceSpan.forDbQuery(
            queryType: "SELECT",
            tableName: "products",
            durationMs: 10,
            startTime: Date()
        )
        XCTAssertEqual(span.status, "ok")
        XCTAssertNil(span.errorMessage)
    }

    func testDbQuerySpanMergesCustomTags() {
        let span = PerformanceSpan.forDbQuery(
            queryType: "SELECT",
            tableName: "users",
            durationMs: 10,
            startTime: Date(),
            tags: ["custom_tag": "custom_value"]
        )
        XCTAssertEqual(span.tags["custom_tag"], "custom_value")
        XCTAssertEqual(span.tags["db_table"], "users")
        XCTAssertEqual(span.tags["query_type"], "SELECT")
    }

    // MARK: custom

    func testCustomSpanBasic() {
        let start = Date()
        let span = PerformanceSpan.custom(
            operation: "image_processing",
            durationMs: 300,
            startTime: start
        )

        XCTAssertEqual(span.operation, "image_processing")
        XCTAssertEqual(span.operationType, "custom")
        XCTAssertEqual(span.status, "ok")
        XCTAssertEqual(span.durationMs, 300)
        XCTAssertEqual(span.platform, "ios")
        XCTAssertNil(span.httpMethod)
    }

    func testCustomSpanWithOperationType() {
        let span = PerformanceSpan.custom(
            operation: "render_frame",
            durationMs: 16,
            startTime: Date(),
            operationType: "rendering"
        )
        XCTAssertEqual(span.operationType, "rendering")
    }

    func testCustomSpanWithCustomStatus() {
        let span = PerformanceSpan.custom(
            operation: "task",
            durationMs: 100,
            startTime: Date(),
            status: "cancelled"
        )
        XCTAssertEqual(span.status, "cancelled")
    }

    func testCustomSpanWithEnvironment() {
        let span = PerformanceSpan.custom(
            operation: "task",
            durationMs: 100,
            startTime: Date(),
            environment: "development"
        )
        XCTAssertEqual(span.environment, "development")
    }

    func testCustomSpanWithErrorMessage() {
        let span = PerformanceSpan.custom(
            operation: "task",
            durationMs: 100,
            startTime: Date(),
            errorMessage: "timeout"
        )
        XCTAssertEqual(span.errorMessage, "timeout")
    }

    // MARK: toDictionary

    func testToDictionaryRequiredFields() {
        let start = Date()
        let span = PerformanceSpan.custom(
            operation: "test_op",
            durationMs: 50,
            startTime: start
        )
        let dict = span.toDictionary()

        XCTAssertEqual(dict["operation"] as? String, "test_op")
        XCTAssertEqual(dict["operation_type"] as? String, "custom")
        XCTAssertEqual(dict["duration_ms"] as? Double, 50.0)
        XCTAssertNotNil(dict["start_time"])
        XCTAssertNotNil(dict["end_time"])
        XCTAssertEqual(dict["platform"] as? String, "ios")
        XCTAssertEqual(dict["status"] as? String, "ok")
    }

    func testToDictionaryIncludesTraceIdAndSpanId() {
        let span = PerformanceSpan.custom(operation: "op", durationMs: 10, startTime: Date())
        let dict = span.toDictionary()

        XCTAssertNotNil(dict["trace_id"])
        XCTAssertNotNil(dict["span_id"])
    }

    func testToDictionaryHttpFieldsPresent() {
        let span = PerformanceSpan.fromHttpRequest(
            method: "POST", url: "https://api.com/data",
            statusCode: 201, durationMs: 100, startTime: Date()
        )
        let dict = span.toDictionary()

        XCTAssertEqual(dict["http_method"] as? String, "POST")
        XCTAssertEqual(dict["http_url"] as? String, "https://api.com/data")
        XCTAssertEqual(dict["http_status_code"] as? Int, 201)
        XCTAssertNotNil(dict["http_host"])
    }

    func testToDictionaryHttpFieldsAbsentForCustomSpan() {
        let span = PerformanceSpan.custom(operation: "op", durationMs: 10, startTime: Date())
        let dict = span.toDictionary()

        XCTAssertNil(dict["http_method"])
        XCTAssertNil(dict["http_url"])
        XCTAssertNil(dict["http_status_code"])
        XCTAssertNil(dict["http_host"])
    }

    func testToDictionaryOmitsNilEnvironment() {
        let span = PerformanceSpan.custom(operation: "op", durationMs: 10, startTime: Date())
        let dict = span.toDictionary()
        XCTAssertNil(dict["environment"])
    }

    func testToDictionaryIncludesEnvironment() {
        let span = PerformanceSpan.custom(
            operation: "op", durationMs: 10, startTime: Date(), environment: "prod"
        )
        let dict = span.toDictionary()
        XCTAssertEqual(dict["environment"] as? String, "prod")
    }

    func testToDictionaryOmitsEmptyTags() {
        let span = PerformanceSpan.custom(operation: "op", durationMs: 10, startTime: Date())
        let dict = span.toDictionary()
        XCTAssertNil(dict["tags"])
    }

    func testToDictionaryIncludesNonEmptyTags() {
        let span = PerformanceSpan.custom(
            operation: "op", durationMs: 10, startTime: Date(), tags: ["k": "v"]
        )
        let dict = span.toDictionary()
        let tags = dict["tags"] as? [String: String]
        XCTAssertEqual(tags?["k"], "v")
    }

    func testToDictionaryOmitsEmptyMetadata() {
        let span = PerformanceSpan.custom(operation: "op", durationMs: 10, startTime: Date())
        let dict = span.toDictionary()
        XCTAssertNil(dict["metadata"])
    }

    func testToDictionaryStartTimeISO8601Format() {
        let span = PerformanceSpan.custom(operation: "op", durationMs: 10, startTime: Date())
        let dict = span.toDictionary()
        let startTimeStr = dict["start_time"] as? String
        XCTAssertNotNil(startTimeStr)
        XCTAssertTrue(startTimeStr?.contains("T") ?? false)
    }
}

// MARK: - BreadcrumbService Tests

final class BreadcrumbServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BreadcrumbService.shared.clear()
        usleep(100_000) // Wait for async barrier clear
        BreadcrumbService.shared.setMaxBreadcrumbs(20)
        usleep(100_000)
    }

    override func tearDown() {
        BreadcrumbService.shared.clear()
        usleep(100_000)
        BreadcrumbService.shared.setMaxBreadcrumbs(20)
        usleep(100_000)
        super.tearDown()
    }

    // MARK: Singleton

    func testSharedInstanceIsSingleton() {
        let a = BreadcrumbService.shared
        let b = BreadcrumbService.shared
        XCTAssertTrue(a === b)
    }

    // MARK: Add & Retrieve

    func testAddBreadcrumbObject() {
        let breadcrumb = Breadcrumb(message: "Direct add", type: .error)
        BreadcrumbService.shared.add(breadcrumb)
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.message, "Direct add")
        XCTAssertEqual(result.first?.type, .error)
    }

    func testAddBreadcrumbByMessage() {
        BreadcrumbService.shared.add("Simple message")
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.message, "Simple message")
        XCTAssertEqual(result.first?.type, .info)
    }

    func testAddBreadcrumbByMessageWithType() {
        BreadcrumbService.shared.add("Error msg", type: .error)
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.first?.type, .error)
    }

    func testAddBreadcrumbByMessageWithData() {
        BreadcrumbService.shared.add("With data", type: .info, data: ["key": "value"])
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.first?.data["key"]?.value as? String, "value")
    }

    func testAddMultipleBreadcrumbs() {
        BreadcrumbService.shared.add("First")
        BreadcrumbService.shared.add("Second")
        BreadcrumbService.shared.add("Third")
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].message, "First")
        XCTAssertEqual(result[1].message, "Second")
        XCTAssertEqual(result[2].message, "Third")
    }

    // MARK: Convenience Methods

    func testAddNavigation() {
        BreadcrumbService.shared.addNavigation(from: "Home", to: "Profile")
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .navigation)
        XCTAssertTrue(result.first?.message.contains("Home") ?? false)
        XCTAssertTrue(result.first?.message.contains("Profile") ?? false)
    }

    func testAddNavigationWithNilFrom() {
        BreadcrumbService.shared.addNavigation(from: nil, to: "Settings")
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.message.contains("Settings") ?? false)
    }

    func testAddUser() {
        BreadcrumbService.shared.addUser("Tapped submit", data: ["form": "login"])
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .user)
        XCTAssertEqual(result.first?.message, "Tapped submit")
    }

    func testAddHttp() {
        BreadcrumbService.shared.addHttp(method: "GET", url: "https://api.com", statusCode: 200, duration: 0.5)
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .http)
        XCTAssertTrue(result.first?.message.contains("GET") ?? false)
        XCTAssertTrue(result.first?.message.contains("200") ?? false)
    }

    func testAddHttpWithoutOptionalParams() {
        BreadcrumbService.shared.addHttp(method: "POST", url: "https://api.com")
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .http)
    }

    func testAddState() {
        BreadcrumbService.shared.addState("App entered background")
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .state)
        XCTAssertEqual(result.first?.message, "App entered background")
    }

    func testAddSystem() {
        BreadcrumbService.shared.addSystem("Memory warning")
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .system)
        XCTAssertEqual(result.first?.message, "Memory warning")
    }

    func testAddError() {
        BreadcrumbService.shared.addError("Network failed", data: ["code": 503])
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .error)
        XCTAssertEqual(result.first?.message, "Network failed")
    }

    // MARK: getBreadcrumbsAsDictionary

    func testGetBreadcrumbsAsDictionary() {
        BreadcrumbService.shared.add("msg1", type: .info)
        BreadcrumbService.shared.add("msg2", type: .error)
        usleep(100_000)

        let dicts = BreadcrumbService.shared.getBreadcrumbsAsDictionary()
        XCTAssertEqual(dicts.count, 2)
        XCTAssertEqual(dicts[0]["message"] as? String, "msg1")
        XCTAssertEqual(dicts[0]["type"] as? String, "info")
        XCTAssertEqual(dicts[1]["message"] as? String, "msg2")
        XCTAssertEqual(dicts[1]["type"] as? String, "error")
    }

    func testGetBreadcrumbsAsDictionaryEmpty() {
        let dicts = BreadcrumbService.shared.getBreadcrumbsAsDictionary()
        XCTAssertTrue(dicts.isEmpty)
    }

    // MARK: Clear

    func testClearBreadcrumbs() {
        BreadcrumbService.shared.add("msg1")
        BreadcrumbService.shared.add("msg2")
        usleep(100_000)
        XCTAssertEqual(BreadcrumbService.shared.count, 2)

        BreadcrumbService.shared.clear()
        usleep(100_000)
        XCTAssertEqual(BreadcrumbService.shared.count, 0)
        XCTAssertTrue(BreadcrumbService.shared.getBreadcrumbs().isEmpty)
    }

    func testClearAlreadyEmptyIsNoOp() {
        BreadcrumbService.shared.clear()
        usleep(100_000)
        XCTAssertEqual(BreadcrumbService.shared.count, 0)
    }

    // MARK: Count

    func testCountReflectsAdditions() {
        XCTAssertEqual(BreadcrumbService.shared.count, 0)

        BreadcrumbService.shared.add("one")
        usleep(100_000)
        XCTAssertEqual(BreadcrumbService.shared.count, 1)

        BreadcrumbService.shared.add("two")
        usleep(100_000)
        XCTAssertEqual(BreadcrumbService.shared.count, 2)
    }

    // MARK: Max Breadcrumbs

    func testSetMaxBreadcrumbsTrimsExcess() {
        for i in 1...10 {
            BreadcrumbService.shared.add("Message \(i)")
        }
        usleep(100_000)
        XCTAssertEqual(BreadcrumbService.shared.count, 10)

        BreadcrumbService.shared.setMaxBreadcrumbs(5)
        usleep(100_000)
        XCTAssertEqual(BreadcrumbService.shared.count, 5)

        let breadcrumbs = BreadcrumbService.shared.getBreadcrumbs()
        // Oldest should be trimmed: Messages 1-5 gone, 6-10 remain
        XCTAssertEqual(breadcrumbs.first?.message, "Message 6")
        XCTAssertEqual(breadcrumbs.last?.message, "Message 10")
    }

    func testMaxBreadcrumbsEnforcedOnAdd() {
        BreadcrumbService.shared.setMaxBreadcrumbs(3)
        usleep(100_000)

        for i in 1...5 {
            BreadcrumbService.shared.add("Message \(i)")
        }
        usleep(100_000)

        let breadcrumbs = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(breadcrumbs.count, 3)
        XCTAssertEqual(breadcrumbs[0].message, "Message 3")
        XCTAssertEqual(breadcrumbs[1].message, "Message 4")
        XCTAssertEqual(breadcrumbs[2].message, "Message 5")
    }

    func testMaxBreadcrumbsExactLimit() {
        BreadcrumbService.shared.setMaxBreadcrumbs(5)
        usleep(100_000)

        for i in 1...5 {
            BreadcrumbService.shared.add("Message \(i)")
        }
        usleep(100_000)

        XCTAssertEqual(BreadcrumbService.shared.count, 5)
        XCTAssertEqual(BreadcrumbService.shared.getBreadcrumbs().first?.message, "Message 1")
    }

    func testMaxBreadcrumbsOnePastLimit() {
        BreadcrumbService.shared.setMaxBreadcrumbs(5)
        usleep(100_000)

        for i in 1...6 {
            BreadcrumbService.shared.add("Message \(i)")
        }
        usleep(100_000)

        let breadcrumbs = BreadcrumbService.shared.getBreadcrumbs()
        XCTAssertEqual(breadcrumbs.count, 5)
        XCTAssertEqual(breadcrumbs.first?.message, "Message 2")
        XCTAssertEqual(breadcrumbs.last?.message, "Message 6")
    }

    // MARK: Thread Safety

    func testConcurrentAddsDoNotCrash() {
        let expectation = XCTestExpectation(description: "Concurrent adds complete")
        expectation.expectedFulfillmentCount = 10

        BreadcrumbService.shared.setMaxBreadcrumbs(100)
        usleep(100_000)

        for i in 0..<10 {
            DispatchQueue.global().async {
                for j in 0..<10 {
                    BreadcrumbService.shared.add("Thread \(i) Message \(j)")
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        usleep(200_000)

        let count = BreadcrumbService.shared.count
        XCTAssertEqual(count, 100)
    }

    func testConcurrentReadsAndWritesDoNotCrash() {
        let expectation = XCTestExpectation(description: "Concurrent reads and writes complete")
        expectation.expectedFulfillmentCount = 20

        BreadcrumbService.shared.setMaxBreadcrumbs(100)
        usleep(100_000)

        for i in 0..<10 {
            DispatchQueue.global().async {
                for j in 0..<5 {
                    BreadcrumbService.shared.add("Write \(i)-\(j)")
                }
                expectation.fulfill()
            }
            DispatchQueue.global().async {
                _ = BreadcrumbService.shared.getBreadcrumbs()
                _ = BreadcrumbService.shared.count
                _ = BreadcrumbService.shared.getBreadcrumbsAsDictionary()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        // Test passes if no crash
    }

    // MARK: Order Preservation

    func testBreadcrumbOrderPreserved() {
        let messages = ["alpha", "beta", "gamma", "delta", "epsilon"]
        for msg in messages {
            BreadcrumbService.shared.add(msg)
        }
        usleep(100_000)

        let result = BreadcrumbService.shared.getBreadcrumbs().map { $0.message }
        XCTAssertEqual(result, messages)
    }

    // MARK: Mixed Types

    func testMixedBreadcrumbTypes() {
        BreadcrumbService.shared.addNavigation(from: "A", to: "B")
        BreadcrumbService.shared.addUser("tap")
        BreadcrumbService.shared.addHttp(method: "GET", url: "https://api.com", statusCode: 200)
        BreadcrumbService.shared.addState("bg")
        BreadcrumbService.shared.addSystem("mem")
        BreadcrumbService.shared.addError("err")
        BreadcrumbService.shared.add("info msg")
        usleep(100_000)

        let types = BreadcrumbService.shared.getBreadcrumbs().map { $0.type }
        XCTAssertEqual(types, [.navigation, .user, .http, .state, .system, .error, .info])
    }
}

// MARK: - DeviceInfo Tests

final class DeviceInfoTests: XCTestCase {

    func testSharedInstanceIsSingleton() {
        let a = DeviceInfo.shared
        let b = DeviceInfo.shared
        XCTAssertTrue(a === b)
    }

    func testPlatformIsNotEmpty() {
        XCTAssertFalse(DeviceInfo.shared.platform.isEmpty)
    }

    func testOsVersionIsNotEmpty() {
        XCTAssertFalse(DeviceInfo.shared.osVersion.isEmpty)
    }

    func testOsVersionFormatContainsDots() {
        let version = DeviceInfo.shared.osVersion
        let components = version.split(separator: ".")
        XCTAssertEqual(components.count, 3, "OS version should have major.minor.patch format")
    }

    func testDeviceModelIsNotEmpty() {
        XCTAssertFalse(DeviceInfo.shared.deviceModel.isEmpty)
    }

    func testUserAgentIsNotEmpty() {
        XCTAssertFalse(DeviceInfo.shared.userAgent.isEmpty)
    }

    func testUserAgentContainsRiviumTrace() {
        XCTAssertTrue(DeviceInfo.shared.userAgent.contains("RiviumTrace"))
    }

    func testRiviumTracePlatformIsNotEmpty() {
        XCTAssertFalse(DeviceInfo.shared.riviumTracePlatform.isEmpty)
    }

    func testDeviceInfoDictionaryContainsRequiredKeys() {
        let info = DeviceInfo.shared.deviceInfo

        XCTAssertNotNil(info["device_model"])
        XCTAssertNotNil(info["os_version"])
        XCTAssertNotNil(info["platform"])
        XCTAssertNotNil(info["locale"])
        XCTAssertNotNil(info["timezone"])
    }

    func testDeviceInfoDictionaryValuesAreNotEmpty() {
        let info = DeviceInfo.shared.deviceInfo

        XCTAssertFalse((info["device_model"] as? String)?.isEmpty ?? true)
        XCTAssertFalse((info["os_version"] as? String)?.isEmpty ?? true)
        XCTAssertFalse((info["platform"] as? String)?.isEmpty ?? true)
        XCTAssertFalse((info["locale"] as? String)?.isEmpty ?? true)
        XCTAssertFalse((info["timezone"] as? String)?.isEmpty ?? true)
    }

    func testDeviceIdentifierIsNotEmpty() {
        XCTAssertFalse(DeviceInfo.shared.deviceIdentifier.isEmpty)
    }

    func testDeviceIdentifierIsConsistent() {
        let id1 = DeviceInfo.shared.deviceIdentifier
        let id2 = DeviceInfo.shared.deviceIdentifier
        XCTAssertEqual(id1, id2)
    }

    func testIsSimulatorReturnsBool() {
        // Just verify it doesn't crash and returns a valid bool
        let _ = DeviceInfo.shared.isSimulator
    }

    func testUserAgentContainsSDKVersion() {
        XCTAssertTrue(DeviceInfo.shared.userAgent.contains(RiviumTraceSDK.version))
    }

    func testPlatformKnownValue() {
        let knownPlatforms = ["iOS", "macOS", "tvOS", "watchOS", "Unknown"]
        XCTAssertTrue(knownPlatforms.contains(DeviceInfo.shared.platform))
    }

    func testRiviumTracePlatformKnownValue() {
        let knownPlatforms = ["ios", "macos", "tvos", "watchos", "apple_unknown"]
        XCTAssertTrue(knownPlatforms.contains(DeviceInfo.shared.riviumTracePlatform))
    }
}

// MARK: - AnyCodable Tests

final class AnyCodableTests: XCTestCase {

    func testEncodeDecodeString() throws {
        let original = AnyCodable("hello")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? String, "hello")
    }

    func testEncodeDecodeInt() throws {
        let original = AnyCodable(42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? Int, 42)
    }

    func testEncodeDecodeDouble() throws {
        let original = AnyCodable(3.14)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let decodedValue = try XCTUnwrap(decoded.value as? Double)
        XCTAssertEqual(decodedValue, 3.14, accuracy: 0.001)
    }

    func testEncodeDecodeBool() throws {
        let original = AnyCodable(true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? Bool, true)
    }

    func testEncodeDecodeArray() throws {
        let original = AnyCodable([1, 2, 3])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let array = decoded.value as? [Any]
        XCTAssertNotNil(array)
        XCTAssertEqual(array?.count, 3)
    }

    func testEncodeDecodeDictionary() throws {
        let original = AnyCodable(["key": "value"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let dict = decoded.value as? [String: Any]
        XCTAssertEqual(dict?["key"] as? String, "value")
    }

    func testEncodeDecodeNull() throws {
        let original = AnyCodable(NSNull())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertTrue(decoded.value is NSNull)
    }
}

// MARK: - RiviumTraceSDK Version Tests

final class RiviumTraceSDKVersionTests: XCTestCase {

    func testVersionIsNotEmpty() {
        XCTAssertFalse(RiviumTraceSDK.version.isEmpty)
    }

    func testVersionHasSemanticFormat() {
        let components = RiviumTraceSDK.version.split(separator: ".")
        XCTAssertGreaterThanOrEqual(components.count, 2, "Version should have at least major.minor format")
        for component in components {
            XCTAssertNotNil(Int(component), "Each version component should be a number")
        }
    }
}
