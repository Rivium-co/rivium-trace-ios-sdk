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

    /// Get device information as a dictionary
    public var deviceInfo: [String: Any] {
        var info: [String: Any] = [
            "device_model": deviceModel,
            "os_version": osVersion,
            "platform": platform,
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier
        ]

        #if os(iOS)
        info["device_name"] = UIDevice.current.name
        info["system_name"] = UIDevice.current.systemName
        info["system_version"] = UIDevice.current.systemVersion
        info["device_type"] = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif

        #if os(macOS)
        info["device_name"] = Host.current().localizedName ?? "Mac"
        info["system_name"] = "macOS"
        #endif

        return info
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
