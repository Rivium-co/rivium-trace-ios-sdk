# Changelog

All notable changes to the RiviumTrace iOS SDK will be documented in this file.

## [1.0.0] - 2025-01-11

### Added
- Initial release of RiviumTrace iOS SDK
- Error tracking with automatic uncaught exception capture
- Signal crash handlers (SIGSEGV, SIGABRT, SIGBUS, etc.)
- Native crash detection via file marker system
- Breadcrumb system for tracking user journey
  - Navigation breadcrumbs
  - User action breadcrumbs
  - HTTP request breadcrumbs
  - System event breadcrumbs
- Logging with batching and retry support
- Performance monitoring (APM) with HTTP span tracking
- URLSession extension for automatic HTTP tracking
- User context and tagging
- Offline error caching
- Sample rate configuration
- Debug mode for development
- Multi-platform support (iOS, macOS, tvOS, watchOS)
- Swift Package Manager support
- CocoaPods support
