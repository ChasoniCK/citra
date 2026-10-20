import Foundation
import Testing
@testable import Citra

private struct WriteFile: FileAction {
    let id = "write"
    let title = "Write"
    func isApplicable(to items: [FileItem]) -> Bool { true }
    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        let dir = items[0].url.deletingLastPathComponent()
        let out = try await OutputWriter.write(into: dir, baseName: "result", pathExtension: "txt") { temp in
            try Data("ok".utf8).write(to: temp)
        }
        progress.completedUnitCount = progress.totalUnitCount
        return ActionResult(files: [out])
    }
}

private struct Fail: FileAction {
    struct Broken: LocalizedError { var errorDescription: String? { "broken file" } }
    let id = "fail"
    let title = "Fail"
    func isApplicable(to items: [FileItem]) -> Bool { true }
    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult { throw Broken() }
}

private struct Slow: FileAction {
    let id = "slow"
    let title = "Slow"
    func isApplicable(to items: [FileItem]) -> Bool { true }
    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        let dir = items[0].url.deletingLastPathComponent()
        return ActionResult(files: [try await OutputWriter.write(into: dir, baseName: "slow", pathExtension: "txt") { temp in
            try Data("partial".utf8).write(to: temp)
            try await Task.sleep(for: .seconds(10))
        }])
    }
}

private final class MainThreadProbe: @unchecked Sendable { var ranOnMain: Bool? }

private struct Probe: FileAction {
    let id = "probe"
    let title = "Probe"
    let probe: MainThreadProbe
    func isApplicable(to items: [FileItem]) -> Bool { true }
    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        probe.ranOnMain = pthread_main_np() != 0
        return ActionResult()
    }
}

@MainActor
struct TaskManagerTests {
    let folder: TestFolder
    var finished: [(String, [URL])] = []
    init() throws { folder = try TestFolder() }

    func manager() -> (TaskManager, Box) {
        let box = Box()
        let tm = TaskManager(onFinished: { box.finished.append(($0, $1.files)) }, onFailed: { box.failed.append(($0, $1.localizedDescription)) })
        return (tm, box)
    }

    final class Box { var finished: [(String, [URL])] = []; var failed: [(String, String)] = [] }

    func item() throws -> FileItem { FileTypeResolver.resolve(try folder.file("input.txt", Data("in".utf8))) }

    @Test func finishedJobReportsItsOutputs() async throws {
        let (tm, box) = manager()
        await tm.run(WriteFile(), items: [try item()]).value
        #expect(box.finished.count == 1)
        #expect(box.finished.first?.1.map(\.lastPathComponent) == ["result.txt"])
        #expect(box.failed.isEmpty)
        #expect(tm.jobs.isEmpty)
    }

    @Test func failureIsReportedNotSwallowed() async throws {
        let (tm, box) = manager()
        await tm.run(Fail(), items: [try item()]).value
        #expect(box.failed.map(\.1) == ["broken file"])
        #expect(box.finished.isEmpty)
        #expect(tm.jobs.isEmpty)
    }

    @Test func cancelLeavesNoResultAndNoFiles() async throws {
        let (tm, box) = manager()
        let task = tm.run(Slow(), items: [try item()])
        #expect(tm.jobs.count == 1)
        try await Task.sleep(for: .milliseconds(100))
        tm.cancel(try #require(tm.jobs.first).id)
        await task.value
        #expect(box.finished.isEmpty && box.failed.isEmpty)
        #expect(tm.jobs.isEmpty)
        #expect(try folder.names() == ["input.txt"])
    }

    @Test func actionsRunOffTheMainThread() async throws {
        let (tm, _) = manager()
        let probe = MainThreadProbe()
        await tm.run(Probe(probe: probe), items: [try item()]).value
        #expect(probe.ranOnMain == false)
    }
}

struct RegistryTests {
    let folder: TestFolder
    init() throws { folder = try TestFolder() }

    func ids(_ mode: MenuMode, _ items: [FileItem]) -> [String] { Registry.actions(for: mode, items: items).map(\.id) }

    @Test func nothingForNoItems() {
        #expect(ids(.fileActions, []).isEmpty)
    }

    @Test func fileActionsApplyToFilesAndFolders() throws {
        let dir = folder.url.appending(path: "Dir", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = FileTypeResolver.resolve(try folder.image("a.png"))
        for items in [[png], [FileTypeResolver.resolve(dir)], [png, FileTypeResolver.resolve(dir)]] {
            #expect(ids(.fileActions, items).contains("file.copy"))
            #expect(ids(.fileActions, items).contains("file.copyPath"))
        }
    }
}
