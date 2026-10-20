import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Citra

/// Renders the ring to PNGs for side-by-side review with `references/` — no screen capture involved.
/// Nothing lies behind the panel here; a flat Finder-like background stands in.
@MainActor
struct RingRenderTests {
    static let outDir = FileManager.default.temporaryDirectory.appending(path: "citra-ring-previews")

    static let tools = [("Compress", "arrow.down.right.and.arrow.up.left"), ("Metadata", "tag"), ("Mute", "speaker.slash"),
                        ("Trim", "scissors"), ("Crop", "crop"), ("Speed", "gauge.with.dots.needle.67percent"),
                        ("Snapshot", "camera"), ("Split", "film"), ("Redact", "eye.slash")]
        .map { RadialMenuItem(id: $0.0, title: $0.0, symbol: $0.1) }
    static let convert = ["MOV", "MKV", "AVI", "WMV", "GIF", "MP3"].map { RadialMenuItem(id: $0, title: $0, detail: "MP4 → \($0)") }
    static let fileActions = [("AirDrop", "dot.radiowaves.left.and.right"), ("Float", "square.stack"), ("Copy", "doc.on.doc"),
                              ("Move", "folder"), ("Copy Path", "link"), ("Terminal", "terminal")]
        .map { RadialMenuItem(id: $0.0, title: $0.0, symbol: $0.1) }
    static let twelve = (["JPEG", "PNG", "HEIC", "TIFF", "PDF", "WEBP", "GIF", "BMP", "ICO", "JP2", "TGA", "EXR"])
        .map { RadialMenuItem(id: $0, title: $0, detail: "PNG → \($0)") }

    static let cases: [(String, [RadialMenuItem], RingTarget?, String)] = [
        ("tools-9", tools, nil, "1 MB"),
        ("convert-6-hover", convert, .primary(3), "1 MB"),
        ("zip-convert-2", ["TAR", "TAR.GZ"].map { RadialMenuItem(id: $0, title: $0) }, nil, "3.2 MB"),
        ("zip-tools-1", [RadialMenuItem(id: "x", title: "Extract", symbol: "archivebox")], nil, "3.2 MB"),
        ("file-actions-6-hover", fileActions, .primary(4), "Folder"),
        ("overflow-12-more", twelve, .overflow(1), "1 MB"),
    ]

    @Test func renderReferenceCases() throws {
        try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.dark, .light] {
            for (name, items, hovered, idle) in Self.cases {
                let model = RadialMenuModel()
                model.items = items
                model.hovered = hovered
                model.idleCenterText = idle
                model.phase = .shown
                let background = scheme == .dark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color(red: 0.93, green: 0.93, blue: 0.94)
                let renderer = ImageRenderer(content: RadialMenuView(model: model).background(background).environment(\.colorScheme, scheme))
                renderer.scale = 2
                let image = try #require(renderer.cgImage, "\(name) did not render")
                #expect(image.width == Int(model.panelSide * 2))
                let url = Self.outDir.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png")
                let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(dest, image, nil)
                #expect(CGImageDestinationFinalize(dest))
            }
        }
    }
}
