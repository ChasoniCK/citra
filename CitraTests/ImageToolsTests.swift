import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Citra

struct ImageToolsTests {
    let folder: TestFolder
    init() throws { folder = try TestFolder() }

    func item(_ url: URL) -> FileItem { FileTypeResolver.resolve(url) }
    func tool(_ id: String) throws -> any FileAction { try #require(Registry.all(for: .tools).first { $0.id == id }) }
    func ids(_ items: [FileItem]) -> [String] { Registry.actions(for: .tools, items: items).map(\.id) }

    func props(_ url: URL) throws -> [CFString: Any] {
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
    }

    func size(_ url: URL) throws -> (Int, Int) {
        let p = try props(url)
        return (p[kCGImagePropertyPixelWidth] as? Int ?? -1, p[kCGImagePropertyPixelHeight] as? Int ?? -1)
    }

    /// Red channel at (x, y), y from the top, of the decoded (unoriented) pixels.
    func red(at x: Int, _ y: Int, of url: URL) throws -> UInt8 {
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var px = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = try #require(CGContext(data: &px, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return px[(y * image.width + x) * 4] // bitmap memory row 0 is the top row
    }

    @Test func imagesGetTheFourToolsInOrder() throws {
        #expect(ids([item(try folder.image("a.jpg", type: .jpeg))]) == ["image.resize", "image.rotate", "image.compress", "image.metadata"])
    }

    @Test func pngHasNoCompress() throws {
        #expect(!ids([item(try folder.image("a.png"))]).contains("image.compress"))
    }

    @Test func rotateTurnsClockwiseAndKeepsTheOriginal() async throws {
        // 16×8: right half red. Clockwise: the right half becomes the bottom half of an 8×16 image.
        let png = try folder.image("wide.png", width: 16, height: 8)
        let before = try Data(contentsOf: png)
        let out = try await tool("image.rotate").perform(items: [item(png)], progress: Progress())
        #expect(out.map(\.lastPathComponent) == ["wide rotated.png"])
        #expect(try size(out[0]) == (8, 16))
        #expect(try red(at: 4, 14, of: out[0]) == 255)
        #expect(try red(at: 4, 1, of: out[0]) == 0)
        #expect(try Data(contentsOf: png) == before)
    }

    @Test func rotateBakesAnExistingOrientationFirst() async throws {
        // Orientation 6 = shown rotated 90° clockwise already; one more turn shows it upside down, upright pixels.
        let jpg = try folder.image("o.jpg", type: .jpeg, width: 16, height: 8, properties: [kCGImagePropertyOrientation: 6])
        let out = try await tool("image.rotate").perform(items: [item(jpg)], progress: Progress())
        #expect(try size(out[0]) == (16, 8))
        #expect((try props(out[0])[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test func removeMetadataDropsGPSAndEXIFButKeepsOrientation() async throws {
        let jpg = try folder.image("geo.jpg", type: .jpeg, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 55.75, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Camera"],
        ])
        #expect(try props(jpg)[kCGImagePropertyGPSDictionary] != nil)
        let out = try await tool("image.metadata").perform(items: [item(jpg)], progress: Progress())
        #expect(out.map(\.lastPathComponent) == ["geo no metadata.jpg"])
        let p = try props(out[0])
        #expect(p[kCGImagePropertyGPSDictionary] == nil)
        #expect((p[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
        #expect((p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
        #expect(p[kCGImagePropertyOrientation] as? Int == 6)
    }

    @Test func compressMakesASmallerJPEG() async throws {
        let jpg = try folder.image("big.jpg", type: .jpeg, width: 256, height: 256,
                                   properties: [kCGImageDestinationLossyCompressionQuality: 1.0], noise: true)
        let out = try await tool("image.compress").perform(items: [item(jpg)], progress: Progress())
        #expect(out.map(\.lastPathComponent) == ["big compressed.jpg"])
        let a = try #require(try jpg.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let b = try #require(try out[0].resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(b < a)
    }

    @Test func compressThatDoesNotShrinkLeavesNothingAndSaysSo() async throws {
        // Noise at quality 0.1: re-encoding at 0.6 keeps more of it, so the copy grows.
        let jpg = try folder.image("small.jpg", type: .jpeg, width: 256, height: 256,
                                   properties: [kCGImageDestinationLossyCompressionQuality: 0.1], noise: true)
        await #expect(throws: ImageTools.Failure.self) {
            try await tool("image.compress").perform(items: [item(jpg)], progress: Progress())
        }
        #expect(try folder.names() == ["small.jpg"])
    }

    @Test func resizeByPercentAndByLongestSide() async throws {
        let png = try folder.image("r.png", width: 64, height: 32)
        let half = try await ResizeImage(choose: { .percent(50) }).perform(items: [item(png)], progress: Progress())
        #expect(half.map(\.lastPathComponent) == ["r resized.png"])
        #expect(try size(half[0]) == (32, 16))
        let side = try await ResizeImage(choose: { .longestSide(20) }).perform(items: [item(png)], progress: Progress())
        #expect(try size(side[0]) == (20, 10))
    }

    @Test func cancelledResizeDialogDoesNothing() async throws {
        let png = try folder.image("r.png")
        await #expect(throws: CancellationError.self) {
            try await ResizeImage(choose: { nil }).perform(items: [item(png)], progress: Progress())
        }
        #expect(try folder.names() == ["r.png"])
    }
}
