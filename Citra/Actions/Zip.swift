import Compression
import Foundation

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func update(_ crc: UInt32, _ bytes: UnsafeRawBufferPointer) -> UInt32 {
        var c = ~crc
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return ~c
    }

    static func checksum(_ data: Data) -> UInt32 { data.withUnsafeBytes { update(0, $0) } }
}

struct ZipEntry: Sendable {
    let name: String
    let method: UInt16
    let flags: UInt16
    let crc32: UInt32
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let localHeaderOffset: UInt64
    /// Unix mode from the external attributes when the archive was made on Unix/macOS, else 0.
    let unixMode: UInt32

    var isEncrypted: Bool { flags & 1 != 0 }
    var isSymlink: Bool { unixMode & 0o170000 == 0o120000 }
    var isDirectory: Bool { name.hasSuffix("/") || name.hasSuffix("\\") || unixMode & 0o170000 == 0o040000 }
}

/// Read-only ZIP access: central directory (with ZIP64 sizes and offsets), stored and DEFLATE entries
/// streamed with CRC-32 verification. No writes happen here; `ZipExtractor` decides where bytes go.
final class ZipReader {
    enum Failure: LocalizedError {
        case notZip(URL)
        case corrupt(String)
        case encrypted(String)
        case unsupportedMethod(String, UInt16)

        var errorDescription: String? {
            switch self {
            case .notZip(let url): "“\(url.lastPathComponent)” is not a readable ZIP archive."
            case .corrupt(let what): "The archive is damaged: \(what)."
            case .encrypted(let name): "“\(name)” is password-protected; encrypted archives are not supported."
            case .unsupportedMethod(let name, let m): "“\(name)” uses compression method \(m), which is not supported."
            }
        }
    }

    let url: URL
    private(set) var entries: [ZipEntry] = []
    private let handle: FileHandle
    private let size: UInt64

    init(url: URL) throws {
        self.url = url
        do {
            handle = try FileHandle(forReadingFrom: url)
            size = try handle.seekToEnd()
        } catch {
            throw Failure.notZip(url)
        }
        try readCentralDirectory()
    }

    deinit { try? handle.close() }

    private func read(_ offset: UInt64, _ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + UInt64(count) <= size else { throw Failure.corrupt("record outside the file") }
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else { throw Failure.corrupt("short read") }
        return [UInt8](data)
    }

    private func readCentralDirectory() throws {
        let tailLength = Int(min(size, 22 + 0xFFFF))
        guard tailLength >= 22 else { throw Failure.notZip(url) }
        let tailStart = size - UInt64(tailLength)
        let tail = try read(tailStart, tailLength)
        guard let eocd = stride(from: tail.count - 22, through: 0, by: -1).first(where: { tail.u32($0) == 0x0605_4B50 })
        else { throw Failure.notZip(url) }

        var count = UInt64(tail.u16(eocd + 10))
        var cdSize = UInt64(tail.u32(eocd + 12))
        var cdOffset = UInt64(tail.u32(eocd + 16))
        if count == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            // ZIP64: the locator sits right before the classic end record.
            let locator = tailStart + UInt64(eocd) - 20
            let loc = try read(locator, 20)
            guard loc.u32(0) == 0x0706_4B50 else { throw Failure.corrupt("missing ZIP64 locator") }
            let record = try read(loc.u64(8), 56)
            guard record.u32(0) == 0x0606_4B50 else { throw Failure.corrupt("missing ZIP64 end record") }
            count = record.u64(32)
            cdSize = record.u64(40)
            cdOffset = record.u64(48)
        }
        guard cdSize <= size, count <= cdSize / 46 + 1 else { throw Failure.corrupt("central directory size") }

        let cd = try read(cdOffset, Int(cdSize))
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= cd.count, cd.u32(p) == 0x0201_4B50 else { throw Failure.corrupt("central directory entry") }
            let madeBy = cd.u16(p + 4) >> 8
            let flags = cd.u16(p + 8)
            let method = cd.u16(p + 10)
            let crc = cd.u32(p + 16)
            var compressed = UInt64(cd.u32(p + 20))
            var uncompressed = UInt64(cd.u32(p + 24))
            let nameLength = Int(cd.u16(p + 28)), extraLength = Int(cd.u16(p + 30)), commentLength = Int(cd.u16(p + 32))
            let external = cd.u32(p + 38)
            var offset = UInt64(cd.u32(p + 42))
            guard p + 46 + nameLength + extraLength + commentLength <= cd.count else { throw Failure.corrupt("entry name") }
            let nameBytes = Array(cd[(p + 46)..<(p + 46 + nameLength)])
            let name = String(bytes: nameBytes, encoding: .utf8) ?? String(decoding: nameBytes, as: Unicode.ASCII.self)

