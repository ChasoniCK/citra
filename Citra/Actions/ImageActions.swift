import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO plumbing shared by the image conversions and tools.
enum ImageCodec {
    enum Failure: LocalizedError {
        case unreadable(URL)
        case encodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url): "“\(url.lastPathComponent)” is not a readable image."
            case .encodeFailed(let format): "Could not write \(format)."
            }
        }
    }

    /// Image types ImageIO can decode and encode on this Mac.
    static let decodable = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])
    static let encodable = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    static func isReadableImage(_ item: FileItem) -> Bool {
        !item.isDirectory && item.conforms(to: .image) && (decodable.contains(item.type.identifier) || item.conforms(to: .svg))
    }

    static func source(_ url: URL) throws -> CGImageSource {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetType(src) != nil, CGImageSourceGetCount(src) > 0 {
            return src
        }
        guard let src = rasterized(url) else { throw Failure.unreadable(url) }
        return src
    }

    /// SVG, which ImageIO cannot read, drawn by AppKit; the long side is at least 1024 px so icons don't come out tiny.
    private static func rasterized(_ url: URL) -> CGImageSource? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = max(1, 1024 / max(image.size.width, image.size.height))
        let width = max(1, Int((image.size.width * scale).rounded())), height = max(1, Int((image.size.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, // safe: sRGB always exists
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let previous = NSGraphicsContext.current // thread-local, so drawing off the main thread is fine
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.current = previous
        let png = NSMutableData()
        guard let cgImage = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        return CGImageDestinationFinalize(dest) ? CGImageSourceCreateWithData(png, nil) : nil
    }

    /// First image of `url` re-encoded as `type` next to it, metadata and orientation kept;
    /// transparency is flattened on white for formats without alpha.
    static func convert(_ url: URL, to type: UTType, fileExtension: String, quality: Double = 0.9,
                        nameSuffix: String? = nil) async throws -> URL {
        let src = try source(url)
        let name = url.deletingPathExtension().lastPathComponent
        return try await OutputWriter.write(into: OutputWriter.destination(for: url),
                                            baseName: nameSuffix.map { "\(name) \($0)" } ?? name,
                                            pathExtension: fileExtension) { temp in
            guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, type.identifier as CFString, 1, nil)
            else { throw Failure.encodeFailed(fileExtension.uppercased()) }
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality,
                kCGImageDestinationBackgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            ]
            CGImageDestinationAddImageFromSource(dest, src, 0, options as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw Failure.encodeFailed(fileExtension.uppercased()) }
        }
    }
}

/// "PNG → JPEG" for one type, "3 files → JPEG" otherwise.
func conversionText(_ items: [FileItem], to target: String) -> String {
    let labels = Set(items.map(\.typeLabel))
    return labels.count == 1 && items.count == 1 ? "\(labels.first!) → \(target)" // safe: count checked
        : labels.count == 1 ? "\(items.count) \(labels.first!) → \(target)" // safe: count checked
        : "\(items.count) files → \(target)"
}

/// Any image ImageIO can decode (or SVG) → JPEG / PNG / HEIC / TIFF / AVIF / BMP (first frame of multi-image files).
struct ImageConverter: FileAction {
    let target: UTType
    let fileExtension: String
    let title: String

    static let all = [
        ImageConverter(target: .jpeg, fileExtension: "jpg", title: "JPEG"),
        ImageConverter(target: .png, fileExtension: "png", title: "PNG"),
        ImageConverter(target: .heic, fileExtension: "heic", title: "HEIC"),
        ImageConverter(target: .tiff, fileExtension: "tiff", title: "TIFF"),
        ImageConverter(target: UTType("public.avif")!, fileExtension: "avif", title: "AVIF"), // safe: system type since macOS 13
        ImageConverter(target: .bmp, fileExtension: "bmp", title: "BMP"),
    ]

    var id: String { "image.\(target.preferredFilenameExtension ?? fileExtension)" }
    var isAvailable: Bool { ImageCodec.encodable.contains(target.identifier) }

