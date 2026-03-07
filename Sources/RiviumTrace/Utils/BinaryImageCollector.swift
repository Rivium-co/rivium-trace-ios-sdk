import Foundation
import MachO

/// Collects binary image information needed for server-side dSYM symbolication
public enum BinaryImageCollector {

    /// A single loaded binary image
    public struct BinaryImage {
        public let uuid: String
        public let name: String
        public let path: String
        public let loadAddress: UInt64
        public let size: UInt64
        public let arch: String

        public func toDictionary() -> [String: Any] {
            return [
                "uuid": uuid,
                "name": name,
                "path": path,
                "load_address": String(format: "0x%llx", loadAddress),
                "size": size,
                "arch": arch
            ]
        }
    }

    /// Collect all loaded binary images
    public static func collectAll() -> [BinaryImage] {
        var images: [BinaryImage] = []
        let count = _dyld_image_count()

        for i in 0..<count {
            guard let header = _dyld_get_image_header(i) else { continue }
            guard let nameCStr = _dyld_get_image_name(i) else { continue }

            let imagePath = String(cString: nameCStr)
            let shortName = (imagePath as NSString).lastPathComponent
            let slide = _dyld_get_image_vmaddr_slide(i)

            // Load address = header pointer value
            let loadAddr = UInt64(bitPattern: Int64(Int(bitPattern: header)))

            guard let uuid = extractUUID(from: header) else { continue }

            let textSize = extractTextSegmentSize(from: header)
            let arch = extractArch(from: header)

            images.append(BinaryImage(
                uuid: uuid,
                name: shortName,
                path: imagePath,
                loadAddress: loadAddr,
                size: textSize,
                arch: arch
            ))
        }

        return images
    }

    /// Collect only the app binary and its frameworks (skip system)
    public static func collectAppImages() -> [BinaryImage] {
        let bundlePath = Bundle.main.bundlePath
        return collectAll().filter { img in
            img.path.hasPrefix(bundlePath)
        }
    }

    /// Extract UUID from Mach-O header's LC_UUID load command
    private static func extractUUID(from header: UnsafePointer<mach_header>) -> String? {
        var cursor = UnsafeRawPointer(header)

        if header.pointee.magic == MH_MAGIC_64 {
            cursor = cursor.advanced(by: MemoryLayout<mach_header_64>.size)
        } else {
            cursor = cursor.advanced(by: MemoryLayout<mach_header>.size)
        }

        for _ in 0..<header.pointee.ncmds {
            let loadCmd = cursor.assumingMemoryBound(to: load_command.self)

            if loadCmd.pointee.cmd == LC_UUID {
                let uuidCmd = cursor.assumingMemoryBound(to: uuid_command.self)
                let bytes = uuidCmd.pointee.uuid
                return String(format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                    bytes.0, bytes.1, bytes.2, bytes.3,
                    bytes.4, bytes.5, bytes.6, bytes.7,
                    bytes.8, bytes.9, bytes.10, bytes.11,
                    bytes.12, bytes.13, bytes.14, bytes.15)
            }

            cursor = cursor.advanced(by: Int(loadCmd.pointee.cmdsize))
        }
        return nil
    }

    /// Extract __TEXT segment size from Mach-O header
    private static func extractTextSegmentSize(from header: UnsafePointer<mach_header>) -> UInt64 {
        var cursor = UnsafeRawPointer(header)
        let is64 = header.pointee.magic == MH_MAGIC_64
        cursor = cursor.advanced(by: is64 ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size)

        for _ in 0..<header.pointee.ncmds {
            let loadCmd = cursor.assumingMemoryBound(to: load_command.self)

            if is64 && loadCmd.pointee.cmd == LC_SEGMENT_64 {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self)
                let segName = withUnsafeBytes(of: seg.pointee.segname) { ptr in
                    String(cString: ptr.assumingMemoryBound(to: CChar.self).baseAddress!)
                }
                if segName == "__TEXT" {
                    return seg.pointee.vmsize
                }
            }

            cursor = cursor.advanced(by: Int(loadCmd.pointee.cmdsize))
        }
        return 0
    }

    /// Get architecture string from the Mach-O header
    private static func extractArch(from header: UnsafePointer<mach_header>) -> String {
        switch header.pointee.cputype {
        case CPU_TYPE_ARM64: return "arm64"
        case CPU_TYPE_ARM: return "arm"
        case CPU_TYPE_X86_64: return "x86_64"
        case CPU_TYPE_I386: return "x86"
        default: return "unknown"
        }
    }
}
