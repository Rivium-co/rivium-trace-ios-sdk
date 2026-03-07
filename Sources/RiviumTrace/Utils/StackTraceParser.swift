import Foundation

/// Parsed stack frame matching Sentry/Firebase industry-standard structure
struct StackFrame {
    let index: Int
    let function: String           // demangled, human-readable function name
    let module: String             // binary/library name (e.g. "MyApp", "UIKitCore")
    let package: String            // full path to binary image
    let instructionAddress: String // hex instruction address
    let symbolAddress: String?     // hex function start address
    let rawSymbol: String          // original mangled symbol
    let inApp: Bool                // true if this is user app code, false for system frames
    let offset: String?            // offset within function

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "function": function,
            "module": module,
            "package": package,
            "instruction_addr": instructionAddress,
            "in_app": inApp,
            "platform": "cocoa",
            "raw_symbol": rawSymbol
        ]
        if let symbolAddress = symbolAddress {
            dict["symbol_addr"] = symbolAddress
        }
        if let offset = offset {
            dict["offset"] = offset
        }
        return dict
    }
}

/// Parses and demangles iOS stack traces into Sentry-compatible structured frames
enum StackTraceParser {

    /// Known system framework prefixes — frames from these are NOT in_app
    private static let systemLibraries: Set<String> = [
        "SwiftUI", "SwiftUICore", "UIKitCore", "UIKit",
        "CoreFoundation", "Foundation", "libdispatch.dylib",
        "libsystem_kernel.dylib", "libsystem_pthread.dylib",
        "libswiftCore.dylib", "libswiftFoundation.dylib",
        "GraphicsServices", "Gestures", "UpdateCycle",
        "AttributeGraph", "Combine", "dyld"
    ]

    /// Parse raw call stack symbols into structured frames
    static func parse(_ symbols: [String]) -> [StackFrame] {
        return symbols.enumerated().compactMap { index, line in
            parseFrame(line, index: index)
        }
    }

    /// Format stack frames into a human-readable string (like Sentry/Firebase)
    static func formatReadable(_ symbols: [String]) -> String {
        let frames = parse(symbols)
        return frames.map { frame in
            let appTag = frame.inApp ? "[app]" : "     "
            let mod = frame.module.padding(toLength: 36, withPad: " ", startingAt: 0)
            return "\(String(format: "%2d", frame.index)) \(appTag) \(mod) \(frame.function)"
        }.joined(separator: "\n")
    }

    /// Parse a single stack frame line
    /// Format: "0   LibName   0x00000001 $s4Main... + 123"
    private static func parseFrame(_ line: String, index: Int) -> StackFrame? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let components = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard components.count >= 3 else {
            return StackFrame(
                index: index,
                function: trimmed,
                module: "unknown",
                package: "unknown",
                instructionAddress: "0x0",
                symbolAddress: nil,
                rawSymbol: trimmed,
                inApp: false,
                offset: nil
            )
        }

        let library = String(components[1])
        let address = String(components[2])

        var rawSymbol = ""
        var offset: String? = nil

        if components.count > 3 {
            let symbolParts = components[3...]

            if symbolParts.count >= 2,
               let lastTwo = symbolParts.suffix(2).first,
               lastTwo == "+" {
                let symbolOnly = symbolParts.dropLast(2)
                rawSymbol = symbolOnly.joined(separator: " ")
                offset = String(symbolParts.last!)
            } else {
                rawSymbol = symbolParts.joined(separator: " ")
            }
        }

        let demangled = demangle(rawSymbol)

        // Compute symbol_addr from instruction_addr - offset
        var symbolAddr: String? = nil
        if let offsetStr = offset, let offsetVal = UInt64(offsetStr),
           let instrAddr = UInt64(address.dropFirst(2), radix: 16) {
            symbolAddr = String(format: "0x%016llx", instrAddr - offsetVal)
        }

        // Determine if this is user app code
        // .debug.dylib is a user app debug dylib (e.g. RiviumTraceExample.debug.dylib)
        let isInApp = !systemLibraries.contains(library)
            && (!library.hasSuffix(".dylib") || library.contains(".debug.dylib"))
            && !library.hasPrefix("lib")

        return StackFrame(
            index: index,
            function: demangled,
            module: library,
            package: library, // full path not available from Thread.callStackSymbols
            instructionAddress: address,
            symbolAddress: symbolAddr,
            rawSymbol: rawSymbol,
            inApp: isInApp,
            offset: offset
        )
    }

    /// Capture raw return addresses from the current call stack as hex strings
    /// These are the actual instruction pointers needed for server-side dSYM symbolication
    static func captureRawAddresses() -> [String] {
        return Thread.callStackReturnAddresses.map { addr in
            String(format: "0x%llx", addr.uintValue)
        }
    }

    /// Capture raw return addresses from an NSException's call stack
    static func captureRawAddresses(from exception: NSException) -> [String] {
        return exception.callStackReturnAddresses.map { addr in
            String(format: "0x%llx", addr.uintValue)
        }
    }

    /// Demangle a Swift symbol into human-readable form
    static func demangle(_ symbol: String) -> String {
        if let demangled = swift_demangle(symbol) {
            return demangled
        }
        return symbol
    }

    /// Call Swift runtime's demangling function
    private static func swift_demangle(_ mangledName: String) -> String? {
        let trimmed = mangledName.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("$s") || trimmed.hasPrefix("_$s") ||
              trimmed.hasPrefix("$S") || trimmed.hasPrefix("_$S") ||
              trimmed.hasPrefix("_T") else {
            return nil
        }

        return mangledName.utf8CString.withUnsafeBufferPointer { buf in
            guard let ptr = buf.baseAddress else { return nil }
            let nameLength = strlen(ptr)

            // Call swift_demangle with correct 5-parameter signature:
            // mangledName, mangledNameLength, outputBuffer (nil = allocate), outputBufferSize, flags
            var outputSize: size_t = 0
            guard let result = swift_demangle_getDemangledName(ptr, nameLength, nil, &outputSize, 0) else {
                return nil
            }

            let str = String(cString: result)
            free(result)
            return str.isEmpty ? nil : str
        }
    }
}

// Swift runtime demangling C function
// Actual signature: char *swift_demangle(const char *mangledName, size_t mangledNameLength,
//                                        char *outputBuffer, size_t *outputBufferSize, uint32_t flags)
@_silgen_name("swift_demangle")
private func swift_demangle_getDemangledName(
    _ mangledName: UnsafePointer<CChar>,
    _ mangledNameLength: size_t,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ outputBufferSize: UnsafeMutablePointer<size_t>,
    _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?
