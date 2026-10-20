import AVFoundation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Citra

struct VideoTests {
    let folder: TestFolder
    init() throws { folder = try TestFolder() }

    func action(_ mode: MenuMode, _ id: String) throws -> any FileAction { try #require(Registry.all(for: mode).first { $0.id == id }) }

    func video(_ name: String, audio: Bool = true, type: AVFileType = .mp4) async throws -> FileItem {
        let url = folder.url.appending(path: name)
        try await TestVideo.make(url, audio: audio, fileType: type)
        return FileTypeResolver.resolve(url)
    }

    @Test func mp4OffersMOVAndM4AAndTools() async throws {
        let mp4 = try await video("clip.mp4")
        #expect(Registry.actions(for: .conversion, items: [mp4]).map(\.id) == ["video.mov", "video.m4a"])
        #expect(Registry.actions(for: .tools, items: [mp4]).map(\.id) == ["video.snapshot", "video.mute"])
        #expect(try action(.conversion, "video.mov").centerText(for: [mp4]) == "MP4 → MOV")
    }

    /// Tracks are not read before the drop (folder-access prompt), so a silent video is told at run time.
    @Test func silentVideoGetsAClearMessageAndNoFile() async throws {
        let silent = try await video("screen.mp4", audio: false)
        await #expect(throws: Video.Failure.self) {
            try await action(.conversion, "video.m4a").perform(items: [silent], progress: Progress())
        }
        await #expect(throws: Video.Failure.self) {
            try await action(.tools, "video.mute").perform(items: [silent], progress: Progress())
        }
        #expect(try folder.names() == ["screen.mp4"])
    }

    @Test func movIsNotOfferedForMOV() async throws {
        let mov = try await video("clip.mov", type: .mov)
        #expect(Registry.actions(for: .conversion, items: [mov]).map(\.id) == ["video.m4a"])
    }

    @Test func mp4ToMOVIsAValidMovieAndKeepsTheOriginal() async throws {
        let mp4 = try await video("clip.mp4")
        let before = try Data(contentsOf: mp4.url)
        let progress = Progress()
        let out = try await action(.conversion, "video.mov").perform(items: [mp4], progress: progress).files
        #expect(out.map(\.lastPathComponent) == ["clip.mov"])
        #expect(FileTypeResolver.resolve(out[0]).type == .quickTimeMovie)
        #expect(try await TestVideo.tracks(out[0], .video) == 1)
        #expect(try await TestVideo.tracks(out[0], .audio) == 1)
        #expect(try Data(contentsOf: mp4.url) == before)
        #expect(progress.fractionCompleted == 1)
    }

    @Test func toM4AKeepsOnlyAudio() async throws {
        let out = try await action(.conversion, "video.m4a").perform(items: [try await video("clip.mp4")], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == ["clip.m4a"])
        #expect(try await TestVideo.tracks(out[0], .audio) == 1)
        #expect(try await TestVideo.tracks(out[0], .video) == 0)
    }

    @Test func muteDropsTheAudioTrackOnly() async throws {
        let out = try await action(.tools, "video.mute").perform(items: [try await video("clip.mp4")], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == ["clip muted.mp4"])
        #expect(try await TestVideo.tracks(out[0], .video) == 1)
        #expect(try await TestVideo.tracks(out[0], .audio) == 0)
    }

    @Test func snapshotWritesAPNGFrame() async throws {
        let out = try await action(.tools, "video.snapshot").perform(items: [try await video("clip.mp4")], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == ["clip snapshot.png"])
        let src = try #require(CGImageSourceCreateWithURL(out[0] as CFURL, nil))
        #expect(CGImageSourceGetType(src) as String? == UTType.png.identifier)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 64)
    }

    @Test func brokenVideoIsAClearErrorAndLeavesNothing() async throws {
        let fake = FileItem(url: try folder.file("broken.mp4", Data("not a movie".utf8)), type: .mpeg4Movie)
        await #expect(throws: (any Error).self) {
            try await action(.conversion, "video.mov").perform(items: [fake], progress: Progress())
        }
        #expect(try folder.names() == ["broken.mp4"])
    }
}
