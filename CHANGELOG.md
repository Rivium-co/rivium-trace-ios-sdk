# Changelog

All notable changes to the RiviumTrace iOS SDK will be documented in this file.

## [0.2.0] - 2026-07-24

### Added
- Native crashes are now posted as a **Sentry-shape structured event** in the
  new `resolved_stack_trace` field. `NativeCrashReporter` maps the parsed
  `PLCrashReport` into the same JSON schema the Android SDK emits, so the
  RiviumTrace dashboard renders iOS and Android native crashes with an
  identical frame-by-frame view (signal metadata, thread selector with the
  crashing thread flagged, register dump, per-frame image path + instruction
  address, `debug_meta.images` with UUIDs suitable for dSYM symbolication).
- Debuggerd/Apple-style text trace is still populated in the `stack_trace`
  field as a fallback for older consumers.
- `RiviumTraceError.resolvedStackTrace: String?` field on the public model,
  serialized as `resolved_stack_trace`. Non-native errors leave it `nil`.

### Fixed
- Signal name is no longer double-prefixed. `PLCrashReport.signalInfo.name`
  already returns `"SIGSEGV"`, so the previous code produced `"SIGSIGSEGV"`
  in the crash title. Names starting with `SIG` are now passed through as-is.

### Breaking changes
- **Native crash capture is now backed by PLCrashReporter 1.12.0 (MIT, vendored).**
  The previous lifecycle-marker heuristic produced false-positive "native crash"
  reports on every non-graceful app close (swipe-to-quit, OS memory kill,
  force-quit). It has been removed. Real crashes are now caught by
  async-signal-safe handlers for POSIX signals (SIGSEGV, SIGABRT, SIGBUS, SIGILL,
  SIGFPE, SIGTRAP) and Mach exception ports, and reported on the next launch
  with full thread state, register values, and binary images for server-side
  symbolication.
- **`watchOS` support dropped.** PLCrashReporter does not ship a watchOS slice.
  iOS 12+, macOS 10.14+, tvOS 12+, and Mac Catalyst remain supported.
- The previous in-process `SignalCrashHandler` and `CrashDetector` types are
  removed. They were not safe to call from a signal context and never produced
  useful stack traces.

### Added
- `NativeCrashReporter` service wrapping PLCrashReporter. Drains pending crash
  reports on init and installs handlers for the running session.
- Vendored `CrashReporter.xcframework` (PLCrashReporter 1.12.0) under
  `Frameworks/`. See `THIRD_PARTY_NOTICES.txt`.
- `THIRD_PARTY_NOTICES.txt` at repo root listing the MIT license of
  PLCrashReporter and the Apache-2.0 license of its protobuf-c dependency.

### Configuration
- `captureSignalCrashes` (default `true`) now controls PLCrashReporter
  installation. Set to `false` to disable native crash capture.

## [0.1.0] - 2026-03-07

### Added
- Initial release of RiviumTrace iOS SDK
- Error tracking with automatic uncaught exception capture
- Signal crash handlers (SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGPIPE, SIGSYS, SIGTRAP) — *removed in 2.0.0; see entry above*
- Native crash detection via file marker system — *removed in 2.0.0; see entry above*
- ANR (Application Not Responding) detection
- Breadcrumb system for tracking user journey
  - Navigation breadcrumbs
  - User action breadcrumbs
  - HTTP request breadcrumbs
  - System event breadcrumbs
- Performance monitoring (APM) with HTTP span tracking
- Custom span reporting and batch reporting
- Structured logging with batching and exponential backoff retry
- URLSession extension for automatic HTTP tracking
- Automatic HTTP error capturing and privacy protection
- User context, global extras, and tags
- Offline error caching
- Sample rate configuration
- Multi-platform support (iOS 12+, macOS 10.14+, tvOS 12+, watchOS 5+)
- Swift Package Manager support
- CocoaPods support
- Carthage support
