import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Citra

struct FileTypeResolverTests {
    let folder: TestFolder
    init() throws { folder = try TestFolder() }

    @Test func pngByContentAndExtension() throws {
        let item = FileTypeResolver.resolve(try folder.image("a.png"))
        #expect(item.type == .png)
        #expect(item.typeLabel == "PNG")
        #expect(!item.isDirectory)
    }

    /// Content wins over a wrong extension.
    @Test func pngNamedJpgIsPNG() throws {
        let png = try folder.image("a.png")
        let renamed = folder.url.appending(path: "photo.jpg")
        try FileManager.default.moveItem(at: png, to: renamed)
        #expect(FileTypeResolver.resolve(renamed).type == .png)
    }

    @Test func fileWithoutExtensionIsDetectedByContent() throws {
        let png = try folder.image("a.png")
        let bare = folder.url.appending(path: "noext")
        try FileManager.default.moveItem(at: png, to: bare)
        #expect(FileTypeResolver.resolve(bare).type == .png)
    }

    @Test func zipByMagic() throws {
        let zip = try folder.file("archive.bin", Data([0x50, 0x4B, 0x03, 0x04] + [UInt8](repeating: 0, count: 40)))
        #expect(FileTypeResolver.resolve(zip).type == .zip)
    }

    @Test func textFallsBackToMetadataOrExtension() throws {
        let txt = try folder.file("notes.txt", Data("hello".utf8))
        #expect(FileTypeResolver.resolve(txt).type.conforms(to: .plainText))
    }

    @Test func folderIsAFolder() throws {
        let dir = folder.url.appending(path: "Stuff", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let item = FileTypeResolver.resolve(dir)
        #expect(item.isDirectory)
        #expect(!item.isPackage)
        #expect(item.type == .folder)
    }

    @Test func appBundleIsAPackage() throws {
        let app = folder.url.appending(path: "Tool.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        let item = FileTypeResolver.resolve(app)
        #expect(item.isDirectory)
        #expect(item.isPackage)
        #expect(item.type.conforms(to: .applicationBundle))
    }

    @Test func movieBrandsAreTold() throws {
        func ftyp(_ brand: String) -> Data { Data([0, 0, 0, 0x18]) + Data("ftyp".utf8) + Data(brand.utf8) + Data(repeating: 0, count: 12) }
        #expect(FileTypeResolver.resolve(try folder.file("a", ftyp("qt  "))).type == .quickTimeMovie)
        #expect(FileTypeResolver.resolve(try folder.file("b", ftyp("isom"))).type == .mpeg4Movie)
        #expect(FileTypeResolver.resolve(try folder.file("c", ftyp("heic"))).type == .heic)
    }
}
