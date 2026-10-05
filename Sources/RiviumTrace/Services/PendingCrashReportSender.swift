import Foundation

/// A crash report left on disk by a previous session, ready to send.
struct PendingCrashReport {
    /// The same for a given report on every launch, and different for
    /// another crash. Never sent to the server.
    let id: String
    let error: RiviumTraceError

    /// Identifier derived from the raw report (FNV-1a, 64 bit, plus length).
    static func identifier(for data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes {
                hash = (hash ^ UInt64(byte)) &* 0x100000001b3
            }
        }
        return String(format: "%016llx-%d", hash, data.count)
    }
}

/// Where the crash report of a previous session is read from and removed.
/// The crash reporter keeps a single report: a new crash replaces it.
protocol PendingCrashReportSource: AnyObject {
    /// The pending report, or `nil` when there is none. Must leave a
    /// readable report in place.
    func loadPendingCrashReport(
        environment: String,
        releaseVersion: String?,
        userAgent: String?
    ) -> PendingCrashReport?

    /// Delete the pending report.
    func purgePendingCrashReport()
}

/// What became of a pending crash report.
enum PendingCrashReportOutcome: Equatable {
    /// The server accepted it (2xx).
    case delivered
    /// The server refused it for good (4xx other than 408 and 429).
    case rejected
    /// It is in the offline store, which sends it from now on.
    case stored
    /// It cannot be turned into a request at all.
    case unsendable
    /// Nothing is settled (network failure, 5xx, 408, 429, SDK shut down):
    /// the report must stay where it is and be tried on the next launch.
    case stillPending

    /// True when the report is safe elsewhere or can never be accepted, so
    /// the crash reporter's copy is no longer needed.
    var allowsPurge: Bool {
        return self != .stillPending
    }
}

/// Sends the crash report of the previous session without ever losing it:
/// the report is removed from the crash reporter only after it was delivered,
/// refused for good, or written to the offline store.
///
/// With offline storage on, the report is moved to the offline store first
/// and sent from there, so the crash reporter is free for a new crash within
/// milliseconds. With offline storage off nothing is copied to disk: the
/// report is sent directly and stays in the crash reporter until the server
/// answers, to be tried again on every launch. A report that is still there
/// when the app crashes again is replaced by the new one.
///
/// A report can be delivered twice only when the process dies after the
/// server accepted it and before that answer was recorded on disk.
final class PendingCrashReportSender: @unchecked Sendable {

    private let source: PendingCrashReportSource
    private let client: RiviumTraceClient

    init(source: PendingCrashReportSource, client: RiviumTraceClient) {
        self.source = source
        self.client = client
    }

    /// Read the pending report and hand it to the client.
    ///
    /// Reads files and may write one, so it must not run on the main thread.
    /// Returns once the report is in the offline store or its request is
    /// under way; it never waits for the network.
    ///
    /// - Parameter completion: Called once, with `nil` when there was no
    ///   report, else with the outcome after any purge has been done.
    func sendPendingReport(
        environment: String,
        releaseVersion: String?,
        userAgent: String?,
        completion: ((PendingCrashReportOutcome?) -> Void)? = nil
    ) {
        let started = Date()
        guard let report = source.loadPendingCrashReport(
            environment: environment,
            releaseVersion: releaseVersion,
            userAgent: userAgent
        ) else {
            completion?(nil)
            return
        }
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        logInfo("Found a crash report from the previous session (read in \(elapsedMs) ms)")

        let source = self.source
        client.deliverCrashReport(report.error, id: report.id) { outcome in
            if outcome.allowsPurge {
                source.purgePendingCrashReport()
            }
            switch outcome {
            case .delivered:
                logInfo("Crash report from the previous session sent")
            case .rejected:
                logWarn("Crash report from the previous session rejected by server, dropped")
            case .stored:
                logDebug("Crash report from the previous session queued for sending")
            case .unsendable:
                logError("Crash report from the previous session could not be encoded, dropped")
            case .stillPending:
                logWarn("Crash report from the previous session not sent, will retry on next launch")
            }
            completion?(outcome)
        }
    }
}