            // ZIP64 extra field: the 32-bit fields that are saturated follow, in this order.
            var e = p + 46 + nameLength
            let extraEnd = e + extraLength
            while e + 4 <= extraEnd {
                let id = cd.u16(e), length = Int(cd.u16(e + 2))
                if id == 0x0001 {
                    var f = e + 4
                    if uncompressed == 0xFFFF_FFFF, f + 8 <= extraEnd { uncompressed = cd.u64(f); f += 8 }
                    if compressed == 0xFFFF_FFFF, f + 8 <= extraEnd { compressed = cd.u64(f); f += 8 }
                    if offset == 0xFFFF_FFFF, f + 8 <= extraEnd { offset = cd.u64(f) }
                }
                e += 4 + length
            }
            entries.append(ZipEntry(name: name, method: method, flags: flags, crc32: crc, compressedSize: compressed,
                                    uncompressedSize: uncompressed, localHeaderOffset: offset,
                                    unixMode: madeBy == 3 || madeBy == 19 ? external >> 16 : 0))
            p += 46 + nameLength + extraLength + commentLength
        }
    }

    /// Streams the entry's bytes into `sink`; throws if the data is damaged (size or CRC-32 mismatch).
    func extract(_ entry: ZipEntry, _ sink: (UnsafeRawBufferPointer) throws -> Void) throws {
        guard !entry.isEncrypted else { throw Failure.encrypted(entry.name) }
        let header = try read(entry.localHeaderOffset, 30)
        guard header.u32(0) == 0x0403_4B50 else { throw Failure.corrupt("local header of \(entry.name)") }
        var position = entry.localHeaderOffset + 30 + UInt64(header.u16(26)) + UInt64(header.u16(28))
        var remaining = entry.compressedSize
        var crc: UInt32 = 0
        var total: UInt64 = 0
        let chunk = 1 << 18

        func emit(_ bytes: UnsafeRawBufferPointer) throws {
            crc = CRC32.update(crc, bytes)
            total += UInt64(bytes.count)
            guard total <= entry.uncompressedSize else { throw Failure.corrupt("\(entry.name) is longer than declared") }
            try sink(bytes)
        }

        switch entry.method {
        case 0:
            while remaining > 0 {
                try Task.checkCancellation()
                let n = Int(min(remaining, UInt64(chunk)))
                let bytes = try read(position, n)
                position += UInt64(n)
                remaining -= UInt64(n)
                try bytes.withUnsafeBytes { try emit($0) }
            }
        case 8:
            try inflate(from: &position, remaining: &remaining, chunk: chunk, emit: emit)
        default:
            throw Failure.unsupportedMethod(entry.name, entry.method)
        }
        guard total == entry.uncompressedSize, crc == entry.crc32 else { throw Failure.corrupt("\(entry.name) failed its checksum") }
    }

    /// Raw DEFLATE (COMPRESSION_ZLIB has no zlib header, exactly what ZIP stores).
    private func inflate(from position: inout UInt64, remaining: inout UInt64, chunk: Int,
                         emit: (UnsafeRawBufferPointer) throws -> Void) throws {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        let source = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { stream.deallocate(); source.deallocate(); destination.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
        else { throw Failure.corrupt("cannot start decompression") }
        defer { compression_stream_destroy(stream) }
        stream.pointee.src_size = 0

        while true {
            try Task.checkCancellation()
            if stream.pointee.src_size == 0, remaining > 0 {
                let n = Int(min(remaining, UInt64(chunk)))
                let bytes = try read(position, n)
                bytes.withUnsafeBufferPointer { source.update(from: $0.baseAddress!, count: n) } // safe: n > 0
                position += UInt64(n)
                remaining -= UInt64(n)
                stream.pointee.src_ptr = UnsafePointer(source)
                stream.pointee.src_size = n
            }
            stream.pointee.dst_ptr = destination
            stream.pointee.dst_size = chunk
            let finalize = remaining == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(stream, finalize)
            let produced = chunk - stream.pointee.dst_size
            if produced > 0 { try emit(UnsafeRawBufferPointer(start: destination, count: produced)) }
            switch status {
            case COMPRESSION_STATUS_END: return
            case COMPRESSION_STATUS_OK:
                if produced == 0, stream.pointee.src_size == 0, remaining == 0 { throw Failure.corrupt("truncated data") }
            default: throw Failure.corrupt("bad compressed data")
            }
        }
    }
}

/// Writes a ZIP's contents under `root` and nowhere else.
/// - Every name is checked before anything is written: absolute paths, drive letters and `..` abort the whole extraction.
/// - Symlinks must resolve inside the root (checked lexically up front) and are created last,
///   so no file write can ever pass through one.
enum ZipExtractor {
    enum Failure: LocalizedError {
        case unsafePath(String)
        case escapingLink(String, String)

        var errorDescription: String? {
            switch self {
            case .unsafePath(let name): "The archive tries to write outside its folder (“\(name)”). Nothing was extracted."
            case .escapingLink(let name, let target): "The archive contains a link that points outside its folder (“\(name)” → “\(target)”). Nothing was extracted."
            }
        }
    }

    /// Normalized path components, or nil for names that must never be written.
    static func safeComponents(_ name: String) -> [String]? {
        let unified = name.replacingOccurrences(of: "\\", with: "/")
        guard !unified.hasPrefix("/"), !unified.contains("\0") else { return nil }
        let parts = unified.split(separator: "/").map(String.init).filter { $0 != "." }
        guard !parts.contains(".."), !(parts.first?.count == 2 && parts.first?.last == ":") else { return nil }
        return parts
    }

