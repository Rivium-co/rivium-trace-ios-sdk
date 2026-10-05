import Foundation

/// Disk store for error reports that could not be sent because the network
/// was unavailable.
///
/// Each entry is the exact JSON body of the `/api/errors` request. The API key
/// is never written: stored bodies are sent again with the key of the config
/// in use at that time.
///
/// All state and all file access are confined to one private serial queue, so
/// nothing here runs on the caller's thread. Every failure is logged and
/// swallowed.
final class OfflineErrorStore: @unchecked Sendable {

    /// One stored error report.
    struct Entry {
        /// Identifies the entry inside the store (never sent to the server).
        let id: String
        /// The JSON request body, byte for byte as it was first sent.
        let body: Data
    }

    static let fileName = "rivium_trace_offline_errors.json"
    static let defaultMaxEntries = 100

    /// Store used by the SDK, in the app's Application Support directory.
    static let shared = OfflineErrorStore()

    private let queue = DispatchQueue(label: "co.rivium.trace.offline-store", qos: .utility)
    private let maxEntries: Int
    private let explicitFileURL: URL?

    // Only touched on `queue`.
    private var resolvedFileURL: URL?
    private var didResolveFileURL = false
    private var entries: [Entry] = []
    private var isLoaded = false
    private var isResending = false

    /// - Parameters:
    ///   - fileURL: Where to keep the file. `nil` uses the default location.
    ///   - maxEntries: Cap on stored errors; the oldest are dropped first.
    init(fileURL: URL? = nil, maxEntries: Int = OfflineErrorStore.defaultMaxEntries) {
        self.explicitFileURL = fileURL
        self.maxEntries = max(1, maxEntries)
    }

    // MARK: - Writing

    /// Add an error body. When `synchronously` is true the call returns after
    /// the file is written (used when the process is about to die); it must
    /// then not be called from the store's own queue.
    func add(_ body: Data, synchronously: Bool = false) {
        let work = { [self] in
            loadIfNeeded()
            entries.append(Entry(id: UUID().uuidString, body: body))
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
            persist()
            logDebug("Error stored offline for later sending (\(entries.count) stored)")
        }
        if synchronously {
            queue.sync(execute: work)
        } else {
            queue.async(execute: work)
        }
    }

    /// Remove one entry after the server has answered for it.
    func remove(id: String) {
        queue.async { [self] in
            loadIfNeeded()
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries.remove(at: index)
            persist()
        }
    }

    // MARK: - Resend pass

    /// Start a resend pass. `handler` runs on the store's queue with the
    /// entries to send (oldest first), or with `nil` when there is nothing to
    /// do or a pass is already running. Only one pass runs at a time, so an
    /// entry is never handed out twice at once. A caller that receives
    /// entries must call `endResend()` when it is done.
    func beginResend(_ handler: @escaping ([Entry]?) -> Void) {
        queue.async { [self] in
            guard !isResending else {
                handler(nil)
                return
            }
            loadIfNeeded()
            guard !entries.isEmpty else {
                handler(nil)
                return
            }
            isResending = true
            handler(entries)
        }
    }

    /// End the pass started by `beginResend`. `completion` runs on the
    /// store's queue once the pass is closed.
    func endResend(_ completion: (() -> Void)? = nil) {
        queue.async { [self] in
            isResending = false
            completion?()
        }
    }

    // MARK: - Reading

    /// Current entries, oldest first. Blocks on the store's queue; not for
    /// use on the main thread.
    func snapshot() -> [Entry] {
        return queue.sync { () -> [Entry] in
            loadIfNeeded()
            return entries
        }
    }

    // MARK: - File access (queue only)

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        entries = []

        guard let url = fileURL() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            guard let list = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                logWarn("Offline error file has an unexpected format, starting empty")
                return
            }
            var loaded: [Entry] = []
            for item in list {
                guard let dict = item as? [String: Any],
                      let id = dict["id"] as? String,
                      let bodyText = dict["body"] as? String,
                      let body = bodyText.data(using: .utf8),
                      !body.isEmpty else { continue }
                loaded.append(Entry(id: id, body: body))
            }
            if loaded.count > maxEntries {
                loaded.removeFirst(loaded.count - maxEntries)
            }
            entries = loaded
        } catch {
            // A corrupt file is treated as empty; the next write replaces it.
            logWarn("Offline error file could not be read, starting empty: \(error.localizedDescription)")
        }
    }

    private func persist() {
        guard let url = fileURL() else { return }

        var list: [[String: String]] = []
        list.reserveCapacity(entries.count)
        for entry in entries {
            guard let bodyText = String(data: entry.body, encoding: .utf8) else { continue }
            list.append(["id": entry.id, "body": bodyText])
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: list)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url, options: .atomic)

            // An atomic write replaces the file, so the flag is set every time.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)
        } catch {
            logError("Failed to write offline errors: \(error.localizedDescription)")
        }
    }

    private func fileURL() -> URL? {
        if let explicit = explicitFileURL { return explicit }
        if didResolveFileURL { return resolvedFileURL }
        didResolveFileURL = true

        resolvedFileURL = Self.defaultDirectory()?.appendingPathComponent(Self.fileName)
        if resolvedFileURL == nil {
            logWarn("No writable directory for offline errors; offline storage is inactive")
        }
        return resolvedFileURL
    }

    /// Application Support, or Caches where Application Support cannot be
    /// written (tvOS).
    private static func defaultDirectory() -> URL? {
        let fileManager = FileManager.default
        let candidates: [FileManager.SearchPathDirectory] = [.applicationSupportDirectory, .cachesDirectory]

        for candidate in candidates {
            guard var directory = fileManager.urls(for: candidate, in: .userDomainMask).first else { continue }

            #if os(macOS)
            // Outside the sandbox these directories are shared by every app
            // of the user, so each app gets its own folder.
            let owner = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
            directory.appendPathComponent(owner, isDirectory: true)
            #endif

            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                continue
            }
            if fileManager.isWritableFile(atPath: directory.path) {
                return directory
            }
        }
        return nil
    }
}
