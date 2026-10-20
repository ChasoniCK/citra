import AVFoundation
import Foundation

/// A target container ffmpeg writes and the encoders it needs; the format is offered only when all exist.
struct FFmpegFormat: Sendable {
    /// Which dropped files the format is offered for.
    enum Input: Sendable { case video, videoOrAudio, audio }

    let title: String
    let ext: String
    let muxer: String
    let arguments: [String]
    let encoders: [String]
    var input = Input.video
    /// Other extensions of the same format, so `take.aif` is not offered AIFF.
    var aliases: [String] = []

    private static let h264 = ["-c:v", "libx264", "-crf", "20", "-preset", "medium", "-pix_fmt", "yuv420p",
                               "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
    /// Same limits as `VideoToGIF`, with a generated palette instead of the default 256 web colors.
    private static let gif = ["-t", "\(Int(VideoToGIF.maxSeconds))", "-vf",
                              "fps=\(Int(VideoToGIF.fps)),scale=\(Int(VideoToGIF.maxSide)):\(Int(VideoToGIF.maxSide))"
                                  + ":force_original_aspect_ratio=decrease,split[a][b];[a]palettegen[p];[b][p]paletteuse",
                              "-loop", "0"]

    static let all: [FFmpegFormat] = [
        // Video: for files AVFoundation cannot open; MOV, MP4 and GIF of the others go through AVFoundation.
        FFmpegFormat(title: "MP4", ext: "mp4", muxer: "mp4", arguments: h264, encoders: ["libx264", "aac"]),
        FFmpegFormat(title: "MOV", ext: "mov", muxer: "mov", arguments: h264, encoders: ["libx264", "aac"]),
        FFmpegFormat(title: "MKV", ext: "mkv", muxer: "matroska", arguments: ["-map", "0", "-c", "copy"], encoders: []),
        FFmpegFormat(title: "WEBM", ext: "webm", muxer: "webm",
                     arguments: ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus"],
                     encoders: ["libvpx-vp9", "libopus"]),
        FFmpegFormat(title: "AVI", ext: "avi", muxer: "avi",
                     arguments: ["-c:v", "mpeg4", "-q:v", "3", "-c:a", "libmp3lame", "-q:a", "3"],
                     encoders: ["mpeg4", "libmp3lame"]),
        FFmpegFormat(title: "WMV", ext: "wmv", muxer: "asf",
                     arguments: ["-c:v", "wmv2", "-b:v", "4M", "-c:a", "wmav2", "-b:a", "192k"],
                     encoders: ["wmv2", "wmav2"]),
        FFmpegFormat(title: "GIF", ext: "gif", muxer: "gif", arguments: gif, encoders: ["gif"]),
        // Audio: MP3 for video too; the rest only for audio files, so a video's ring does not spill into More.
        FFmpegFormat(title: "MP3", ext: "mp3", muxer: "mp3", arguments: ["-vn", "-c:a", "libmp3lame", "-q:a", "2"],
                     encoders: ["libmp3lame"], input: .videoOrAudio),
        FFmpegFormat(title: "M4A", ext: "m4a", muxer: "ipod", arguments: ["-vn", "-c:a", "aac", "-b:a", "256k"],
                     encoders: ["aac"], input: .audio),
        FFmpegFormat(title: "WAV", ext: "wav", muxer: "wav", arguments: ["-vn", "-c:a", "pcm_s16le"],
                     encoders: ["pcm_s16le"], input: .audio),
        FFmpegFormat(title: "FLAC", ext: "flac", muxer: "flac", arguments: ["-vn", "-c:a", "flac"],
                     encoders: ["flac"], input: .audio),
        // Homebrew's ffmpeg has no libvorbis; the built-in encoder is experimental and stereo-only.
        FFmpegFormat(title: "OGG", ext: "ogg", muxer: "ogg",
                     arguments: ["-vn", "-c:a", "vorbis", "-strict", "experimental", "-ac", "2", "-q:a", "6"],
                     encoders: ["vorbis"], input: .audio),
        FFmpegFormat(title: "OPUS", ext: "opus", muxer: "opus", arguments: ["-vn", "-c:a", "libopus", "-b:a", "160k"],
                     encoders: ["libopus"], input: .audio),
        FFmpegFormat(title: "AIFF", ext: "aiff", muxer: "aiff", arguments: ["-vn", "-c:a", "pcm_s16be"],
                     encoders: ["pcm_s16be"], input: .audio, aliases: ["aif"]),
        FFmpegFormat(title: "WMA", ext: "wma", muxer: "asf", arguments: ["-vn", "-c:a", "wmav2", "-b:a", "192k"],
                     encoders: ["wmav2"], input: .audio),
    ]
}

/// The user's own ffmpeg, if installed. It is not bundled (LGPL/GPL, size, signing); when it is missing
/// these formats are simply not offered, and Settings › Conversions says how to enable them.
struct FFmpeg: Sendable {
    let ffmpeg: URL
    let ffprobe: URL?
    let encoders: Set<String>

    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Looked up once; `AppDelegate` touches it at launch so the drag path never waits for it.
    static let current: FFmpeg? = locate()

