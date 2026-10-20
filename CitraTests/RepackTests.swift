import Foundation
import Testing
@testable import Citra

struct RepackTests {
    let folder: TestFolder
    init() throws { folder = try TestFolder() }

    func action(_ id: String) throws -> any FileAction { try #require(Registry.all(for: .conversion).first { $0.id == id }) }

    func projectZip() throws -> FileItem {
        let src = folder.url.appending(path: "src", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: src.appending(path: "Project/docs"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: src.appending(path: "Project/docs/readme.txt"))
        try Data("#!/bin/sh\n".utf8).write(to: src.appending(path: "Project/run.sh"))
        try TestZip.system(["-qry", "../Project.zip", "Project"], in: src)
        try FileManager.default.removeItem(at: src)
        return FileTypeResolver.resolve(folder.url.appending(path: "Project.zip"))
    }

    func list(_ archive: URL, gzip: Bool) throws -> [String] {
        let p = Process(), out = Pipe()
        p.executableURL = URL(filePath: "/usr/bin/tar")
        p.arguments = [gzip ? "-tzf" : "-tf", archive.path]
        p.standardOutput = out
        try p.run()
        p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").map(String.init).sorted()
    }

    @Test func zipOffersTarAndTarGz() throws {
        let ids = Registry.actions(for: .conversion, items: [try projectZip()]).map(\.id)
        #expect(ids == ["zip.tar", "zip.targz"])
        #expect(try action("zip.targz").centerText(for: [try projectZip()]) == "ZIP → TAR.GZ")
    }

    @Test(arguments: [("zip.tar", false, "Project.tar"), ("zip.targz", true, "Project.tar.gz")])
    func repackKeepsTheTreeAndCleansUp(_ c: (String, Bool, String)) async throws {
        let zip = try projectZip()
        let out = try await action(c.0).perform(items: [zip], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == [c.2])
        let entries = try list(out[0], gzip: c.1)
        #expect(entries.contains("Project/docs/readme.txt"))
        #expect(entries.contains("Project/run.sh"))
        #expect(!entries.contains { $0.contains("._") })
        #expect(try folder.names() == ["Project.zip", c.2].sorted())
        if c.1 { #expect(FileTypeResolver.resolve(out[0]).type == .gzip) }
    }

    @Test func unsafeZipIsRefusedAndLeavesNothing() async throws {
        let bad = FileTypeResolver.resolve(try folder.file("bad.zip", TestZip.build([TestZip.file("../evil.txt")])))
        await #expect(throws: ZipExtractor.Failure.self) {
            try await action("zip.tar").perform(items: [bad], progress: Progress())
        }
        #expect(try folder.names() == ["bad.zip"])
    }

    @Test func failingToolReportsItsMessage() async throws {
        await #expect(throws: ProcessRunner.Failure.self) {
            try await ProcessRunner.run(URL(filePath: "/usr/bin/tar"), ["-tf", folder.url.appending(path: "missing.tar").path])
        }
    }

    @Test func cancellingStopsTheProcess() async throws {
        let task = Task { try await ProcessRunner.run(URL(filePath: "/bin/sleep"), ["10"]) }
        try await Task.sleep(for: .milliseconds(100))
        let start = Date.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date.now.timeIntervalSince(start) < 2)
    }
}
