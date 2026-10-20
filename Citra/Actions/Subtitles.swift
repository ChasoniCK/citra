import Foundation

/// SRT ⇄ WebVTT and a plain transcript. Both formats are blocks separated by blank lines; a block is a cue
/// only if it has a `-->` timing line, which skips the WEBVTT header and NOTE, STYLE and REGION blocks.
enum Subtitles {
    enum Failure: LocalizedError {
        case noCues(String)

        var errorDescription: String? {
            switch self {
            case .noCues(let name): "“\(name)” contains no subtitles (no “-->” timing lines)."
            }
        }
    }

    struct Cue: Equatable {
        var start: Int // milliseconds
        var end: Int
        var lines: [String]
    }

    /// UTF-8, else Foundation's guess (UTF-16 with BOM, Windows code pages), else Latin-1, which decodes anything.
    static func decode(_ data: Data) -> String {
        var text = String(data: data, encoding: .utf8)
        if text == nil {
            var converted: NSString?
            _ = NSString.stringEncoding(for: data, encodingOptions: [.allowLossyKey: false],
                                        convertedString: &converted, usedLossyConversion: nil)
            text = converted as String? ?? String(data: data, encoding: .isoLatin1)
        }
        let result = text ?? ""
        return result.first == "\u{FEFF}" ? String(result.dropFirst()) : result
    }

    static func parse(_ text: String) -> [Cue] {
        var cues: [Cue] = [], block: [String] = []
        func flush() {
            if let i = block.firstIndex(where: { $0.contains("-->") }), let (start, end) = timing(block[i]) {
                cues.append(Cue(start: start, end: end, lines: Array(block[(i + 1)...])))
            }
            block = []
        }
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.allSatisfy(\.isWhitespace) { flush() } else { block.append(String(line)) }
        }
        flush()
        return cues
    }

    /// `00:00:01,000 --> 00:00:02,500 X1:10` or `01.500 --> 00:03.000 align:start` → milliseconds; anything
    /// after the second timestamp (cue settings, SRT coordinates) is ignored.
    static func timing(_ line: String) -> (Int, Int)? {
        let stamp = /(?:(\d{1,4}):)?(\d{1,2}):(\d{1,2})(?:[,.](\d{1,3}))?/
        let times = line.matches(of: stamp).prefix(2).map { m in
            // safe: every group is 1–4 ASCII digits, which always parse
            let fraction = Int((String(m.4 ?? "0") + "00").prefix(3))!
            return ((Int(m.1 ?? "0")! * 60 + Int(m.2)!) * 60 + Int(m.3)!) * 1000 + fraction
        }
        return times.count == 2 ? (times[0], times[1]) : nil
    }

    static func srt(_ cues: [Cue]) -> String {
        cues.enumerated().map { i, cue in
            "\(i + 1)\n" + block(cue, ",") { unescaped(styled($0)) }
        }.joined(separator: "\n")
    }

    static func vtt(_ cues: [Cue]) -> String {
        "WEBVTT\n\n" + cues.map { block($0, ".") { escaped(styled($0)) } }.joined(separator: "\n")
    }

    /// Text only, without tags; a line repeated by the next cue (rolling auto-captions) is kept once.
    static func plainText(_ cues: [Cue]) -> String {
        var lines: [String] = []
        for line in cues.flatMap(\.lines) {
            let text = unescaped(line.replacing(/\{\\[^}]*\}|<[^>]*>/, with: "")).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty, text != lines.last { lines.append(text) }
        }
        return lines.map { $0 + "\n" }.joined()
    }

    private static func block(_ cue: Cue, _ separator: String, _ line: (String) -> String) -> String {
        "\(stamp(cue.start, separator)) --> \(stamp(cue.end, separator))\n" + cue.lines.map { line($0) + "\n" }.joined()
    }

    private static func stamp(_ ms: Int, _ separator: String) -> String {
        String(format: "%02d:%02d:%02d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60) + separator + String(format: "%03d", ms % 1000)
    }

    /// Keeps `<i> <b> <u>`, which both formats share; drops other tags (`<font>`, `<v Bob>`, `<c.x>`, karaoke
    /// timestamps) and SRT `{\an8}` overrides, which WebVTT would show as text.
    private static func styled(_ line: String) -> String {
        line.replacing(/\{\\[^}]*\}|<(?!\/?[ibu]>)[^>]*>/, with: "")
    }

    /// WebVTT text must escape `&` and any `<` that does not open a kept tag.
    private static func escaped(_ line: String) -> String {
        line.replacingOccurrences(of: "&", with: "&amp;").replacing(/<(?!\/?[ibu]>)/, with: "&lt;")
    }

    private static func unescaped(_ line: String) -> String {
        [("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&lrm;", ""), ("&rlm;", ""), ("&amp;", "&")]
            .reduce(line) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

/// SRT → VTT / TXT and VTT → SRT / TXT, by extension: subtitle files have no system type on many Macs.
struct SubtitleConverter: FileAction {
    let target: String
    static let all = ["srt", "vtt", "txt"].map(SubtitleConverter.init)

    var id: String { "subtitles.\(target)" }
    var title: String { target.uppercased() }

    func isApplicable(to items: [FileItem]) -> Bool {
        items.allSatisfy { item in
            let ext = item.url.pathExtension.lowercased()
            return !item.isDirectory && ["srt", "vtt"].contains(ext) && ext != target
        }
    }

    func centerText(for items: [FileItem]) -> String? { conversionText(items, to: title) }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        progress.totalUnitCount = Int64(items.count)
        var outputs: [URL] = []
        for item in items {
            try Task.checkCancellation()
            let cues = Subtitles.parse(Subtitles.decode(try Data(contentsOf: item.url)))
            guard !cues.isEmpty else { throw Subtitles.Failure.noCues(item.url.lastPathComponent) }
            let text = target == "srt" ? Subtitles.srt(cues) : target == "vtt" ? Subtitles.vtt(cues) : Subtitles.plainText(cues)
            outputs.append(try await OutputWriter.write(into: OutputWriter.destination(for: item.url),
                                                        baseName: item.url.deletingPathExtension().lastPathComponent,
                                                        pathExtension: target) { try Data(text.utf8).write(to: $0) })
            progress.completedUnitCount += 1
        }
        return ActionResult(files: outputs)
    }
}