    func isApplicable(to items: [FileItem]) -> Bool {
        items.allSatisfy { ImageCodec.isReadableImage($0) && !$0.conforms(to: target) }
    }

    func centerText(for items: [FileItem]) -> String? { conversionText(items, to: title) }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        progress.totalUnitCount = Int64(items.count)
        var outputs: [URL] = []
        for item in items {
            try Task.checkCancellation()
            let quality = target == .jpeg ? AppSettings.jpegQuality
                : target == .heic || target.identifier == "public.avif" ? AppSettings.heicQuality : 1
            outputs.append(try await ImageCodec.convert(item.url, to: target, fileExtension: fileExtension, quality: quality))
            progress.completedUnitCount += 1
        }
        return ActionResult(files: outputs)
    }
}

/// ImageIO cannot write WebP, so the user's `cwebp` (Homebrew `webp`) does; not offered without it.
struct WebPConverter: FileAction {
    let id = "image.webp"
    let title = "WEBP"
    static let cwebp: URL? = FFmpeg.searchPaths.map { URL(filePath: "\($0)/cwebp") }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }

    var isAvailable: Bool { Self.cwebp != nil }

    func isApplicable(to items: [FileItem]) -> Bool {
        items.allSatisfy { ImageCodec.isReadableImage($0) && !$0.conforms(to: .webP) }
    }

    func centerText(for items: [FileItem]) -> String? { conversionText(items, to: title) }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        guard let cwebp = Self.cwebp else {
            throw CocoaError(.executableNotLoadable, userInfo: [NSLocalizedDescriptionKey: "cwebp is not installed."])
        }
        progress.totalUnitCount = Int64(items.count)
        var outputs: [URL] = []
        for item in items {
            try Task.checkCancellation()
            // cwebp reads few formats and ignores EXIF orientation: hand it an upright PNG.
            let image = try ImageTools.upright(try ImageCodec.source(item.url), url: item.url)
            let png = FileManager.default.temporaryDirectory.appending(path: "citra-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: png) } // best effort: our own temp file
            guard let dest = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { throw ImageCodec.Failure.encodeFailed("WEBP") }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { throw ImageCodec.Failure.encodeFailed("WEBP") }
            outputs.append(try await OutputWriter.write(into: OutputWriter.destination(for: item.url),
                                                        baseName: item.url.deletingPathExtension().lastPathComponent,
                                                        pathExtension: "webp") { temp in
                try await ProcessRunner.run(cwebp, ["-quiet", "-q", "\(Int(AppSettings.jpegQuality * 100))", png.path, "-o", temp.path])
            })
            progress.completedUnitCount += 1
        }
        return ActionResult(files: outputs)
    }
}

/// One PDF page per image, page size from the image's DPI (72 when unknown).
struct ImageToPDF: FileAction {
    let id = "image.pdf"
    let title = "PDF"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(ImageCodec.isReadableImage) }

    func centerText(for items: [FileItem]) -> String? { conversionText(items, to: title) }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        progress.totalUnitCount = Int64(items.count)
        var outputs: [URL] = []
        for item in items {
            try Task.checkCancellation()
            let src = try ImageCodec.source(item.url)
            guard let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw ImageCodec.Failure.unreadable(item.url) }
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
            let dpi = (props[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
            let size = CGSize(width: Double(image.width) * 72 / dpi, height: Double(image.height) * 72 / dpi)
            outputs.append(try await OutputWriter.write(into: OutputWriter.destination(for: item.url),
                                                        baseName: item.url.deletingPathExtension().lastPathComponent,
                                                        pathExtension: "pdf") { temp in
                var box = CGRect(origin: .zero, size: size)
                guard let pdf = CGContext(temp as CFURL, mediaBox: &box, nil) else { throw ImageCodec.Failure.encodeFailed("PDF") }
                pdf.beginPDFPage(nil)
                pdf.draw(image, in: box)
                pdf.endPDFPage()
                pdf.closePDF()
            })
            progress.completedUnitCount += 1
        }
        return ActionResult(files: outputs)
    }
}

