import AppKit
import Testing
@testable import Citra

struct FileActionsTests {
    let folder: TestFolder
    init() throws { folder = try TestFolder() }

    func item(_ url: URL) -> FileItem { FileTypeResolver.resolve(url) }
    func dir(_ name: String) throws -> URL {
        let u = folder.url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func allSixInSpecOrderForFilesAndFolders() throws {
        let order = ["file.airdrop", "file.float", "file.copy", "file.move", "file.copyPath", "file.terminal"]
        #expect(Registry.actions(for: .fileActions, items: [item(try folder.image("a.png"))]).map(\.id) == order)
        #expect(Registry.actions(for: .fileActions, items: [item(try dir("D"))]).map(\.id) == order)
    }

    @Test @MainActor func copyPutsTheFilesThemselvesOnThePasteboard() async throws {
        let name = NSPasteboard.Name("citra-test-\(UUID().uuidString)")
        let a = try folder.image("a.png"), d = try dir("D")
        _ = try await CopyFilesAction(pasteboard: name).perform(items: [item(a), item(d)], progress: Progress())
        let urls = NSPasteboard(name: name).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(urls?.map(\.standardizedFileURL) == [a, d].map(\.standardizedFileURL))
        NSPasteboard(name: name).releaseGlobally()
    }

    @Test @MainActor func copyPathPutsOnePathPerLine() async throws {
        let name = NSPasteboard.Name("citra-test-\(UUID().uuidString)")
        let a = try folder.image("a b.png"), d = try dir("D")
        _ = try await CopyPathAction(pasteboard: name).perform(items: [item(a), item(d)], progress: Progress())
        #expect(NSPasteboard(name: name).string(forType: .string) == "\(a.path)\n\(d.path)")
        NSPasteboard(name: name).releaseGlobally()
    }

    @Test func terminalOpensFoldersThemselvesAndParentsOfFiles() throws {
        let d = try dir("Project"), a = try folder.image("a.png"), b = try folder.image("b.png")
        let app = try dir("Tool.app")
        let dirs = OpenInTerminal.directories(for: [item(d), item(a), item(b), item(app)])
        #expect(dirs.map(\.standardizedFileURL) == [d, folder.url].map(\.standardizedFileURL))
    }

    // MARK: Move

    func mover(_ choice: Mover.Choice = .stop, trashed: Box = Box()) -> Mover {
        Mover(resolve: { _ in choice }, trash: { url in trashed.urls.append(url); try FileManager.default.removeItem(at: url) })
    }

    final class Box: @unchecked Sendable { var urls: [URL] = [] }

    @Test func moveMovesIntoTheFolder() async throws {
        let a = try folder.file("a.txt", Data("A".utf8)), target = try dir("Target")
        let moved = try await mover().move([a], to: target, crossVolume: false)
        #expect(moved.map(\.lastPathComponent) == ["a.txt"])
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(try String(contentsOf: target.appending(path: "a.txt"), encoding: .utf8) == "A")
    }

    @Test func conflictKeepBothUsesAFreeName() async throws {
        let a = try folder.file("a.txt", Data("new".utf8)), target = try dir("Target")
        try Data("old".utf8).write(to: target.appending(path: "a.txt"))
        let moved = try await mover(.keepBoth).move([a], to: target, crossVolume: false)
        #expect(moved.map(\.lastPathComponent) == ["a 2.txt"])
        #expect(try String(contentsOf: target.appending(path: "a.txt"), encoding: .utf8) == "old")
    }

    @Test func conflictSkipLeavesBothUntouched() async throws {
        let a = try folder.file("a.txt", Data("new".utf8)), target = try dir("Target")
        try Data("old".utf8).write(to: target.appending(path: "a.txt"))
        let moved = try await mover(.skip).move([a], to: target, crossVolume: false)
        #expect(moved.isEmpty)
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(try String(contentsOf: target.appending(path: "a.txt"), encoding: .utf8) == "old")
    }

    @Test func conflictReplaceTrashesTheExistingOneFirst() async throws {
        let a = try folder.file("a.txt", Data("new".utf8)), target = try dir("Target")
        try Data("old".utf8).write(to: target.appending(path: "a.txt"))
        let trashed = Box()
        _ = try await mover(.replace, trashed: trashed).move([a], to: target, crossVolume: false)
        #expect(trashed.urls.map(\.lastPathComponent) == ["a.txt"])
        #expect(try String(contentsOf: target.appending(path: "a.txt"), encoding: .utf8) == "new")
    }

    @Test func conflictStopCancels() async throws {
        let a = try folder.file("a.txt", Data("new".utf8)), target = try dir("Target")
        try Data("old".utf8).write(to: target.appending(path: "a.txt"))
        await #expect(throws: CancellationError.self) { try await mover(.stop).move([a], to: target, crossVolume: false) }
        #expect(FileManager.default.fileExists(atPath: a.path))
    }

    /// Across volumes: copy completely, then delete the source.
    @Test func crossVolumeCopiesThenDeletesTheSource() async throws {
        let d = try dir("Folder")
        try Data("inside".utf8).write(to: d.appending(path: "f.txt"))
        let target = try dir("Target")
        let moved = try await mover().move([d], to: target, crossVolume: true)
        #expect(moved.map(\.lastPathComponent) == ["Folder"])
        #expect(!FileManager.default.fileExists(atPath: d.path))
        #expect(try String(contentsOf: target.appending(path: "Folder/f.txt"), encoding: .utf8) == "inside")
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path) == ["Folder"])
    }

    @Test func crossVolumeFailureKeepsTheSource() async throws {
        let a = try folder.file("a.txt", Data("A".utf8)), target = try dir("ReadOnly")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: target.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path) }
        await #expect(throws: (any Error).self) { try await mover().move([a], to: target, crossVolume: true) }
        #expect(FileManager.default.fileExists(atPath: a.path))
    }

    // MARK: Shelf

    @Test @MainActor func shelfAddsOnceRemovesAndClears() throws {
        let shelf = ShelfModel()
        let a = try folder.image("a.png"), b = try folder.image("b.png")
        shelf.add([a, b, a])
        #expect(shelf.items == [a, b])
        shelf.remove(a)
        #expect(shelf.items == [b])
        #expect(FileManager.default.fileExists(atPath: a.path))
        shelf.clear()
        #expect(shelf.items.isEmpty)
    }

    @Test func shelfSnapsToTheNearestSideEdgeOnlyWhenClose() {
        let visible = CGRect(x: 0, y: 25, width: 1000, height: 700)
        let size = CGSize(width: 240, height: 300)
        #expect(ShelfPlacement.snapped(CGRect(origin: CGPoint(x: 20, y: 200), size: size), in: visible).origin.x == 0)
        #expect(ShelfPlacement.snapped(CGRect(origin: CGPoint(x: 740, y: 200), size: size), in: visible).origin.x == 760)
        #expect(ShelfPlacement.snapped(CGRect(origin: CGPoint(x: 400, y: 200), size: size), in: visible).origin.x == 400)
        #expect(ShelfPlacement.snapped(CGRect(origin: CGPoint(x: 20, y: 650), size: size), in: visible).maxY == visible.maxY)
    }
}
