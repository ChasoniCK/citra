import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Video {
    enum Failure: LocalizedError {
        case exportFailed(String, String)
        case noVideoTrack(String)
        case noAudioTrack(String)

        var errorDescription: String? {
            switch self {
            case .exportFailed(let name, let reason): "Could not process “\(name)”: \(reason)"
            case .noVideoTrack(let name): "“\(name)” has no video track."
            case .noAudioTrack(let name): "“\(name)” has no audio track, so there is nothing to extract or remove."
            }
        }
    }

    /// Movies AVFoundation can open (MP4, MOV, M4V…; not MKV/AVI/WebM).
    static let openable = Set(AVURLAsset.audiovisualTypes().map(\.rawValue))

    static func isVideo(_ item: FileItem) -> Bool {
        !item.isDirectory && item.conforms(to: .movie) && openable.contains(item.type.identifier)
    }

    /// Checked when the action runs: reading tracks before the drop would trigger a folder-access prompt.
    static func requireAudio(_ asset: AVURLAsset, _ item: FileItem) async throws {
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw Failure.noAudioTrack(item.url.lastPathComponent)
        }
    }

    /// Container type matching the source, for exports that keep the format.
    static func sameContainer(_ item: FileItem) -> AVFileType { item.conforms(to: .quickTimeMovie) ? .mov : .mp4 }

    /// Exports `asset` to `url`, preferring `preset` and falling back to `fallback` when it is not compatible.
    static func export(_ asset: AVAsset, name: String, preset: String, fallback: String? = nil, as type: AVFileType,
                       to url: URL, progress: Progress) async throws {
        var chosen = preset
        if !(await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: type)), let fallback {
            chosen = fallback
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: chosen) else {
            throw Failure.exportFailed(name, "this file cannot be exported (unsupported codec or damaged file).")
        }
        let states = session.states(updateInterval: 0.1) // Sendable, unlike the session itself
        let watcher = Task {
            for await state in states {
                if case .exporting(let p) = state { progress.completedUnitCount = Int64(p.fractionCompleted * 100) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: url, as: type)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw Failure.exportFailed(name, (error as NSError).localizedFailureReason ?? error.localizedDescription)
        }
        progress.completedUnitCount = 100
    }

    /// Runs `body` per item with a 100-unit child progress each.
    static func each(_ items: [FileItem], _ progress: Progress, _ body: (FileItem, Progress) async throws -> URL) async throws -> ActionResult {
        progress.totalUnitCount = Int64(items.count) * 100
        var outputs: [URL] = []
        for item in items {
            try Task.checkCancellation()
            let child = Progress(totalUnitCount: 100, parent: progress, pendingUnitCount: 100)
            outputs.append(try await body(item, child))
        }
        return ActionResult(files: outputs)
    }

    static func baseName(_ item: FileItem, _ suffix: String? = nil) -> String {
        let name = item.url.deletingPathExtension().lastPathComponent
        return suffix.map { "\(name) \($0)" } ?? name
    }
}

/// Re-wraps into QuickTime without re-encoding when the codecs allow it.
struct VideoToMOV: FileAction {
    let id = "video.mov"
    let title = "MOV"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy { Video.isVideo($0) && !$0.conforms(to: .quickTimeMovie) } }
    func centerText(for items: [FileItem]) -> String? { conversionText(items, to: title) }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        try await Video.each(items, progress) { item, child in
            try await OutputWriter.write(into: item.url.deletingLastPathComponent(), baseName: Video.baseName(item), pathExtension: "mov") { temp in
                try await Video.export(AVURLAsset(url: item.url), name: item.url.lastPathComponent, preset: AVAssetExportPresetPassthrough,
                                       fallback: AVAssetExportPresetHighestQuality, as: .mov, to: temp, progress: child)
            }
        }
    }
}

/// The audio track as AAC in M4A.
struct VideoToM4A: FileAction {
    let id = "video.m4a"
    let title = "M4A"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(Video.isVideo) }
    func centerText(for items: [FileItem]) -> String? { conversionText(items, to: title) }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        try await Video.each(items, progress) { item, child in
            try await Video.requireAudio(AVURLAsset(url: item.url), item)
            return try await OutputWriter.write(into: item.url.deletingLastPathComponent(), baseName: Video.baseName(item), pathExtension: "m4a") { temp in
                try await Video.export(AVURLAsset(url: item.url), name: item.url.lastPathComponent, preset: AVAssetExportPresetAppleM4A,
                                       as: .m4a, to: temp, progress: child)
            }
        }
    }
}

/// Same container without the audio tracks, video copied as is.
struct MuteVideo: FileAction {
    let id = "video.mute"
    let title = "Mute"
    let symbol: String? = "speaker.slash"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(Video.isVideo) }
    func centerText(for items: [FileItem]) -> String? { "Remove audio" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        try await Video.each(items, progress) { item, child in
            let asset = AVURLAsset(url: item.url)
            try await Video.requireAudio(asset, item)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard !tracks.isEmpty else { throw Video.Failure.noVideoTrack(item.url.lastPathComponent) }
            let duration = try await asset.load(.duration)
            let composition = AVMutableComposition()
            for track in tracks {
                guard let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                else { continue }
                try copy.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
                copy.preferredTransform = try await track.load(.preferredTransform)
            }
            let type = Video.sameContainer(item)
            return try await OutputWriter.write(into: item.url.deletingLastPathComponent(), baseName: Video.baseName(item, "muted"),
                                                pathExtension: item.url.pathExtension) { temp in
                try await Video.export(composition, name: item.url.lastPathComponent, preset: AVAssetExportPresetPassthrough,
                                       fallback: AVAssetExportPresetHighestQuality, as: type, to: temp, progress: child)
            }
        }
    }
}

/// The frame at the middle of the video, upright, as PNG.
struct VideoSnapshot: FileAction {
    let id = "video.snapshot"
    let title = "Snapshot"
    let symbol: String? = "camera"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(Video.isVideo) }
    func centerText(for items: [FileItem]) -> String? { "Middle frame → PNG" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        try await Video.each(items, progress) { item, child in
            let asset = AVURLAsset(url: item.url)
            let image: CGImage
            do {
                let duration = try await asset.load(.duration)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                image = try await generator.image(at: CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2)).image
            } catch {
                throw Video.Failure.exportFailed(item.url.lastPathComponent, error.localizedDescription)
            }
            let out = try await OutputWriter.write(into: item.url.deletingLastPathComponent(), baseName: Video.baseName(item, "snapshot"),
                                                   pathExtension: "png") { temp in
                guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, UTType.png.identifier as CFString, 1, nil)
                else { throw ImageCodec.Failure.encodeFailed("PNG") }
                CGImageDestinationAddImage(dest, image, nil)
                guard CGImageDestinationFinalize(dest) else { throw ImageCodec.Failure.encodeFailed("PNG") }
            }
            child.completedUnitCount = 100
            return out
        }
    }
}
