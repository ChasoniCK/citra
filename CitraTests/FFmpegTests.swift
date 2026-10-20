import Foundation
import Testing
@testable import Citra

struct FFmpegTests {
    @Test func progressLinesBecomeAFraction() {
        #expect(FFmpeg.progress(line: "out_time_us=2500000", duration: 5) == 0.5)
        #expect(FFmpeg.progress(line: "out_time_us=9000000", duration: 5) == 1)
        #expect(FFmpeg.progress(line: "frame=12", duration: 5) == nil)
        #expect(FFmpeg.progress(line: "out_time_us=N/A", duration: 5) == nil)
        #expect(FFmpeg.progress(line: "out_time_us=100", duration: 0) == nil)
    }

    @Test func encoderListIsParsedAfterTheSeparator() {
        let text = """
        Encoders:
         V..... = Video
         ------
         V....D libx264              libx264 H.264
         A....D libopus              libopus Opus
        """
        #expect(FFmpeg.parseEncoders(text) == ["libx264", "libopus"])
    }

    /// No shell: a path with spaces and quotes stays one argument, right after -i.
    @Test func pathsStayWholeArguments() throws {
        let input = URL(filePath: "/tmp/my \"odd\" clip; rm -rf ~.mp4"), output = URL(filePath: "/tmp/out.mkv")
        let mkv = try #require(FFmpegFormat.all.first { $0.ext == "mkv" })
        let args = FFmpeg.arguments(input: input, output: output, format: mkv)
        let i = try #require(args.firstIndex(of: "-i"))
        #expect(args[i + 1] == input.path)
        #expect(args.last == output.path)
        #expect(args.contains("pipe:1"))
    }
}
