import Foundation
import UIKit

/// Crash detection using two-file marker approach
///
/// How it works:
/// 1. On app start: Check if "clean exit" marker exists from last session
/// 2. If session file exists but NO clean exit marker → Previous session crashed
/// 3. When app goes to background → Create clean exit marker
/// 4. When app returns to foreground → Remove clean exit marker
/// 5. If app crashes while in foreground, no clean exit marker exists → crash detected on next launch
///
/// This prevents false crash detection when user swipes the app away normally.
public class CrashDetector {

    /// Shared instance
    public static let shared = CrashDetector()

    private let sessionFilename = "rivium_trace_session.txt"
    private let cleanExitFilename = "rivium_trace_clean_exit.txt"
    private let maxCrashAgeSeconds: TimeInterval = 24 * 60 * 60 // 24 hours

    private var sessionPath: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(sessionFilename)
    }

    private var cleanExitPath: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(cleanExitFilename)
    }

    private var isObservingLifecycle = false

    private init() {}

    /// Crash info from previous session
    public struct CrashInfo {
        public let timestamp: Date
        public let sessionId: String?
        public let lastScreen: String?
        public let timeSinceCrashSeconds: Int64
    }

    /// Start observing app lifecycle for automatic clean exit marking
    public func startObservingLifecycle() {
        guard !isObservingLifecycle else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )

        isObservingLifecycle = true
        logDebug("Started observing app lifecycle for crash detection")
    }

    /// Stop observing app lifecycle
    public func stopObservingLifecycle() {
        guard isObservingLifecycle else { return }

        NotificationCenter.default.removeObserver(self)
        isObservingLifecycle = false
        logDebug("Stopped observing app lifecycle")
    }

    @objc private func appWillResignActive() {
        // App is about to become inactive - mark clean exit
        markCleanExit()
    }

    @objc private func appDidEnterBackground() {
        // App entered background - ensure clean exit is marked
        markCleanExit()
    }

    @objc private func appWillEnterForeground() {
        // App coming back - clear clean exit marker
        clearCleanExit()
    }

    @objc private func appDidBecomeActive() {
        // App is active again - clear clean exit marker
        clearCleanExit()
    }

    @objc private func appWillTerminate() {
        // App is terminating gracefully - mark clean exit
        markCleanExit()
    }

    /// Check if a crash occurred in a previous session
    /// Crash = session file exists but clean exit file does NOT exist
    public func checkForCrash() -> CrashInfo? {
        let fileManager = FileManager.default
        let sessionPath = self.sessionPath
        let cleanExitPath = self.cleanExitPath

        let hadSession = fileManager.fileExists(atPath: sessionPath.path)
        let hadCleanExit = fileManager.fileExists(atPath: cleanExitPath.path)

        logDebug("Crash check - hadSession: \(hadSession), hadCleanExit: \(hadCleanExit)")

        // Clean up clean exit marker first
        if hadCleanExit {
            try? fileManager.removeItem(at: cleanExitPath)
        }

        // No crash if: no session, or had clean exit
        if !hadSession || hadCleanExit {
            logDebug("No crash detected")
            // Clean up session file if it exists
            if hadSession {
                try? fileManager.removeItem(at: sessionPath)
            }
            return nil
        }

        // Had session but no clean exit = crash
        do {
            let content = try String(contentsOf: sessionPath, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")

            guard let timestampString = lines.first,
                  let timestamp = Double(timestampString) else {
                try? fileManager.removeItem(at: sessionPath)
                return nil
            }

            let crashDate = Date(timeIntervalSince1970: timestamp / 1000)
            let timeSince = Date().timeIntervalSince(crashDate)

            // Check if session is too old
            if timeSince > maxCrashAgeSeconds {
                logDebug("Session too old, ignoring")
                try? fileManager.removeItem(at: sessionPath)
                return nil
            }

            let sessionId = lines.count > 1 && !lines[1].isEmpty ? lines[1] : nil
            let lastScreen = lines.count > 2 && !lines[2].isEmpty ? lines[2] : nil

            logInfo("Crash detected from previous session (\(Int(timeSince))s ago)")

            // Delete the session file after reading
            try? fileManager.removeItem(at: sessionPath)

            return CrashInfo(
                timestamp: crashDate,
                sessionId: sessionId,
                lastScreen: lastScreen,
                timeSinceCrashSeconds: Int64(timeSince)
            )
        } catch {
            logError("Failed to read session file: \(error.localizedDescription)")
            try? fileManager.removeItem(at: sessionPath)
            return nil
        }
    }

    /// Create a session marker file
    public func createMarker(sessionId: String? = nil) {
        let content = """
            \(Int64(Date().timeIntervalSince1970 * 1000))
            \(sessionId ?? "")

            """

        do {
            try content.write(to: sessionPath, atomically: true, encoding: .utf8)

            // Remove any existing clean exit marker (we're now running)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: cleanExitPath.path) {
                try? fileManager.removeItem(at: cleanExitPath)
            }

            logDebug("Session marker created")

            // Start observing lifecycle
            startObservingLifecycle()
        } catch {
            logError("Failed to create session marker: \(error.localizedDescription)")
        }
    }

    /// Update the session marker with latest screen info
    public func updateLastScreen(_ screenName: String) {
        let fileManager = FileManager.default
        let path = sessionPath

        guard fileManager.fileExists(atPath: path.path) else { return }

        do {
            var content = try String(contentsOf: path, encoding: .utf8)
            var lines = content.components(separatedBy: "\n")

            // Ensure we have at least 3 lines
            while lines.count < 3 {
                lines.append("")
            }
            lines[2] = screenName

            content = lines.joined(separator: "\n")
            try content.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            logError("Failed to update session marker: \(error.localizedDescription)")
        }
    }

    /// Mark that the app is going to background (clean exit)
    public func markCleanExit() {
        let content = "\(Int64(Date().timeIntervalSince1970 * 1000))"
        do {
            try content.write(to: cleanExitPath, atomically: true, encoding: .utf8)
            logDebug("Clean exit marker created (app going to background)")
        } catch {
            logError("Failed to create clean exit marker: \(error.localizedDescription)")
        }
    }

    /// Remove clean exit marker when app comes back to foreground
    public func clearCleanExit() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cleanExitPath.path) {
            do {
                try fileManager.removeItem(at: cleanExitPath)
                logDebug("Clean exit marker removed (app in foreground)")
            } catch {
                logError("Failed to remove clean exit marker: \(error.localizedDescription)")
            }
        }
    }

    /// Delete all markers (call on explicit close for complete cleanup)
    public func deleteMarker() {
        stopObservingLifecycle()

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: sessionPath.path) {
                try fileManager.removeItem(at: sessionPath)
            }
            if fileManager.fileExists(atPath: cleanExitPath.path) {
                try fileManager.removeItem(at: cleanExitPath)
            }
            logDebug("All markers deleted (graceful shutdown)")
        } catch {
            logError("Failed to delete markers: \(error.localizedDescription)")
        }
    }

    /// Check if session marker exists
    public var hasMarker: Bool {
        return FileManager.default.fileExists(atPath: sessionPath.path)
    }
}

