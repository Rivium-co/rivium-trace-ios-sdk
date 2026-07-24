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
        // Debuggerd-style text — fallback for consumers that don't understand
        // the structured JSON, and shown by older dashboards.
        let formatted = PLCrashReportTextFormatter.stringValue(
            for: report,
            with: PLCrashReportTextFormatiOS
        ) ?? "Native crash (no formatter output)"

        let signalName = normalizeSignalName(report.signalInfo?.name)
        let signalCode = report.signalInfo?.code ?? "unknown"
        let crashedThreadAddress = report.signalInfo?.address ?? 0

        // Structured Sentry-shape JSON — the dashboard renders this as a
        // frame-by-frame Sentry-style event when present.
        let structuredJson = buildSentryShapeJson(report: report)

        var extra: [String: Any] = [
            "error_type": "native_crash",
            "signal": signalName,
            "signal_code": signalCode,
            "fault_address": String(format: "0x%llx", crashedThreadAddress),
            "crash_reporter": "plcrashreporter",
            "tombstone_parsed": true
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
            message: "Native crash: \(signalName) (\(signalCode))",
            stackTrace: formatted,
            resolvedStackTrace: structuredJson,
            environment: environment,
            releaseVersion: releaseVersion,
            timestamp: Int64((report.systemInfo?.timestamp?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000),
            userAgent: userAgent,
            extra: extra,
            level: MessageLevel.fatal.rawValue
        )
    }

    /// Map a PLCrashReport to the same Sentry-shape structured event JSON
    /// that the Android tombstone parser produces. The dashboard's native
    /// crash renderer treats both platforms identically.
    private func buildSentryShapeJson(report: PLCrashReport) -> String? {
        let signalName = normalizeSignalName(report.signalInfo?.name)
        let signalCode = report.signalInfo?.code ?? "unknown"
        let faultAddr = report.signalInfo?.address ?? 0

        // Threads
        var threadsArr: [[String: Any]] = []
        var crashedTid: Int = 0
        if let threads = report.threads as? [PLCrashReportThreadInfo] {
            for thread in threads {
                let tid = Int(thread.threadNumber)
                let crashed = thread.crashed
                if crashed { crashedTid = tid }

                // Frames — PLCrashReport lists newest first; the Sentry
                // convention is oldest -> newest (crashing frame last), so
                // we reverse when writing.
                var frames: [[String: Any]] = []
                if let sf = thread.stackFrames as? [PLCrashReportStackFrameInfo] {
                    for f in sf.reversed() {
                        var frame: [String: Any] = [
                            "instruction_addr": String(format: "0x%llx", f.instructionPointer),
                            "in_app": frameIsInApp(f, images: report.images as? [PLCrashReportBinaryImageInfo]),
                            "platform": "native"
                        ]
                        if let symbol = f.symbolInfo {
                            let fn = symbol.symbolName ?? "<unknown>"
                            let offset = f.instructionPointer &- symbol.startAddress
                            frame["function"] = offset > 0 ? "\(fn)+\(offset)" : fn
                        } else {
                            frame["function"] = "<unknown>"
                        }
                        if let image = imageForAddress(f.instructionPointer, images: report.images as? [PLCrashReportBinaryImageInfo]) {
                            frame["package"] = image.imageName ?? ""
                            frame["image_addr"] = String(format: "0x%llx", image.imageBaseAddress)
                            if image.hasImageUUID, let uuid = image.imageUUID {
                                frame["build_id"] = uuid.replacingOccurrences(of: "-", with: "").lowercased()
                            }
                        }
                        frames.append(frame)
                    }
                }

                var stacktrace: [String: Any] = ["frames": frames]

                // Registers on the crashing thread only (matches Sentry
                // behaviour — registers are only meaningful at the crash site).
                if crashed, let regs = thread.registers as? [PLCrashReportRegisterInfo] {
                    var registers: [String: String] = [:]
                    for reg in regs {
                        let name = reg.registerName ?? ""
                        if name.isEmpty { continue }
                        registers[name] = String(format: "0x%016llx", reg.registerValue)
                    }
                    if !registers.isEmpty { stacktrace["registers"] = registers }
                }

                let threadDict: [String: Any] = [
                    "id": tid,
                    "name": "tid_\(tid)",
                    "crashed": crashed,
                    "current": crashed,
                    "main": tid == 0,
                    "stacktrace": stacktrace
                ]
                threadsArr.append(threadDict)
            }
        }

        // debug_meta.images
        var images: [[String: Any]] = []
        if let bins = report.images as? [PLCrashReportBinaryImageInfo] {
            for img in bins {
                var entry: [String: Any] = [
                    "type": "macho",
                    "code_file": img.imageName ?? "",
                    "image_addr": String(format: "0x%llx", img.imageBaseAddress),
                    "image_size": img.imageSize
                ]
                if let arch = img.codeType {
                    entry["arch"] = machoArchName(arch)
                }
                if img.hasImageUUID, let uuid = img.imageUUID {
                    entry["code_id"] = uuid.replacingOccurrences(of: "-", with: "").lowercased()
                    entry["debug_id"] = uuid.lowercased()
                }
                images.append(entry)
            }
        }

        // Exception mechanism.meta
        var meta: [String: Any] = [
            "signal": [
                "name": signalName,
                "code_name": signalCode
            ] as [String: Any]
        ]
        if let mach = report.machExceptionInfo {
            meta["mach_exception"] = [
                "exception": mach.type,
                "codes": (mach.codes as? [NSNumber])?.map { $0.uint64Value } ?? []
            ] as [String: Any]
        }

        let mechanism: [String: Any] = [
            "type": "plcrashreporter",
            "handled": false,
            "meta": meta,
            "data": [
                "fault_address": String(format: "0x%llx", faultAddr)
            ] as [String: Any]
        ]

        var exception: [String: Any] = [
            "type": signalName,
            "value": "\(signalName) (\(signalCode))",
            "thread_id": crashedTid,
            "mechanism": mechanism
        ]
        if let exc = report.exceptionInfo, let name = exc.exceptionName {
            exception["value"] = "\(name): \(exc.exceptionReason ?? "")"
        }

        var event: [String: Any] = [
            "format": "structured",
            "platform": "native",
            "level": "fatal",
            "exception": exception,
            "threads": threadsArr,
            "debug_meta": ["images": images]
        ]

        // Platform metadata — parallels Android's tombstone_meta.
        var meta2: [String: Any] = [:]
        if let sys = report.systemInfo {
            meta2["os_version"] = sys.operatingSystemVersion ?? ""
            meta2["os_build"] = sys.operatingSystemBuild ?? ""
        }
        if let proc = report.processInfo {
            meta2["process_name"] = proc.processName ?? ""
            meta2["pid"] = proc.processID
            meta2["command_line"] = [proc.processPath ?? ""]
        }
        if !meta2.isEmpty { event["ios_meta"] = meta2 }

        // JSONSerialization with fragment-free defaults. Order isn't guaranteed
        // but the dashboard doesn't care.
        guard let data = try? JSONSerialization.data(withJSONObject: event, options: []) else {
            logError("Failed to serialize Sentry-shape crash JSON")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// True when the frame's image lives inside the app's main bundle
    /// (`.app` directory). System frameworks and OS libs live under
    /// /System, /usr/lib, /Library/PrivateFrameworks — those are not "in-app".
    private func frameIsInApp(
        _ frame: PLCrashReportStackFrameInfo,
        images: [PLCrashReportBinaryImageInfo]?
    ) -> Bool {
        guard let img = imageForAddress(frame.instructionPointer, images: images) else { return false }
        guard let path = img.imageName else { return false }
        // Match Sentry's Cocoa SDK heuristic.
        return path.contains(".app/") &&
            !path.contains("/Frameworks/libswift") &&
            !path.hasPrefix("/System/") &&
            !path.hasPrefix("/usr/lib/")
    }

    private func imageForAddress(
        _ addr: UInt64,
        images: [PLCrashReportBinaryImageInfo]?
    ) -> PLCrashReportBinaryImageInfo? {
        guard let images = images else { return nil }
        for img in images {
            let end = img.imageBaseAddress &+ img.imageSize
            if addr >= img.imageBaseAddress && addr < end {
                return img
            }
        }
        return nil
    }

    private func machoArchName(_ codeType: PLCrashReportProcessorInfo) -> String {
        // CPU_TYPE_* constants from <mach/machine.h>. Kept inline so this file
        // doesn't need the mach import and works on all Apple platforms.
        //   CPU_TYPE_X86       = 7
        //   CPU_TYPE_ARM       = 12
        //   CPU_ARCH_ABI64     = 0x01000000
        //   CPU_TYPE_X86_64    = 7  | 0x01000000 = 16777223
        //   CPU_TYPE_ARM64     = 12 | 0x01000000 = 16777228
        switch codeType.type {
        case 16777228: return "arm64"
        case 12: return "arm"
        case 16777223: return "x86_64"
        case 7: return "x86"
        default: return "unknown"
        }
    }

    /// PLCrashReport returns signal names already SIG-prefixed (e.g. "SIGSEGV").
    /// Legacy versions sometimes returned bare "SEGV". Normalize to a single
    /// "SIG*" form so the dashboard never shows "SIGSIGSEGV".
    private func normalizeSignalName(_ raw: String?) -> String {
        guard let raw = raw, !raw.isEmpty else { return "SIGUNKNOWN" }
        return raw.hasPrefix("SIG") ? raw : "SIG\(raw)"
    }
    #endif
}
