import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

#if canImport(WatchKit)
import WatchKit
#endif

/// Utility class to gather device and app information
public class DeviceInfo: @unchecked Sendable {

    /// Shared instance
    public static let shared = DeviceInfo()

    private init() {}

    /// Get user agent string for API requests
    public var userAgent: String {
        let appInfo = self.appInfo
        let deviceModel = self.deviceModel
        let osVersion = self.osVersion
        let platform = self.platform

        var ua = "RiviumTrace-SDK/\(RiviumTraceSDK.version) (\(platform) \(osVersion); \(deviceModel))"
        if let name = appInfo.name, let version = appInfo.version {
            ua += " \(name)/\(version)"
        }
        return ua
    }

    /// Get app name and version
    public var appInfo: (name: String?, version: String?, build: String?) {
        let bundle = Bundle.main
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return (name, version, build)
    }

    /// Get app version string
    public var appVersion: String? {
        return appInfo.version
    }

    /// Get device model
    public var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    /// Get OS version
    public var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// Get platform name
    public var platform: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #else
        return "Unknown"
        #endif
    }

    /// Get RiviumTrace platform identifier
    public var riviumTracePlatform: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #elseif os(tvOS)
        return "tvos"
        #elseif os(watchOS)
        return "watchos"
        #else
        return "apple_unknown"
        #endif
    }

    // MARK: - Error context (device_info / app_info)

    private let contextLock = NSLock()
    private var cachedDeviceInfo: [String: Any]?
    private var cachedAppInfo: [String: Any]?

    /// Device facts attached to every error and message as `extra.device_info`.
    ///
    /// Key names match the Android SDK where they apply (`device_model`,
    /// `device_manufacturer`, `os_version`, `locale`, `timezone`) so the
    /// dashboard reads both platforms the same way. Collected once and cached.
    ///
    /// Privacy: no device name (`UIDevice.name` is usually the owner's name),
    /// no identifierForVendor, no IP address.
    public var deviceInfo: [String: Any] {
        contextLock.lock()
        defer { contextLock.unlock() }
        if let cached = cachedDeviceInfo { return cached }

        var info: [String: Any] = [
            "device_model": deviceModel,
            "device_manufacturer": "Apple",
            "os_name": osName,
            "os_version": osVersion,
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
            "is_simulator": isSimulator,
            "memory_total_bytes": ProcessInfo.processInfo.physicalMemory
        ]
        #if os(iOS)
        info["device_type"] = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif

        cachedDeviceInfo = info
        return info
    }

    /// App facts attached to every error and message as `extra.app_info`.
    /// Collected once and cached; keys with no value in Info.plist are left out.
    public var appInfoDictionary: [String: Any] {
        contextLock.lock()
        defer { contextLock.unlock() }
        if let cached = cachedAppInfo { return cached }

        let app = appInfo
        var info: [String: Any] = [:]
        if let version = app.version { info["version"] = version }
        if let build = app.build { info["build_number"] = build }
        if let bundleId = Bundle.main.bundleIdentifier { info["package_name"] = bundleId }
        if let name = app.name { info["app_name"] = name }

        cachedAppInfo = info
        return info
    }

    /// OS name: "iOS" / "iPadOS" (UIDevice.systemName), "macOS", "tvOS".
    public var osName: String {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.systemName
        #else
        return platform
        #endif
    }

    /// Get a pseudo-unique device identifier (hashed for privacy)
    public var deviceIdentifier: String {
        #if os(iOS) || os(tvOS)
        if let uuid = UIDevice.current.identifierForVendor?.uuidString {
            return uuid
        }
        #endif

        // Fallback: generate from device properties
        let deviceString = "\(deviceModel)|\(osVersion)|\(platform)"
        return String(deviceString.hashValue, radix: 16)
    }

    /// Check if device is a simulator
    public var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Get screen size (iOS/tvOS only)
    #if os(iOS) || os(tvOS)
    public var screenSize: CGSize {
        return UIScreen.main.bounds.size
    }

    public var screenScale: CGFloat {
        return UIScreen.main.scale
    }
    #endif
}
