import Foundation
import Testing
@testable import Citra

struct OutputWriterTests {
    let folder: TestFolder
    init() throws { folder = try TestFolder() }

    @Test func writesUnderTheFreeNameAndLeavesNoTempFile() async throws {
        _ = try folder.file("photo.jpg", Data("old".utf8))
        let out = try await OutputWriter.write(into: folder.url, baseName: "photo", pathExtension: "jpg") { temp in
            try Data("new".utf8).write(to: temp)
        }
        #expect(out.lastPathComponent == "photo 2.jpg")
        #expect(try String(contentsOf: out, encoding: .utf8) == "new")
        #expect(try folder.names() == ["photo 2.jpg", "photo.jpg"])
    }

    @Test func failureLeavesNothingBehind() async throws {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await OutputWriter.write(into: folder.url, baseName: "x", pathExtension: "bin") { temp in
                try Data("partial".utf8).write(to: temp)
                throw Boom()
            }
        }
        #expect(try folder.names().isEmpty)
    }

    @Test func cancellationLeavesNothingBehind() async throws {
        let task = Task {
            try await OutputWriter.write(into: folder.url, baseName: "x", pathExtension: "bin") { temp in
                try Data("partial".utf8).write(to: temp)
                try await Task.sleep(for: .seconds(5))
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try folder.names().isEmpty)
    }

    @Test func directoriesAreMovedIntoPlaceToo() async throws {
        let out = try await OutputWriter.write(into: folder.url, baseName: "archive", pathExtension: "") { temp in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: temp.appending(path: "inside.txt"))
        }
        #expect(out.lastPathComponent == "archive")
        #expect(FileManager.default.fileExists(atPath: out.appending(path: "inside.txt").path))
        #expect(try folder.names() == ["archive"])
    }

    @Test func readOnlyFolderIsAClearError() async throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.url.path) }
        await #expect(throws: OutputWriter.Failure.self) {
            try await OutputWriter.write(into: folder.url, baseName: "x", pathExtension: "bin") { _ in }
        }
    }
}
