# Changelog

All notable changes to the RiviumTrace iOS SDK will be documented in this file.

## [0.1.0] - 2026-03-07

### Added
- Initial release of RiviumTrace iOS SDK
- Error tracking with automatic uncaught exception capture
- Signal crash handlers (SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGPIPE, SIGSYS, SIGTRAP)
- Native crash detection via file marker system
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
