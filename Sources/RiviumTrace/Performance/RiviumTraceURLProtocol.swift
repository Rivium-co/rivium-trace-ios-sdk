import Foundation

/// Custom URLProtocol for automatic HTTP performance tracking
///
/// This protocol intercepts all URLSession requests and reports timing data to RiviumTrace APM.
///
/// Usage:
/// ```swift
/// // Enable automatic tracking
/// RiviumTraceURLProtocol.register()
///
/// // Or use a custom URLSession
/// let config = URLSessionConfiguration.default
/// config.protocolClasses = [RiviumTraceURLProtocol.self] + (config.protocolClasses ?? [])
/// let session = URLSession(configuration: config)
/// ```
public final class RiviumTraceURLProtocol: URLProtocol, @unchecked Sendable {

    // MARK: - Properties

    private static let handledKey = "RiviumTraceURLProtocolHandled"

    private var dataTask: URLSessionDataTask?
    private var receivedData: Data?
    private var startTime: Date?
    private var response: URLResponse?

    nonisolated(unsafe) private static var excludedHosts: Set<String> = ["trace.rivium.co"]
    nonisolated(unsafe) private static var minDurationMs: Double = 0

    // MARK: - Configuration

    /// Register the protocol to intercept all URLSession requests
    public static func register() {
        URLProtocol.registerClass(RiviumTraceURLProtocol.self)
    }

    /// Unregister the protocol
    public static func unregister() {
        URLProtocol.unregisterClass(RiviumTraceURLProtocol.self)
    }

    /// Configure the RiviumTrace API host to always exclude from tracking.
    /// Call this during SDK initialization with the configured apiUrl.
    public static func setApiUrl(_ apiUrl: String) {
        if let host = URL(string: apiUrl)?.host {
            excludedHosts.insert(host)
        }
    }

    /// Set hosts to exclude from tracking (e.g., third-party analytics)
    public static func setExcludedHosts(_ hosts: [String]) {
        excludedHosts = Set(hosts)
        excludedHosts.insert("trace.rivium.co") // Always exclude default RiviumTrace API
    }

    /// Set minimum duration (ms) to report. Spans shorter than this are ignored.
    public static func setMinDurationMs(_ ms: Double) {
        minDurationMs = ms
    }

    // MARK: - URLProtocol Override

    public override class func canInit(with request: URLRequest) -> Bool {
        // Don't handle if already processed
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }

        // Don't track RiviumTrace's own API calls or excluded hosts
        if let host = request.url?.host, excludedHosts.contains(host) {
            return false
        }

        // Only track HTTP/HTTPS requests
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    public override func startLoading() {
        startTime = Date()
        receivedData = Data()

        // Mark request as handled to prevent infinite loop
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: RiviumTraceURLProtocolError.failedToCreateRequest)
            return
        }

        URLProtocol.setProperty(true, forKey: RiviumTraceURLProtocol.handledKey, in: mutableRequest)

        // Create a new session to forward the request
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        dataTask = session.dataTask(with: mutableRequest as URLRequest)
        dataTask?.resume()
    }

    public override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }

    // MARK: - Private Methods

    private func reportPerformanceSpan(error: Error? = nil) {
        guard let start = startTime else { return }

        let durationMs = Date().timeIntervalSince(start) * 1000

        // Skip if below minimum duration threshold
        guard durationMs >= RiviumTraceURLProtocol.minDurationMs else { return }

        let httpResponse = response as? HTTPURLResponse
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        let path = request.url?.path ?? ""
        let host = request.url?.host ?? ""

        RiviumTrace.shared.trackHttpRequest(
            request: request,
            response: httpResponse,
            startTime: start,
            error: error
        )
    }
}

// MARK: - URLSessionDataDelegate

extension RiviumTraceURLProtocol: URLSessionDataDelegate {

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData?.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            reportPerformanceSpan(error: error)
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            reportPerformanceSpan()
            client?.urlProtocolDidFinishLoading(self)
        }

        session.invalidateAndCancel()
    }
}

// MARK: - Errors

enum RiviumTraceURLProtocolError: Error {
    case failedToCreateRequest
}
