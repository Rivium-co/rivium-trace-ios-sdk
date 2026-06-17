import Foundation
#if canImport(CrashReporter)
import CrashReporter
#endif

/// Native crash capture backed by PLCrashReporter.
///
/// PLCrashReporter installs async-signal-safe handlers for POSIX signals
/// (SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP) and Mach exception
/// ports. On crash it writes a structured report to disk inside the app
/// sandbox. On the next launch the report is parsed, mapped into our
/// `RiviumTraceError.nativeCrash` payload, and POSTed to the backend.
///
/// PLCrashReporter is vendored as a static xcframework at
/// `Frameworks/CrashReporter.xcframework/` and shipped under the MIT
/// license preserved in `THIRD_PARTY_NOTICES.txt`.
final class NativeCrashReporter: @unchecked Sendable {

    static let shared = NativeCrashReporter()

    private var isInstalled = false

    private init() {}

    /// Install the native crash handler. Must be called once during SDK init.
    func install() {
        #if canImport(CrashReporter)
        guard !isInstalled else { return }

        let config = PLCrashReporterConfig(
            signalHandlerType: .BSD,
            symbolicationStrategy: []
        )
        guard let reporter = PLCrashReporter(configuration: config) else {
            logError("PLCrashReporter failed to instantiate")
            return
        }

        do {
            try reporter.enableAndReturnError()
            isInstalled = true
            logDebug("Native crash handler installed (PLCrashReporter)")
        } catch {
            logError("Failed to install native crash handler: \(error.localizedDescription)")
        }
        #else
        logWarn("Native crash capture unavailable: CrashReporter framework not linked")
        #endif
    }

    /// Check for a pending crash report written by a previous session and
    /// hand it back as a `RiviumTraceError` ready to send.
    ///
    /// Returns `nil` if there is no pending report.
    func loadPendingCrashReport(
        environment: String,
        releaseVersion: String?,
        userAgent: String?
    ) -> RiviumTraceError? {
        #if canImport(CrashReporter)
        let config = PLCrashReporterConfig(
            signalHandlerType: .BSD,
            symbolicationStrategy: []
        )
        guard let reporter = PLCrashReporter(configuration: config) else { return nil }
        guard reporter.hasPendingCrashReport() else { return nil }

        do {
            let data = try reporter.loadPendingCrashReportDataAndReturnError()
            let report = try PLCrashReport(data: data)
            let error = mapReportToError(
                report,
                environment: environment,
                releaseVersion: releaseVersion,
                userAgent: userAgent
            )
            try? reporter.purgePendingCrashReportAndReturnError()
            return error
        } catch {
            logError("Failed to load pending crash report: \(error.localizedDescription)")
            try? reporter.purgePendingCrashReportAndReturnError()
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(CrashReporter)
    private func mapReportToError(
        _ report: PLCrashReport,
        environment: String,
        releaseVersion: String?,
        userAgent: String?
    ) -> RiviumTraceError {
        // PLCrashReport ships a human-readable text formatter that produces
        // a stack-trace-style block similar to Apple crash logs. The backend
        // re-symbolicates using uploaded dSYMs against the raw addresses, so
        // the text form here is the fallback for the dashboard preview.
        let formatted = PLCrashReportTextFormatter.stringValue(
            for: report,
            with: PLCrashReportTextFormatiOS
        ) ?? "Native crash (no formatter output)"

        let signalName = report.signalInfo?.name ?? "unknown"
        let signalCode = report.signalInfo?.code ?? "unknown"
        let crashedThreadAddress = report.signalInfo?.address ?? 0

        // Find the crashed thread for raw addresses
        var rawAddresses: [String] = []
        if let threads = report.threads as? [PLCrashReportThreadInfo] {
            if let crashed = threads.first(where: { $0.crashed }),
               let frames = crashed.stackFrames as? [PLCrashReportStackFrameInfo] {
                rawAddresses = frames.map { String(format: "0x%llx", $0.instructionPointer) }
            }
        }

        // Map binary images to the same shape BinaryImageCollector produces
        // so the backend symbolication path is unchanged.
        var binaryImages: [[String: Any]] = []
        if let images = report.images as? [PLCrashReportBinaryImageInfo] {
            for img in images {
                var entry: [String: Any] = [
                    "name": (img.imageName as NSString?)?.lastPathComponent ?? "",
                    "path": img.imageName ?? "",
                    "load_address": String(format: "0x%llx", img.imageBaseAddress),
                    "size": img.imageSize
                ]
                if let uuid = img.hasImageUUID ? img.imageUUID : nil {
                    entry["uuid"] = uuid
                }
                binaryImages.append(entry)
            }
        }

        var extra: [String: Any] = [
            "error_type": "native_crash",
            "signal": signalName,
            "signal_code": signalCode,
            "fault_address": String(format: "0x%llx", crashedThreadAddress),
            "binary_images": binaryImages,
            "raw_addresses": rawAddresses,
            "crash_reporter": "plcrashreporter"
        ]

        if let exc = report.exceptionInfo {
            extra["exception_name"] = exc.exceptionName ?? ""
            extra["exception_reason"] = exc.exceptionReason ?? ""
        }
        if let mach = report.machExceptionInfo {
            extra["mach_exception_type"] = mach.type
            extra["mach_exception_codes"] = (mach.codes as? [NSNumber])?.map { $0.uint64Value } ?? []
        }

        return RiviumTraceError(
            message: "Native crash: SIG\(signalName) (\(signalCode))",
            stackTrace: formatted,
            environment: environment,
            releaseVersion: releaseVersion,
            timestamp: Int64((report.systemInfo?.timestamp?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000),
            userAgent: userAgent,
            extra: extra,
            level: MessageLevel.fatal.rawValue
        )
    }
    #endif
}
