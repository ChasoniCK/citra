import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Citra

struct ImageConversionTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "citra-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// 16×16 PNG: left half fully transparent, right half opaque red.
    func makePNG(named name: String = "img.png") throws -> URL {
        let w = 16, h = 16
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 8..<w { let i = (y * w + x) * 4; px[i] = 255; px[i + 3] = 255 } }
        let ctx = try #require(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let url = dir.appending(path: name)
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    func rgb(at x: Int, _ y: Int, of url: URL) throws -> (UInt8, UInt8, UInt8) {
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var px = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = try #require(CGContext(data: &px, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let i = ((image.height - 1 - y) * image.width + x) * 4
        return (px[i], px[i + 1], px[i + 2])
    }

    @Test func writesJPEGNextToOriginalAndKeepsOriginal() throws {
        let png = try makePNG()
        let before = try Data(contentsOf: png)
        let out = try ImageConversion.convert(png, to: .jpeg, fileExtension: "jpg")
        #expect(out.lastPathComponent == "img.jpg")
        #expect(out.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        let src = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(CGImageSourceGetType(src) as String? == UTType.jpeg.identifier)
        #expect(try Data(contentsOf: png) == before)
    }

    @Test func flattensTransparencyOnWhite() throws {
        let out = try ImageConversion.convert(try makePNG(), to: .jpeg, fileExtension: "jpg")
        let (r, g, b) = try rgb(at: 2, 2, of: out)
        #expect(r > 240 && g > 240 && b > 240)
    }

    @Test func neverOverwritesAndLeavesNoTempFiles() throws {
        let png = try makePNG()
        _ = try ImageConversion.convert(png, to: .jpeg, fileExtension: "jpg")
        let second = try ImageConversion.convert(png, to: .jpeg, fileExtension: "jpg")
        #expect(second.lastPathComponent == "img 2.jpg")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["img 2.jpg", "img.jpg", "img.png"])
    }

    @Test func corruptSourceThrowsAndLeavesNothing() throws {
        let fake = dir.appending(path: "fake.png")
        try Data("not an image".utf8).write(to: fake)
        #expect(throws: ImageConversion.Failure.self) {
            try ImageConversion.convert(fake, to: .jpeg, fileExtension: "jpg")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["fake.png"])
    }
}
