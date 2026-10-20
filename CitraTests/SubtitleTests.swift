import Foundation
import Testing
@testable import Citra

struct SubtitleTests {
    @Test func srtBecomesVTT() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,500
        <i>Hello</i> & <font color="red">bye</font>
        {\\an8}Top

        2
        00:01:02,003 --> 01:00:00,000 X1:10 X2:20
        Second
        """
        #expect(Subtitles.vtt(Subtitles.parse(srt)) == """
        WEBVTT

        00:00:01.000 --> 00:00:02.500
        <i>Hello</i> &amp; bye
        Top

        00:01:02.003 --> 01:00:00.000
        Second

        """)
    }

    /// BOM, CRLF, a title on the header line, NOTE and STYLE blocks, a cue identifier, `mm:ss.fff`, cue settings,
    /// voice/class tags and entities.
    @Test func vttBecomesSRT() {
        let vtt = "\u{FEFF}WEBVTT - Title\r\n\r\nNOTE a note\r\nspanning lines\r\n\r\nSTYLE\r\n::cue { color: red }\r\n\r\n"
            + "intro\r\n00:01.500 --> 00:03.000 align:start position:10%\r\n<v Bob>Hi &amp; <c.yellow>welcome</c></v>\r\n"
            + "<b>bold</b> 1 &lt; 2\r\n\r\n00:00:04.000 --> 00:00:05.000\r\nNext\r\n"
        #expect(Subtitles.srt(Subtitles.parse(Subtitles.decode(Data(vtt.utf8)))) == """
        1
        00:00:01,500 --> 00:00:03,000
        Hi & welcome
        <b>bold</b> 1 < 2

        2
        00:00:04,000 --> 00:00:05,000
        Next

        """)
    }

    /// Auto-generated captions repeat each line in the next cue; the transcript keeps it once.
    @Test func rollingCaptionsBecomeAPlainTranscript() {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:02.000
        we are

        00:00:02.000 --> 00:00:03.000
        we are
        going home

        00:00:03.000 --> 00:00:04.000
        going home
        <00:00:03.500><c>now</c>
        """
        #expect(Subtitles.plainText(Subtitles.parse(vtt)) == "we are\ngoing home\nnow\n")
    }

    @Test func windows1251IsDecoded() throws {
        let data = try #require("1\n00:00:01,000 --> 00:00:02,000\nПривет, как дела?\n".data(using: .windowsCP1251))
        #expect(Subtitles.parse(Subtitles.decode(data)).first?.lines == ["Привет, как дела?"])
    }

    @Test func srtOffersVTTAndTXTAndWritesNextToIt() async throws {
        let folder = try TestFolder()
        let srt = FileTypeResolver.resolve(try folder.file("movie.srt", Data("1\n00:00:01,000 --> 00:00:02,000\nHi\n".utf8)))
        #expect(Registry.actions(for: .conversion, items: [srt]).map(\.id) == ["subtitles.vtt", "subtitles.txt"])
        let action = try #require(Registry.all(for: .conversion).first { $0.id == "subtitles.vtt" })
        let out = try await action.perform(items: [srt], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == ["movie.vtt"])
        #expect(try String(contentsOf: out[0], encoding: .utf8) == "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi\n")
    }

    @Test func fileWithoutCuesIsAClearErrorAndLeavesNothing() async throws {
        let folder = try TestFolder()
        let srt = FileTypeResolver.resolve(try folder.file("empty.srt", Data("just text\n".utf8)))
        let action = try #require(Registry.all(for: .conversion).first { $0.id == "subtitles.vtt" })
        await #expect(throws: Subtitles.Failure.self) { try await action.perform(items: [srt], progress: Progress()) }
        #expect(try folder.names() == ["empty.srt"])
    }
}