// MARK: - Signal Crash Handler

/// Signal handler for native crashes
public class SignalCrashHandler {

    public static let shared = SignalCrashHandler()

    private var previousHandlers: [Int32: (@convention(c) (Int32) -> Void)?] = [:]
    private var isInstalled = false

    private let signals: [Int32] = [
        SIGABRT,  // Abort
        SIGBUS,   // Bus error
        SIGFPE,   // Floating point exception
        SIGILL,   // Illegal instruction
        SIGPIPE,  // Broken pipe
        SIGSEGV,  // Segmentation fault
        SIGSYS,   // Bad system call
        SIGTRAP   // Trap
    ]

    private init() {}

    /// Install signal handlers
    public func install() {
        guard !isInstalled else { return }

        for sig in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = signalHandler
            sigemptyset(&action.sa_mask)
            action.sa_flags = 0

            var oldAction = sigaction()
            sigaction(sig, &action, &oldAction)

            // Store previous handler
            previousHandlers[sig] = oldAction.__sigaction_u.__sa_handler
        }

        isInstalled = true
        logDebug("Signal crash handlers installed")
    }

    /// Uninstall signal handlers
    public func uninstall() {
        guard isInstalled else { return }

        for sig in signals {
            if let previousHandler = previousHandlers[sig] {
                var action = sigaction()
                action.__sigaction_u.__sa_handler = previousHandler
                sigemptyset(&action.sa_mask)
                action.sa_flags = 0
                sigaction(sig, &action, nil)
            } else {
                signal(sig, SIG_DFL)
            }
        }

        previousHandlers.removeAll()
        isInstalled = false
        logDebug("Signal crash handlers uninstalled")
    }

    /// Get signal name
    public static func signalName(_ signal: Int32) -> String {
        switch signal {
        case SIGABRT: return "SIGABRT"
        case SIGBUS: return "SIGBUS"
        case SIGFPE: return "SIGFPE"
        case SIGILL: return "SIGILL"
        case SIGPIPE: return "SIGPIPE"
        case SIGSEGV: return "SIGSEGV"
        case SIGSYS: return "SIGSYS"
        case SIGTRAP: return "SIGTRAP"
        default: return "SIGNAL(\(signal))"
        }
    }
}

// Global signal handler function
private func signalHandler(signal: Int32) {
    let signalName = SignalCrashHandler.signalName(signal)
    logError("Received signal: \(signalName)")

    // The session marker should already be in place
    // The crash will be detected on next launch

    // Re-raise the signal with default handler
    SignalCrashHandler.shared.uninstall()
    raise(signal)
}