    /// Whether a link stored at `components` pointing at `target` stays inside the root, without following anything.
    static func staysInside(link components: [String], target: String) -> Bool {
        guard !target.hasPrefix("/"), !target.contains("\0") else { return false }
        var stack = Array(components.dropLast())
        for part in target.split(separator: "/") where part != "." {
            if part == ".." {
                if stack.isEmpty { return false }
                stack.removeLast()
            } else {
                stack.append(String(part))
            }
        }
        return true
    }

    /// The archive's single top-level folder, if everything lives inside one.
    static func singleRoot(_ zip: ZipReader) -> String? {
        let paths = zip.entries.compactMap { safeComponents($0.name) }.filter { !$0.isEmpty && $0.first != "__MACOSX" }
        guard let first = paths.first?.first, paths.allSatisfy({ $0.first == first }), paths.contains(where: { $0.count > 1 })
        else { return nil }
        // Only a real folder can be the root: a symlink or file named like it must stay in the plan and be checked.
        let rootIsFolder = zip.entries.allSatisfy { safeComponents($0.name) != [first] || ($0.isDirectory && !$0.isSymlink) }
        return rootIsFolder ? first : nil
    }

    static func extract(_ zip: ZipReader, into root: URL, stripping prefix: Int, progress: Progress) throws {
        let fm = FileManager.default
        var plan: [(ZipEntry, [String])] = []
        for entry in zip.entries {
            guard let components = safeComponents(entry.name) else { throw Failure.unsafePath(entry.name) }
            guard components.first != "__MACOSX" else { continue }
            let path = Array(components.dropFirst(prefix))
            if !path.isEmpty { plan.append((entry, path)) }
        }

        var links: [([String], String)] = []
        for (entry, path) in plan where entry.isSymlink {
            var target = Data()
            try zip.extract(entry) { target.append(contentsOf: $0) }
            let destination = String(decoding: target, as: UTF8.self)
            guard staysInside(link: path, target: destination) else { throw Failure.escapingLink(entry.name, destination) }
            links.append((path, destination))
        }

        progress.totalUnitCount = Int64(clamping: plan.reduce(0) { $0 + $1.0.uncompressedSize })
        func url(_ path: [String]) -> URL { path.reduce(root) { $0.appending(path: $1) } }

        for (entry, path) in plan where !entry.isSymlink {
            try Task.checkCancellation()
            let destination = url(path)
            if entry.isDirectory {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let mode = entry.unixMode & 0o777
            guard fm.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: mode == 0 ? 0o644 : Int(mode)])
            else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path]) }
            let out = try FileHandle(forWritingTo: destination)
            defer { try? out.close() }
            try zip.extract(entry) { bytes in
                try out.write(contentsOf: Data(bytes))
                progress.completedUnitCount += Int64(bytes.count)
            }
        }

        for (path, target) in links {
            let destination = url(path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
        }
    }
}

struct ExtractArchive: FileAction {
    let id = "zip.extract"
    let title = "Extract"
    let symbol: String? = "archivebox"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy { !$0.isDirectory && $0.type == .zip } }
    func centerText(for items: [FileItem]) -> String? { "Extract" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        var outputs: [URL] = []
        for item in items {
            try Task.checkCancellation()
            let zip = try ZipReader(url: item.url)
            let root = ZipExtractor.singleRoot(zip)
            let child = Progress(totalUnitCount: 1, parent: progress, pendingUnitCount: 1)
            outputs.append(try await OutputWriter.write(into: OutputWriter.destination(for: item.url),
                                                        baseName: root ?? item.url.deletingPathExtension().lastPathComponent,
                                                        pathExtension: "") { temp in
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
                try ZipExtractor.extract(zip, into: temp, stripping: root == nil ? 0 : 1, progress: child)
            })
        }
        return ActionResult(files: outputs)
    }
}

/// Decompresses every entry and checks its CRC-32 without writing anything.
struct TestArchive: FileAction {
    let id = "zip.test"
    let title = "Test"
    let symbol: String? = "checkmark.seal"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy { !$0.isDirectory && $0.type == .zip } }
    func centerText(for items: [FileItem]) -> String? { "Test integrity" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        var lines: [String] = []
        progress.totalUnitCount = Int64(items.count)
        for item in items {
            let zip = try ZipReader(url: item.url)
            var files = 0
            for entry in zip.entries where !entry.isDirectory {
                try zip.extract(entry) { _ in }
                files += 1
            }
            lines.append("\(item.url.lastPathComponent) is OK — \(files) file\(files == 1 ? "" : "s")")
            progress.completedUnitCount += 1
        }
        return ActionResult(message: lines.joined(separator: "\n"))
    }
}

private extension Array where Element == UInt8 {
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
    func u64(_ i: Int) -> UInt64 { UInt64(u32(i)) | UInt64(u32(i + 4)) << 32 }
}
