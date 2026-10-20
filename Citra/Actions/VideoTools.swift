import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// First 15 s at 10 fps, longest side ≤ 480 px, looping — AVFoundation frames written by ImageIO (no ffmpeg).
struct VideoToGIF: FileAction {
    let id = "video.gif"
    let title = "GIF"
    static let fps = 10.0
    static let maxSeconds = 15.0
    static let maxSide: CGFloat = 480

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(Video.isVideo) }
    func centerText(for items: [FileItem]) -> String? { conversionText(items, to: title) }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        try await Video.each(items, progress) { item, child in
            let asset = AVURLAsset(url: item.url)
            let duration = try await asset.load(.duration).seconds
            let count = max(1, Int(min(duration, Self.maxSeconds) * Self.fps))
            let times = (0..<count).map { CMTime(seconds: Double($0) / Self.fps, preferredTimescale: 600) }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: Self.maxSide, height: Self.maxSide)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

            return try await OutputWriter.write(into: OutputWriter.destination(for: item.url), baseName: Video.baseName(item),
                                                pathExtension: "gif") { temp in
                guard let gif = CGImageDestinationCreateWithURL(temp as CFURL, UTType.gif.identifier as CFString, count, nil)
                else { throw ImageCodec.Failure.encodeFailed("GIF") }
                CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / Self.fps]] as CFDictionary
                var last: CGImage?
                var added = 0
                for await result in generator.images(for: times) {
                    try Task.checkCancellation()
                    if case .success(_, let image, _) = result { last = image }
                    // A frame that fails to decode repeats the previous one, keeping the declared frame count.
                    guard let image = last else { continue }
                    CGImageDestinationAddImage(gif, image, frame)
                    added += 1
                    child.completedUnitCount = Int64(Double(added) / Double(count) * 100)
                }
                guard added == count, CGImageDestinationFinalize(gif) else {
                    throw Video.Failure.exportFailed(item.url.lastPathComponent, "could not read its frames.")
                }
            }
        }
    }
}

/// 720p MP4; discarded with a message when it is not smaller than the original.
struct CompressVideo: FileAction {
    let id = "video.compress"
    let title = "Compress"
    let symbol: String? = "arrow.down.right.and.arrow.up.left"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(Video.isVideo) }
    func centerText(for items: [FileItem]) -> String? { "Compress (720p MP4)" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        var notSmaller: URL?
        let outputs = try await Video.each(items, progress) { item, child in
            let out = try await OutputWriter.write(into: OutputWriter.destination(for: item.url),
                                                   baseName: Video.baseName(item, "compressed"), pathExtension: "mp4") { temp in
                try await Video.export(AVURLAsset(url: item.url), name: item.url.lastPathComponent, preset: AVAssetExportPreset1280x720,
                                       fallback: AVAssetExportPresetMediumQuality, as: .mp4, to: temp, progress: child)
            }
            let before = try item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let after = try out.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if after >= before {
                try FileManager.default.removeItem(at: out) // our own output, never the original
                notSmaller = notSmaller ?? item.url
            }
            return out
        }.files.filter { FileManager.default.fileExists(atPath: $0.path) }
        if outputs.isEmpty, let url = notSmaller { throw ImageTools.Failure.notSmaller(url) }
        return ActionResult(files: outputs)
    }
}

/// Keeps a range chosen in a dialog; streams are copied, so the cut lands on keyframes.
struct TrimVideo: FileAction {
    let id = "video.trim"
    let title = "Trim"
    let symbol: String? = "scissors"
    var choose: @Sendable (Double, String) async -> ClosedRange<Double>? = { await TrimDialog.ask(duration: $0, name: $1) }

    func isApplicable(to items: [FileItem]) -> Bool { items.count == 1 && items.allSatisfy(Video.isVideo) }
    func centerText(for items: [FileItem]) -> String? { "Trim…" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        try await Video.each(items, progress) { item, child in
            let asset = AVURLAsset(url: item.url)
            let duration = try await asset.load(.duration).seconds
            guard let range = await choose(duration, item.url.lastPathComponent) else { throw CancellationError() }
            return try await OutputWriter.write(into: OutputWriter.destination(for: item.url), baseName: Video.baseName(item, "trimmed"),
                                                pathExtension: item.url.pathExtension) { temp in
                try await Video.export(asset, name: item.url.lastPathComponent, preset: AVAssetExportPresetPassthrough,
                                       fallback: AVAssetExportPresetHighestQuality, as: Video.sameContainer(item), to: temp, progress: child) {
                    $0.timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                                               end: CMTime(seconds: range.upperBound, preferredTimescale: 600))
                }
            }
        }
    }
}

