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
        !item.isDirectory && item.conforms(to: .image) && decodable.contains(item.type.identifier)
    }

    static func source(_ url: URL) throws -> CGImageSource {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(src) != nil, CGImageSourceGetCount(src) > 0
        else { throw Failure.unreadable(url) }
        return src
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

/// Any image ImageIO can decode → JPEG / PNG / HEIC / TIFF (first frame of multi-image files).
struct ImageConverter: FileAction {
    let target: UTType
    let fileExtension: String
    let title: String

    static let all = [
        ImageConverter(target: .jpeg, fileExtension: "jpg", title: "JPEG"),
        ImageConverter(target: .png, fileExtension: "png", title: "PNG"),
        ImageConverter(target: .heic, fileExtension: "heic", title: "HEIC"),
        ImageConverter(target: .tiff, fileExtension: "tiff", title: "TIFF"),
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
            let quality = target == .jpeg ? AppSettings.jpegQuality : target == .heic ? AppSettings.heicQuality : 1
            outputs.append(try await ImageCodec.convert(item.url, to: target, fileExtension: fileExtension, quality: quality))
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

