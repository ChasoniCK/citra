import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageConversion {
    enum Failure: LocalizedError {
        case unreadable(URL)
        case notWritable(URL)
        case encodeFailed(UTType)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url): "“\(url.lastPathComponent)” is not a readable image."
            case .notWritable(let dir): "No permission to write into “\(dir.lastPathComponent)”."
            case .encodeFailed(let type): "Could not encode \(type.localizedDescription ?? type.identifier)."
            }
        }
    }

    /// Re-encodes `source` as `type` next to it under a free name. The original is never touched;
    /// the result appears atomically (temp file in the same folder, then rename).
    static func convert(_ source: URL, to type: UTType, fileExtension: String) throws -> URL {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetType(src) != nil, CGImageSourceGetCount(src) > 0
        else { throw Failure.unreadable(source) }

        let fm = FileManager.default
        let dir = source.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: dir.path) else { throw Failure.notWritable(dir) }

        let temp = dir.appending(path: ".citra-\(UUID().uuidString).\(fileExtension)")
        do {
            guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, type.identifier as CFString, 1, nil)
            else { throw Failure.encodeFailed(type) }
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.9,
                kCGImageDestinationBackgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            ]
            CGImageDestinationAddImageFromSource(dest, src, 0, options as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw Failure.encodeFailed(type) }

            let target = FileNaming.uniqueURL(directory: dir, baseName: source.deletingPathExtension().lastPathComponent,
                                              pathExtension: fileExtension) { fm.fileExists(atPath: $0.path) }
            try fm.moveItem(at: temp, to: target) // refuses to overwrite if the name was taken meanwhile
            return target
        } catch {
            try? fm.removeItem(at: temp) // best effort; the original error is what matters
            throw error
        }
    }
}
