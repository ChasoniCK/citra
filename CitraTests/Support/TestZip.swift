import Foundation
@testable import Citra

/// Builds small stored (uncompressed) ZIPs with arbitrary names, modes and symlinks — the malicious
/// archives a real zip tool refuses to produce.
enum TestZip {
    struct Entry {
        var name: String
        var data = Data()
        var mode: UInt32 = 0o100644
        var badCRC = false
    }

    static func file(_ name: String, _ text: String = "x") -> Entry { Entry(name: name, data: Data(text.utf8)) }
    static func symlink(_ name: String, to target: String) -> Entry { Entry(name: name, data: Data(target.utf8), mode: 0o120777) }

    static func build(_ entries: [Entry], encrypted: Bool = false) -> Data {
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        var out = Data(), central = Data()
        let flags = (1 << 11) | (encrypted ? 1 : 0)
        for e in entries {
            let name = Data(e.name.utf8)
            let crc = CRC32.checksum(e.data) &+ (e.badCRC ? 1 : 0)
            let offset = UInt32(out.count), size = UInt32(e.data.count)
            out += le32(0x0403_4B50) + le16(20) + le16(flags) + le16(0) + le16(0) + le16(0)
            out += le32(crc) + le32(size) + le32(size) + le16(name.count) + le16(0) + name + e.data
            central += le32(0x0201_4B50) + le16(0x031E) + le16(20) + le16(flags) + le16(0) + le16(0) + le16(0)
            central += le32(crc) + le32(size) + le32(size) + le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0)
            central += le32(e.mode << 16) + le32(offset) + name
        }
        let cdOffset = UInt32(out.count)
        out += central
        out += le32(0x0605_4B50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count)
        out += le32(UInt32(central.count)) + le32(cdOffset) + le16(0)
        return out
    }

    /// Runs `/usr/bin/zip` in `dir` (real DEFLATE entries, symlinks kept with -y).
    static func system(_ arguments: [String], in dir: URL) throws {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/zip")
        p.arguments = arguments
        p.currentDirectoryURL = dir
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
