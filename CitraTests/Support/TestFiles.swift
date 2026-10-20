import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// A fresh temporary folder per test, with helpers that write small real files.
struct TestFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "citra-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String, _ data: Data) throws -> URL {
        let u = url.appending(path: name)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u)
        return u
    }

    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).filter { $0 != ".DS_Store" }.sorted()
    }

    /// 16×16 image: left half transparent, right half opaque red; `type` picks the encoder.
    /// `noise` fills it with random opaque pixels instead (hard to compress).
    func image(_ name: String, type: UTType = .png, width: Int = 16, height: Int = 16,
               properties: [CFString: Any] = [:], noise: Bool = false) throws -> URL {
        var px = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in width / 2..<width { let i = (y * width + x) * 4; px[i] = 255; px[i + 3] = 255 } }
        if noise { for i in px.indices { px[i] = i % 4 == 3 ? 255 : .random(in: 0...255) } }
        let ctx = try #require(CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, // safe: sRGB always exists
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let u = url.appending(path: name)
        let dest = try #require(CGImageDestinationCreateWithURL(u as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return u
    }
}
