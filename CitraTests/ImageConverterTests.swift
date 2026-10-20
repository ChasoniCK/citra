import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Citra

struct ImageConverterTests {
    let folder: TestFolder
    init() throws { folder = try TestFolder() }

    func ids(_ items: [FileItem]) -> [String] { Registry.actions(for: .conversion, items: items).map(\.id) }
    func item(_ url: URL) -> FileItem { FileTypeResolver.resolve(url) }
    func action(_ id: String) throws -> any FileAction { try #require(Registry.all(for: .conversion).first { $0.id == id }) }

    func rgb(at x: Int, _ y: Int, of url: URL) throws -> (UInt8, UInt8, UInt8) {
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var px = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = try #require(CGContext(data: &px, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let i = (y * image.width + x) * 4 // bitmap memory row 0 is the top row
        return (px[i], px[i + 1], px[i + 2])
    }

    func typeOf(_ url: URL) -> String? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    // MARK: Applicability

    @Test func pngOffersEveryOtherFormat() throws {
        #expect(ids([item(try folder.image("a.png"))]) == ["image.jpeg", "image.heic", "image.tiff", "image.pdf"])
    }

    @Test func jpegOffersPNGButNotJPEG() throws {
        #expect(ids([item(try folder.image("a.jpg", type: .jpeg))]) == ["image.png", "image.heic", "image.tiff", "image.pdf"])
    }

    @Test func mixedSelectionOffersOnlyWhatSuitsAll() throws {
        let items = [item(try folder.image("a.png")), item(try folder.image("b.jpg", type: .jpeg))]
        #expect(ids(items) == ["image.heic", "image.tiff", "image.pdf"])
    }

    @Test func foldersAndTextGetNoImageConversions() throws {
        let dir = folder.url.appending(path: "D", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(ids([item(dir)]).allSatisfy { !$0.hasPrefix("image.") })
        #expect(ids([item(try folder.file("t.txt", Data("x".utf8)))]).allSatisfy { !$0.hasPrefix("image.") })
    }

    @Test func centerTextNamesSourceAndTarget() throws {
        let png = item(try folder.image("a.png"))
        #expect(try action("image.jpeg").centerText(for: [png]) == "PNG → JPEG")
        #expect(try action("image.jpeg").centerText(for: [png, item(try folder.image("b.tiff", type: .tiff))]) == "2 files → JPEG")
    }

    // MARK: Conversion on real files

    @Test func pngToJPEGIsValidKeepsOriginalAndFlattensOnWhite() async throws {
        let png = try folder.image("img.png")
        let before = try Data(contentsOf: png)
        let progress = Progress(totalUnitCount: 1)
        let out = try await action("image.jpeg").perform(items: [item(png)], progress: progress).files
        #expect(out.map(\.lastPathComponent) == ["img.jpg"])
        #expect(typeOf(out[0]) == UTType.jpeg.identifier)
        #expect(try Data(contentsOf: png) == before)
        let (r, g, b) = try rgb(at: 2, 2, of: out[0])
        #expect(r > 240 && g > 240 && b > 240)
        #expect(progress.fractionCompleted == 1)
    }

    @Test(arguments: [("image.heic", UTType.heic, "img.heic"), ("image.tiff", .tiff, "img.tiff")])
    func pngToOtherEncoders(_ c: (String, UTType, String)) async throws {
        let out = try await action(c.0).perform(items: [item(try folder.image("img.png"))], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == [c.2])
        #expect(typeOf(out[0]) == c.1.identifier)
    }

    @Test func jpegToPNG() async throws {
        let out = try await action("image.png").perform(items: [item(try folder.image("img.jpg", type: .jpeg))], progress: Progress()).files
        #expect(typeOf(out[0]) == UTType.png.identifier)
    }

    @Test func imageToPDFHasOnePageOfTheImageSize() async throws {
        let out = try await action("image.pdf").perform(items: [item(try folder.image("img.png"))], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == ["img.pdf"])
        let doc = try #require(CGPDFDocument(out[0] as CFURL))
        #expect(doc.numberOfPages == 1)
        let box = try #require(doc.page(at: 1)).getBoxRect(.mediaBox)
        #expect(box.size == CGSize(width: 16, height: 16))
    }

    @Test func everyItemIsConvertedAndNamesNeverCollide() async throws {
        let a = try folder.image("a.png"), b = try folder.image("b.png")
        _ = try folder.file("a.jpg", Data("taken".utf8))
        let out = try await action("image.jpeg").perform(items: [item(a), item(b)], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == ["a 2.jpg", "b.jpg"])
    }

    @Test func corruptImageIsAClearErrorAndLeavesNothing() async throws {
        let fake = try folder.file("fake.png", Data("not an image".utf8))
        await #expect(throws: ImageCodec.Failure.self) {
            try await action("image.jpeg").perform(items: [FileItem(url: fake, type: .png)], progress: Progress()).files
        }
        #expect(try folder.names() == ["fake.png"])
    }
}
