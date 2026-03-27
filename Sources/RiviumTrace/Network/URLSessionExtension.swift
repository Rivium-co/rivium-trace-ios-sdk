import Foundation

/// URLSession extension for automatic HTTP breadcrumb tracking
public final class RiviumTraceHttpBreadcrumbProtocol: URLProtocol, @unchecked Sendable {

    private var dataTask: URLSessionDataTask?
    private var startTime: Date?
    private var receivedData: Data = Data()

    nonisolated(unsafe) private static var isEnabled = false

    /// Enable HTTP error capturing (4xx, 5xx responses)
    nonisolated(unsafe) public static var captureHttpErrors: Bool = true

    /// Enable client error capturing (4xx responses) - only works if captureHttpErrors is true
    nonisolated(unsafe) public static var captureClientErrors: Bool = false

    /// Enable automatic HTTP tracking
    public static func enable() {
        guard !isEnabled else { return }
        URLProtocol.registerClass(RiviumTraceHttpBreadcrumbProtocol.self)
        isEnabled = true
        logDebug("RiviumTraceHttpBreadcrumbProtocol enabled")
    }

    /// Disable automatic HTTP tracking
    public static func disable() {
        guard isEnabled else { return }
        URLProtocol.unregisterClass(RiviumTraceHttpBreadcrumbProtocol.self)
        isEnabled = false
        logDebug("RiviumTraceHttpBreadcrumbProtocol disabled")
    }

    // MARK: - URLProtocol

    public override class func canInit(with request: URLRequest) -> Bool {
        // Don't intercept RiviumTrace API calls
        if let url = request.url?.absoluteString, url.contains("rivium.co") {
            return false
        }

        // Don't intercept already handled requests
        if URLProtocol.property(forKey: "RiviumTraceHandled", in: request) != nil {
            return false
        }

        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    public override func startLoading() {
        startTime = Date()

        // Mark request as handled
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return
        }
        URLProtocol.setProperty(true, forKey: "RiviumTraceHandled", in: mutableRequest)

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        dataTask = session.dataTask(with: mutableRequest as URLRequest)
        dataTask?.resume()
    }

    public override func stopLoading() {
        dataTask?.cancel()
    }
}

// MARK: - URLSessionDataDelegate

extension RiviumTraceHttpBreadcrumbProtocol: URLSessionDataDelegate {

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let duration = startTime.map { Date().timeIntervalSince($0) }
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode

        // Add breadcrumb
        if let request = task.originalRequest {
            let method = request.httpMethod ?? "GET"
            let url = sanitizeUrl(request.url?.absoluteString ?? "unknown")

            RiviumTrace.shared.addHttpBreadcrumb(
                method: method,
                url: url,
                statusCode: statusCode,
                duration: duration
            )

            // Capture HTTP errors (4xx, 5xx) if enabled
            if let code = statusCode, code >= 400, RiviumTraceHttpBreadcrumbProtocol.captureHttpErrors {
                let errorType = code >= 500 ? "Server Error" : "Client Error"

                // Only capture server errors by default, client errors are optional
                if code >= 500 || RiviumTraceHttpBreadcrumbProtocol.captureClientErrors {
                    RiviumTrace.shared.captureMessage(
                        "HTTP \(errorType): \(method) \(url) (\(code))",
                        level: code >= 500 ? .error : .warning,
                        extra: [
                            "status_code": code,
                            "method": method,
                            "url": url,
                            "duration_ms": (duration ?? 0) * 1000
                        ]
                    )
                }
            }
        }

        if let error = error {
            // Capture network errors
            if RiviumTraceHttpBreadcrumbProtocol.captureHttpErrors {
                let request = task.originalRequest
                let method = request?.httpMethod ?? "GET"
                let url = sanitizeUrl(request?.url?.absoluteString ?? "unknown")

                RiviumTrace.shared.captureMessage(
                    "HTTP Request Failed: \(method) \(url)",
                    level: .error,
                    extra: [
                        "error": error.localizedDescription,
                        "method": method,
                        "url": url,
                        "duration_ms": (duration ?? 0) * 1000
                    ]
                )
            }
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private func sanitizeUrl(_ url: String) -> String {
        // Remove sensitive query parameters
        let sensitiveParams = ["token", "api_key", "apikey", "key", "secret",
                              "password", "pwd", "auth", "authorization",
                              "access_token", "refresh_token", "session"]

        var sanitized = url
        for param in sensitiveParams {
            let pattern = "([?&])\(param)=[^&]*"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    range: NSRange(sanitized.startIndex..., in: sanitized),
                    withTemplate: "$1\(param)=[REDACTED]"
                )
            }
        }
        return sanitized
    }
}

// MARK: - URLSession Extension

public extension URLSession {

    /// Create a URLSession with RiviumTrace tracking enabled
    static func riviumTraceSession(configuration: URLSessionConfiguration = .default) -> URLSession {
        configuration.protocolClasses = [RiviumTraceHttpBreadcrumbProtocol.self] + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
    }
}
