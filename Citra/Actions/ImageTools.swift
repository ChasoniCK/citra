import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Helpers for tools that write a modified copy in the source's own format (`photo rotated.png`).
enum ImageTools {
    enum Failure: LocalizedError {
        case notSmaller(URL)

        var errorDescription: String? {
            switch self {
            case .notSmaller(let url): "“\(url.lastPathComponent)” is already compact: the compressed copy was not smaller, so it was discarded."
            }
        }
    }

    /// Readable, and ImageIO can write the same format back.
    static func isEditable(_ item: FileItem) -> Bool {
        ImageCodec.isReadableImage(item) && ImageCodec.encodable.contains(item.type.identifier)
    }

    /// First image with its EXIF orientation applied, at most `maxPixelSize` on the longest side.
    static func upright(_ src: CGImageSource, url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let longest = max(props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize ?? longest),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { throw ImageCodec.Failure.unreadable(url) }
        return image
    }

    /// Writes an upright `image` as `name <suffix>.<ext>` in the source's format; metadata kept, orientation reset.
    static func writeCopy(of url: URL, source src: CGImageSource, image: CGImage, suffix: String, quality: Double) async throws -> URL {
        let type = CGImageSourceGetType(src) ?? UTType.png.identifier as CFString
        var props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        props[kCGImagePropertyOrientation] = 1
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] { // stale after rotate/resize
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            props[kCGImagePropertyExifDictionary] = exif
        }
        props[kCGImageDestinationLossyCompressionQuality] = quality
        return try await OutputWriter.write(into: url.deletingLastPathComponent(),
                                            baseName: "\(url.deletingPathExtension().lastPathComponent) \(suffix)",
                                            pathExtension: url.pathExtension) { temp in
            guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else {
                throw ImageCodec.Failure.encodeFailed(url.pathExtension.uppercased())
            }
            CGImageDestinationAddImage(dest, image, props as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw ImageCodec.Failure.encodeFailed(url.pathExtension.uppercased()) }
        }
    }

    static func rotatedClockwise(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, let ctx = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(w))
        ctx.rotate(by: -.pi / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Runs `body` per item with progress and cancellation checks.
    static func each(_ items: [FileItem], _ progress: Progress, _ body: (FileItem) async throws -> URL) async throws -> [URL] {
        progress.totalUnitCount = Int64(items.count)
        var outputs: [URL] = []
        for item in items {
            try Task.checkCancellation()
            outputs.append(try await body(item))
            progress.completedUnitCount += 1
        }
        return outputs
    }
}

enum ResizePreset: Equatable, Sendable {
    case percent(Int)
    case longestSide(Int)
}

struct ResizeImage: FileAction {
    let id = "image.resize"
    let title = "Resize"
    let symbol: String? = "arrow.up.left.and.arrow.down.right"
    /// Asks for the size; nil cancels. Injected so tests skip the dialog.
    var choose: @Sendable () async -> ResizePreset? = { await ResizeDialog.ask() }

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(ImageTools.isEditable) }
    func centerText(for items: [FileItem]) -> String? { "Resize…" }

    func perform(items: [FileItem], progress: Progress) async throws -> [URL] {
        guard let preset = await choose() else { throw CancellationError() }
        return try await ImageTools.each(items, progress) { item in
            let src = try ImageCodec.source(item.url)
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
            let longest = max(props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
            let target = switch preset {
            case .percent(let p): max(1, longest * p / 100)
            case .longestSide(let side): min(side, longest)
            }
            let image = try ImageTools.upright(src, url: item.url, maxPixelSize: target)
            return try await ImageTools.writeCopy(of: item.url, source: src, image: image, suffix: "resized", quality: 0.92)
        }
    }
}

/// 90° clockwise, after applying any existing EXIF orientation to the pixels.
struct RotateImage: FileAction {
    let id = "image.rotate"
    let title = "Rotate"
    let symbol: String? = "rotate.right"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(ImageTools.isEditable) }
    func centerText(for items: [FileItem]) -> String? { "Rotate 90° right" }

    func perform(items: [FileItem], progress: Progress) async throws -> [URL] {
        try await ImageTools.each(items, progress) { item in
            let src = try ImageCodec.source(item.url)
            guard let rotated = ImageTools.rotatedClockwise(try ImageTools.upright(src, url: item.url))
            else { throw ImageCodec.Failure.encodeFailed(item.typeLabel) }
            return try await ImageTools.writeCopy(of: item.url, source: src, image: rotated, suffix: "rotated", quality: 0.95)
        }
    }
}

