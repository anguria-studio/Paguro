import Foundation

/// Bounds an untrusted ZIP before WebKit opens it. WebKit owns decompression and manifest parsing.
public enum ExtensionArchivePolicy {
    public static let maximumDownloadBytes = 64 * 1_024 * 1_024
    public static let maximumExpandedBytes = 256 * 1_024 * 1_024
    public static let maximumEntries = 8_192

    public static func validate(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard (22...maximumDownloadBytes).contains(bytes.count) else { throw Failure.invalidArchive }
        let lowerBound = max(0, bytes.count - 65_557)
        guard let end = stride(from: bytes.count - 22, through: lowerBound, by: -1).first(where: {
            bytes.u32($0) == 0x06054b50 && $0 + 22 + bytes.u16($0 + 20) == bytes.count
        }) else { throw Failure.invalidArchive }
        let count = bytes.u16(end + 10)
        let centralSize = bytes.u32(end + 12)
        let centralStart = bytes.u32(end + 16)
        guard bytes.u16(end + 4) == 0, bytes.u16(end + 6) == 0,
              bytes.u16(end + 8) == count, (1...maximumEntries).contains(count),
              centralStart + centralSize == end else { throw Failure.invalidArchive }

        var cursor = centralStart
        var expanded = 0
        var names: Set<String> = []
        var ranges: [Range<Int>] = []
        for _ in 0..<count {
            guard cursor + 46 <= end, bytes.u32(cursor) == 0x02014b50 else {
                throw Failure.invalidArchive
            }
            let flags = bytes.u16(cursor + 8)
            let method = bytes.u16(cursor + 10)
            let compressedSize = bytes.u32(cursor + 20)
            let expandedSize = bytes.u32(cursor + 24)
            let nameSize = bytes.u16(cursor + 28)
            let next = cursor + 46 + nameSize + bytes.u16(cursor + 30) + bytes.u16(cursor + 32)
            let mode = (bytes.u32(cursor + 38) >> 16) & 0o170000
            guard next <= end, nameSize > 0, nameSize <= 1_024,
                  flags & 1 == 0, method == 0 || method == 8,
                  mode == 0 || mode == 0o100000 || mode == 0o040000,
                  bytes.u16(cursor + 34) == 0 else { throw Failure.invalidArchive }
            let nameBytes = Array(bytes[(cursor + 46)..<(cursor + 46 + nameSize)])
            guard let name = String(bytes: nameBytes, encoding: .utf8), safePath(name),
                  names.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw Failure.invalidArchive
            }
            expanded += expandedSize
            guard expanded <= maximumExpandedBytes else { throw Failure.tooLarge }

            let local = bytes.u32(cursor + 42)
            guard local + 30 <= centralStart, bytes.u32(local) == 0x04034b50,
                  bytes.u16(local + 6) == flags, bytes.u16(local + 8) == method,
                  bytes.u16(local + 26) == nameSize else { throw Failure.invalidArchive }
            let payload = local + 30 + nameSize + bytes.u16(local + 28)
            guard payload + compressedSize <= centralStart,
                  Array(bytes[(local + 30)..<(local + 30 + nameSize)]) == nameBytes else {
                throw Failure.invalidArchive
            }
            ranges.append(local..<(payload + compressedSize))
            cursor = next
        }
        guard cursor == end, names.contains("manifest.json") else { throw Failure.invalidArchive }
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        for (first, second) in zip(sorted, sorted.dropFirst()) where first.overlaps(second) {
            throw Failure.invalidArchive
        }
    }

    private static func safePath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.dropLast().contains("") && !components.contains(".") && !components.contains("..")
    }

    public enum Failure: Error, LocalizedError {
        case invalidArchive, tooLarge
        public var errorDescription: String? {
            switch self {
            case .invalidArchive: "The extension package is invalid or contains unsafe files."
            case .tooLarge: "The extension package exceeds the prototype's size limit."
            }
        }
    }
}

private extension [UInt8] {
    func u16(_ offset: Int) -> Int { Int(self[offset]) | Int(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
}