    private static func locate() -> FFmpeg? {
        let fm = FileManager.default
        guard let dir = searchPaths.first(where: { fm.isExecutableFile(atPath: "\($0)/ffmpeg") }) else { return nil }
        let ffmpeg = URL(filePath: "\(dir)/ffmpeg")
        let probe = fm.isExecutableFile(atPath: "\(dir)/ffprobe") ? URL(filePath: "\(dir)/ffprobe") : nil
        return FFmpeg(ffmpeg: ffmpeg, ffprobe: probe, encoders: listEncoders(ffmpeg))
    }

    private static func listEncoders(_ ffmpeg: URL) -> Set<String> {
        let process = Process(), output = Pipe()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-encoders"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parseEncoders(String(decoding: data, as: UTF8.self))
    }

    /// Lines after the `------` separator look like ` V....D libx264   description`.
    static func parseEncoders(_ text: String) -> Set<String> {
        let lines = text.split(separator: "\n")
        guard let separator = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("---") }) else { return [] }
        return Set(lines[lines.index(after: separator)...].compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            return fields.count >= 2 ? String(fields[1]) : nil
        })
    }

    func supports(_ format: FFmpegFormat) -> Bool { Set(format.encoders).isSubset(of: encoders) }

    /// An argument array, never a shell string: any path is a single argument.
    static func arguments(input: URL, output: URL, format: FFmpegFormat) -> [String] {
        ["-hide_banner", "-nostdin", "-loglevel", "error", "-i", input.path] + format.arguments
            + ["-progress", "pipe:1", "-nostats", "-f", format.muxer, output.path]
    }

    /// `out_time_us=2500000` of a 5 s input → 0.5.
    static func progress(line: String, duration: Double) -> Double? {
        guard duration > 0, line.hasPrefix("out_time_us="), let micro = Double(line.dropFirst("out_time_us=".count))
        else { return nil }
        return min(1, max(0, micro / 1_000_000 / duration))
    }

    func duration(of url: URL) async -> Double {
        guard let ffprobe,
              let out = try? await ProcessRunner.run(ffprobe, ["-v", "error", "-show_entries", "format=duration",
                                                               "-of", "default=noprint_wrappers=1:nokey=1", url.path])
        else { return 0 }
        return Double(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Containers ffmpeg reads that the type system may not mark as movies (MKV, WebM, AVI, WMV…).
    static let videoExtensions: Set<String> = ["mkv", "webm", "avi", "wmv", "asf", "flv", "mpg", "mpeg", "m2ts", "mts",
                                               "ts", "3gp", "ogv", "vob", "mp4", "m4v", "mov"]

    static func accepts(_ item: FileItem, _ input: FFmpegFormat.Input) -> Bool {
        guard !item.isDirectory else { return false }
        let video = item.conforms(to: .movie) || videoExtensions.contains(item.url.pathExtension.lowercased())
        switch input {
        case .video: return video
        case .videoOrAudio: return video || item.conforms(to: .audio)
        case .audio: return item.conforms(to: .audio)
        }
    }
}

struct FFmpegConverter: FileAction {
    let format: FFmpegFormat

    var id: String { "ffmpeg.\(format.ext)" }
    var title: String { format.title }
    var isAvailable: Bool { FFmpeg.current?.supports(format) ?? false }

    func isApplicable(to items: [FileItem]) -> Bool {
        items.allSatisfy { item in
            let ext = item.url.pathExtension.lowercased()
            return FFmpeg.accepts(item, format.input) && ext != format.ext && !format.aliases.contains(ext)
                && !(["mp4", "mov", "gif"].contains(format.ext) && Video.isVideo(item)) // AVFoundation has its own
        }
    }

    func centerText(for items: [FileItem]) -> String? { conversionText(items, to: title) }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        guard let tool = FFmpeg.current else {
            throw CocoaError(.executableNotLoadable, userInfo: [NSLocalizedDescriptionKey: "ffmpeg is not installed."])
        }
        return try await Video.each(items, progress) { item, child in
            let duration = await tool.duration(of: item.url)
            return try await OutputWriter.write(into: OutputWriter.destination(for: item.url), baseName: Video.baseName(item),
                                                pathExtension: format.ext) { temp in
                try await ProcessRunner.run(tool.ffmpeg, FFmpeg.arguments(input: item.url, output: temp, format: format)) { line in
                    if let fraction = FFmpeg.progress(line: line, duration: duration) {
                        child.completedUnitCount = Int64(fraction * 100)
                    }
                }
            }
        }
    }
}