/// JPEG/HEIC re-encoded at quality 0.6; discarded with a message when it is not smaller.
struct CompressImage: FileAction {
    let id = "image.compress"
    let title = "Compress"
    let symbol: String? = "arrow.down.right.and.arrow.up.left"

    func isApplicable(to items: [FileItem]) -> Bool {
        items.allSatisfy { ImageTools.isEditable($0) && ($0.conforms(to: .jpeg) || $0.conforms(to: .heic)) }
    }

    func centerText(for items: [FileItem]) -> String? { "Compress (quality 60 %)" }

    func perform(items: [FileItem], progress: Progress) async throws -> [URL] {
        var notSmaller: URL?
        let outputs = try await ImageTools.each(items, progress) { item in
            let out = try await ImageCodec.convert(item.url, to: item.type, fileExtension: item.url.pathExtension,
                                                   quality: 0.6, nameSuffix: "compressed")
            let before = try item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let after = try out.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard after < before else {
                try FileManager.default.removeItem(at: out) // our own output, never the original
                notSmaller = notSmaller ?? item.url
                return out
            }
            return out
        }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if outputs.isEmpty, let url = notSmaller { throw ImageTools.Failure.notSmaller(url) }
        return outputs
    }
}

/// EXIF, GPS, IPTC and XMP dropped; orientation kept so the photo still shows upright.
/// Lossless copy where ImageIO supports it, otherwise a high-quality re-encode.
struct RemoveImageMetadata: FileAction {
    let id = "image.metadata"
    let title = "Metadata"
    let symbol: String? = "tag.slash"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(ImageTools.isEditable) }
    func centerText(for items: [FileItem]) -> String? { "Remove metadata" }

    func perform(items: [FileItem], progress: Progress) async throws -> [URL] {
        try await ImageTools.each(items, progress) { item in
            let src = try ImageCodec.source(item.url)
            let type = CGImageSourceGetType(src) ?? item.type.identifier as CFString
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
            let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
            return try await OutputWriter.write(into: item.url.deletingLastPathComponent(),
                                                baseName: "\(item.url.deletingPathExtension().lastPathComponent) no metadata",
                                                pathExtension: item.url.pathExtension) { temp in
                let options: [CFString: Any] = [
                    kCGImageDestinationMetadata: CGImageMetadataCreateMutable(),
                    kCGImageDestinationMergeMetadata: false,
                    kCGImageMetadataShouldExcludeGPS: true,
                    kCGImageDestinationOrientation: orientation,
                ]
                if let dest = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil),
                   CGImageDestinationCopyImageSource(dest, src, options as CFDictionary, nil),
                   Self.isClean(temp) {
                    return
                }
                guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil),
                      let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
                else { throw ImageCodec.Failure.encodeFailed(item.typeLabel) }
                CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: orientation,
                                                         kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
                guard CGImageDestinationFinalize(dest) else { throw ImageCodec.Failure.encodeFailed(item.typeLabel) }
            }
        }
    }

    /// The lossless copy is trusted only if GPS, EXIF and camera tags really are gone.
    private static func isClean(_ url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return false }
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        return p[kCGImagePropertyGPSDictionary] == nil && p[kCGImagePropertyIPTCDictionary] == nil
            && tiff[kCGImagePropertyTIFFMake] == nil && tiff[kCGImagePropertyTIFFModel] == nil
            && exif[kCGImagePropertyExifUserComment] == nil && exif[kCGImagePropertyExifDateTimeOriginal] == nil
    }
}

@MainActor
enum ResizeDialog {
    static let presets: [(String, ResizePreset)] = [
        ("50 %", .percent(50)), ("25 %", .percent(25)),
        ("Longest side 2560 px", .longestSide(2560)), ("Longest side 1920 px", .longestSide(1920)),
        ("Longest side 1280 px", .longestSide(1280)), ("Longest side 800 px", .longestSide(800)),
    ]
    private static let lastChoiceKey = "ResizePresetIndex"

    static func ask() -> ResizePreset? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Resize"
        alert.informativeText = "Size of the resized copy. The original is not changed."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        popup.addItems(withTitles: presets.map(\.0))
        popup.selectItem(at: min(UserDefaults.standard.integer(forKey: lastChoiceKey), presets.count - 1))
        alert.accessoryView = popup
        alert.addButton(withTitle: "Resize")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        UserDefaults.standard.set(popup.indexOfSelectedItem, forKey: lastChoiceKey)
        return presets[popup.indexOfSelectedItem].1
    }
}
