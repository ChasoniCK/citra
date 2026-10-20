import Foundation
import UniformTypeIdentifiers

/// A dropped file or folder with its resolved type.
struct FileItem: Sendable, Equatable {
    let url: URL
    let type: UTType
    var isDirectory = false
    var isPackage = false

    /// Short uppercase name for the UI: "PNG", "MP4", "ZIP".
    var typeLabel: String {
        (type.preferredFilenameExtension ?? url.pathExtension).uppercased()
    }

    func conforms(to other: UTType) -> Bool { type.conforms(to: other) }
}

/// Type by content first (magic bytes of the formats Citra acts on), then file-system metadata, then extension.
enum FileTypeResolver {
    static func resolve(_ url: URL) -> FileItem {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey])
        let isDirectory = values?.isDirectory ?? false
        let isPackage = values?.isPackage ?? false
        if isDirectory {
            return FileItem(url: url, type: isPackage ? (values?.contentType ?? .package) : .folder,
                            isDirectory: true, isPackage: isPackage)
        }
        let metadata = values?.contentType
        let byExtension = UTType(filenameExtension: url.pathExtension)
        if let sniffed = sniff(url) {
            // A more specific declared type that is still compatible (DOCX is a ZIP) wins.
            if let metadata, metadata != sniffed, metadata.conforms(to: sniffed) { return FileItem(url: url, type: metadata) }
            return FileItem(url: url, type: sniffed)
        }
        return FileItem(url: url, type: metadata ?? byExtension ?? .data)
    }

    /// Recognizes formats by their leading bytes; nil when unknown.
    static func sniff(_ url: URL) -> UTType? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512), !data.isEmpty else { return nil }
        let b = [UInt8](data)
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            b.count >= offset + prefix.count && Array(b[offset..<offset + prefix.count]) == prefix
        }
        func ascii(_ s: String, at offset: Int = 0) -> Bool { starts(Array(s.utf8), at: offset) }

        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if ascii("GIF87a") || ascii("GIF89a") { return .gif }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if ascii("%PDF-") { return .pdf }
        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) { return .zip }
        if starts([0x1F, 0x8B]) { return .gzip }
        if ascii("ustar", at: 257) { return UTType(filenameExtension: "tar") }
        if ascii("ftyp", at: 4), b.count >= 12 {
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            switch brand {
            case "heic", "heix", "heim", "heis", "mif1", "msf1": return .heic
            case "qt  ": return .quickTimeMovie
            case "M4A ", "M4B ": return .mpeg4Audio
            case "isom", "iso2", "iso4", "iso5", "iso6", "mp41", "mp42", "avc1", "M4V ", "M4VH", "dash": return .mpeg4Movie
            default: return nil
            }
        }
        return nil
    }
}
