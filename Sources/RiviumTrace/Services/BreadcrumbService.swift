import Foundation

/// Service for managing breadcrumbs (trail of events leading up to an error)
/// Thread-safe implementation using a concurrent queue
public class BreadcrumbService: @unchecked Sendable {

    /// Shared instance
    public static let shared = BreadcrumbService()

    private var breadcrumbs: [Breadcrumb] = []
    private var maxBreadcrumbs: Int = 20
    private let queue = DispatchQueue(label: "co.rivium.trace.breadcrumbs", attributes: .concurrent)

    private init() {}

    /// Configure the maximum number of breadcrumbs to store
    public func setMaxBreadcrumbs(_ max: Int) {
        queue.async(flags: .barrier) {
            self.maxBreadcrumbs = max
            self.trimBreadcrumbs()
        }
    }

    /// Add a breadcrumb
    public func add(_ breadcrumb: Breadcrumb) {
        queue.async(flags: .barrier) {
            self.breadcrumbs.append(breadcrumb)
            self.trimBreadcrumbs()
        }
    }

    /// Add a simple breadcrumb with message
    public func add(_ message: String, type: BreadcrumbType = .info, data: [String: Any] = [:]) {
        add(Breadcrumb(message: message, type: type, data: data))
    }

    /// Add a navigation breadcrumb
    public func addNavigation(from: String?, to: String) {
        add(Breadcrumb.navigation(from: from, to: to))
    }

    /// Add a user action breadcrumb
    public func addUser(_ action: String, data: [String: Any] = [:]) {
        add(Breadcrumb.user(action, data: data))
    }

    /// Add an HTTP request breadcrumb
    public func addHttp(method: String, url: String, statusCode: Int? = nil, duration: TimeInterval? = nil) {
        add(Breadcrumb.http(method: method, url: url, statusCode: statusCode, duration: duration))
    }

    /// Add a state change breadcrumb
    public func addState(_ message: String, data: [String: Any] = [:]) {
        add(Breadcrumb.state(message, data: data))
    }

    /// Add a system event breadcrumb
    public func addSystem(_ message: String, data: [String: Any] = [:]) {
        add(Breadcrumb.system(message, data: data))
    }

    /// Add an error breadcrumb
    public func addError(_ message: String, data: [String: Any] = [:]) {
        add(Breadcrumb.error(message, data: data))
    }

    /// Get all breadcrumbs
    public func getBreadcrumbs() -> [Breadcrumb] {
        return queue.sync {
            return self.breadcrumbs
        }
    }

    /// Get breadcrumbs as a list of dictionaries (for JSON serialization)
    public func getBreadcrumbsAsDictionary() -> [[String: Any]] {
        return getBreadcrumbs().map { $0.toDictionary() }
    }

    /// Clear all breadcrumbs
    public func clear() {
        queue.async(flags: .barrier) {
            self.breadcrumbs.removeAll()
        }
    }

    /// Get the number of stored breadcrumbs
    public var count: Int {
        return queue.sync {
            return self.breadcrumbs.count
        }
    }

    /// Trim breadcrumbs to max size (remove oldest first)
    private func trimBreadcrumbs() {
        while breadcrumbs.count > maxBreadcrumbs {
            breadcrumbs.removeFirst()
        }
    }
}
