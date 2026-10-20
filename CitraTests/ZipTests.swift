import Foundation
import Testing
@testable import Citra

struct ZipTests {
    let folder: TestFolder
    init() throws { folder = try TestFolder() }

    func tool(_ id: String) throws -> any FileAction { try #require(Registry.all(for: .tools).first { $0.id == id }) }
    func zip(_ name: String, _ entries: [TestZip.Entry], encrypted: Bool = false) throws -> FileItem {
        FileTypeResolver.resolve(try folder.file(name, TestZip.build(entries, encrypted: encrypted)))
    }

    /// A project folder zipped by /usr/bin/zip: nested file, executable script, empty folder, inner symlink.
    func realZip() throws -> FileItem {
        let src = folder.url.appending(path: "src", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: src.appending(path: "Project/docs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: src.appending(path: "Project/empty"), withIntermediateDirectories: true)
        try Data(String(repeating: "hello zip ", count: 500).utf8).write(to: src.appending(path: "Project/docs/readme.txt"))
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: src.appending(path: "Project/run.sh"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: src.appending(path: "Project/run.sh").path)
        try FileManager.default.createSymbolicLink(atPath: src.appending(path: "Project/link.txt").path, withDestinationPath: "docs/readme.txt")
        try TestZip.system(["-qry", "../Project.zip", "Project"], in: src)
        return FileTypeResolver.resolve(folder.url.appending(path: "Project.zip"))
    }

    // MARK: Applicability

    @Test func zipGetsExtractAndTest() throws {
        let ids = Registry.actions(for: .tools, items: [try zip("a.zip", [TestZip.file("a.txt")])]).map(\.id)
        #expect(ids == ["zip.extract", "zip.test"])
    }

    // MARK: Extract

    @Test func realArchiveExtractsIntoItsSingleTopFolder() async throws {
        let archive = try realZip()
        let before = try Data(contentsOf: archive.url)
        let out = try await tool("zip.extract").perform(items: [archive], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == ["Project"]) // single top folder: no Project.zip → Project/Project nesting
        let root = out[0]
        #expect(try String(contentsOf: root.appending(path: "docs/readme.txt"), encoding: .utf8).hasPrefix("hello zip"))
        let perms = try FileManager.default.attributesOfItem(atPath: root.appending(path: "run.sh").path)[.posixPermissions] as? Int
        #expect(perms == 0o755)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "empty").path, isDirectory: &isDir) && isDir.boolValue)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: root.appending(path: "link.txt").path) == "docs/readme.txt")
        #expect(try Data(contentsOf: archive.url) == before)
    }

    @Test func looseFilesExtractIntoAFolderNamedAfterTheArchive() async throws {
        let out = try await tool("zip.extract").perform(items: [try zip("loose.zip", [TestZip.file("a.txt"), TestZip.file("b/c.txt")])],
                                                         progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == ["loose"])
        #expect(FileManager.default.fileExists(atPath: out[0].appending(path: "b/c.txt").path))
    }

    @Test func macOSResourceForksAreSkipped() async throws {
        let out = try await tool("zip.extract").perform(items: [try zip("r.zip", [TestZip.file("a.txt"), TestZip.file("__MACOSX/._a.txt")])],
                                                         progress: Progress()).files
        #expect(try FileManager.default.contentsOfDirectory(atPath: out[0].path) == ["a.txt"])
    }

    // MARK: Path traversal and symlink escape

    @Test(arguments: ["../evil.txt", "/abs.txt", "a/../../evil.txt", "..\\evil.txt", "C:/evil.txt"])
    func traversalNamesAbortWithoutWritingAnything(_ name: String) async throws {
        let archive = try zip("bad.zip", [TestZip.file("ok.txt"), TestZip.file(name)])
        await #expect(throws: ZipExtractor.Failure.self) {
            try await tool("zip.extract").perform(items: [archive], progress: Progress())
        }
        #expect(try folder.names() == ["bad.zip"])
        #expect(!FileManager.default.fileExists(atPath: folder.url.deletingLastPathComponent().appending(path: "evil.txt").path))
    }

    @Test(arguments: ["/tmp", "../outside", "a/../../outside"])
    func symlinksLeavingTheArchiveAbort(_ target: String) async throws {
        let archive = try zip("link.zip", [TestZip.symlink("link", to: target), TestZip.file("link/evil.txt")])
        await #expect(throws: ZipExtractor.Failure.self) {
            try await tool("zip.extract").perform(items: [archive], progress: Progress())
        }
        #expect(try folder.names() == ["link.zip"])
        #expect(!FileManager.default.fileExists(atPath: "/tmp/evil.txt"))
    }

    /// The escaping link sits inside a real top folder, so stripping that folder must not hide it.
    @Test func nestedEscapingSymlinkAborts() async throws {
        let archive = try zip("nested.zip", [TestZip.Entry(name: "Top/", mode: 0o040755), TestZip.symlink("Top/link", to: "/tmp"),
                                             TestZip.file("Top/link/evil.txt")])
        await #expect(throws: ZipExtractor.Failure.self) {
            try await tool("zip.extract").perform(items: [archive], progress: Progress())
        }
        #expect(try folder.names() == ["nested.zip"])
    }

    @Test func symlinkInsideTheArchiveIsKept() async throws {
        let out = try await tool("zip.extract").perform(items: [try zip("in.zip", [TestZip.file("d/a.txt"), TestZip.symlink("d/b", to: "a.txt")])],
                                                         progress: Progress()).files
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: out[0].appending(path: "b").path) == "a.txt")
    }

    // MARK: Damage and encryption

    @Test func damagedEntryFailsExtractAndLeavesNothing() async throws {
        var bad = TestZip.file("a.txt", "content")
        bad.badCRC = true
        let archive = try zip("crc.zip", [bad])
        await #expect(throws: ZipReader.Failure.self) {
            try await tool("zip.extract").perform(items: [archive], progress: Progress())
        }
        #expect(try folder.names() == ["crc.zip"])
    }

    @Test func encryptedArchiveIsAClearError() async throws {
        let archive = try zip("enc.zip", [TestZip.file("a.txt")], encrypted: true)
        await #expect(throws: ZipReader.Failure.self) {
            try await tool("zip.extract").perform(items: [archive], progress: Progress())
        }
    }

    @Test func notAZipIsAClearError() async throws {
        let fake = FileItem(url: try folder.file("fake.zip", Data("nope".utf8)), type: .zip)
        await #expect(throws: ZipReader.Failure.self) {
            try await tool("zip.extract").perform(items: [fake], progress: Progress())
        }
    }

    // MARK: Test integrity

    @Test func testIntegrityReportsOKWithFileCount() async throws {
        let result = try await tool("zip.test").perform(items: [try realZip()], progress: Progress())
        #expect(result.files.isEmpty)
        #expect(result.message == "Project.zip is OK — 3 files")
    }

    @Test func testIntegrityFindsDamage() async throws {
        var bad = TestZip.file("a.txt", "content")
        bad.badCRC = true
        await #expect(throws: ZipReader.Failure.self) {
            try await tool("zip.test").perform(items: [try zip("crc.zip", [bad])], progress: Progress())
        }
    }
}