/// Plays faster or slower; audio keeps its pitch.
struct ChangeSpeed: FileAction {
    let id = "video.speed"
    let title = "Speed"
    let symbol: String? = "gauge.with.dots.needle.67percent"
    static let factors: [Double] = [0.5, 1.5, 2, 4]
    var choose: @Sendable () async -> Double? = {
        await PresetDialog.choose(title: "Speed", message: "Speed of the new copy. The original is not changed.",
                                  options: ChangeSpeed.factors.map { "\($0.formatted())×" }, confirm: "Change Speed",
                                  rememberAs: "SpeedPresetIndex").map { ChangeSpeed.factors[$0] }
    }

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(Video.isVideo) }
    func centerText(for items: [FileItem]) -> String? { "Change speed…" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        guard let factor = await choose() else { throw CancellationError() }
        return try await Video.each(items, progress) { item, child in
            let asset = AVURLAsset(url: item.url)
            let duration = try await asset.load(.duration)
            let composition = AVMutableComposition()
            for type in [AVMediaType.video, .audio] {
                for track in try await asset.loadTracks(withMediaType: type) {
                    guard let copy = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                    try copy.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
                    if type == .video { copy.preferredTransform = try await track.load(.preferredTransform) }
                }
            }
            composition.scaleTimeRange(CMTimeRange(start: .zero, duration: duration),
                                       toDuration: CMTimeMultiplyByFloat64(duration, multiplier: 1 / factor))
            return try await OutputWriter.write(into: OutputWriter.destination(for: item.url),
                                                baseName: Video.baseName(item, "\(factor.formatted())x"),
                                                pathExtension: item.url.pathExtension) { temp in
                try await Video.export(composition, name: item.url.lastPathComponent, preset: AVAssetExportPresetHighestQuality,
                                       as: Video.sameContainer(item), to: temp, progress: child) { $0.audioTimePitchAlgorithm = .spectral }
            }
        }
    }
}

/// Centered crop to a preset aspect ratio.
struct CropVideo: FileAction {
    let id = "video.crop"
    let title = "Crop"
    let symbol: String? = "crop"
    static let presets: [(String, Double)] = [("Square 1:1", 1), ("Widescreen 16:9", 16.0 / 9), ("Vertical 9:16", 9.0 / 16), ("Classic 4:3", 4.0 / 3)]
    var choose: @Sendable () async -> Double? = {
        await PresetDialog.choose(title: "Crop", message: "Centered crop of the new copy. The original is not changed.",
                                  options: CropVideo.presets.map(\.0), confirm: "Crop", rememberAs: "CropPresetIndex")
            .map { CropVideo.presets[$0].1 }
    }

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy(Video.isVideo) }
    func centerText(for items: [FileItem]) -> String? { "Crop…" }

    /// The centered rect of `aspect` (width / height) inside `size`, with even sides for the encoder.
    static func cropRect(in size: CGSize, aspect: Double) -> CGRect {
        var w = size.width, h = size.height
        if w / h > aspect { w = h * aspect } else { h = w / aspect }
        w = (w / 2).rounded(.down) * 2
        h = (h / 2).rounded(.down) * 2
        return CGRect(x: ((size.width - w) / 2).rounded(), y: ((size.height - h) / 2).rounded(), width: w, height: h)
    }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        guard let aspect = await choose() else { throw CancellationError() }
        return try await Video.each(items, progress) { item, child in
            let asset = AVURLAsset(url: item.url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw Video.Failure.noVideoTrack(item.url.lastPathComponent)
            }
            let (natural, transform, duration, frameRate) = try await (track.load(.naturalSize), track.load(.preferredTransform),
                                                                      asset.load(.duration), track.load(.nominalFrameRate))
            let shown = natural.applying(transform)
            let crop = Self.cropRect(in: CGSize(width: abs(shown.width), height: abs(shown.height)), aspect: aspect)

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(transform.concatenating(CGAffineTransform(translationX: -crop.minX, y: -crop.minY)), at: .zero)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
            instruction.layerInstructions = [layer]
            let composition = AVMutableVideoComposition()
            composition.renderSize = crop.size
            composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate > 0 ? frameRate.rounded() : 30))
            composition.instructions = [instruction]

            return try await OutputWriter.write(into: OutputWriter.destination(for: item.url), baseName: Video.baseName(item, "cropped"),
                                                pathExtension: item.url.pathExtension) { temp in
                try await Video.export(asset, name: item.url.lastPathComponent, preset: AVAssetExportPresetHighestQuality,
                                       as: Video.sameContainer(item), to: temp, progress: child) { $0.videoComposition = composition }
            }
        }
    }
}
