import CoreGraphics
import Foundation
import Testing
@testable import Citra

struct Stage5Tests {
    let folder: TestFolder
    init() throws { folder = try TestFolder() }

    @Test func trimTimesParse() {
        #expect(TimeText.seconds("1:05.5") == 65.5)
        #expect(TimeText.seconds("90") == 90)
        #expect(TimeText.seconds("1:02:03") == 3723)
        #expect(TimeText.seconds("1:75") == nil)
        #expect(TimeText.seconds("-1") == nil)
        #expect(TimeText.seconds("abc") == nil)
        #expect(TimeText.string(65.5) == "1:05.5")
    }

    @Test func cropIsCenteredWithEvenSides() {
        #expect(CropVideo.cropRect(in: CGSize(width: 1920, height: 1080), aspect: 1) == CGRect(x: 420, y: 0, width: 1080, height: 1080))
        let r = CropVideo.cropRect(in: CGSize(width: 1080, height: 1920), aspect: 16.0 / 9)
        #expect(r.width == 1080 && r.height == 606 && r.minY == 657)
    }

    /// A PDF whose pages have the given widths (square pages).
    func pdf(_ name: String, _ sides: [CGFloat]) throws -> FileItem {
        let url = folder.url.appending(path: name)
        let context = try #require(CGContext(url as CFURL, mediaBox: nil, nil))
        for side in sides {
            var box = CGRect(x: 0, y: 0, width: side, height: side)
            context.beginPage(mediaBox: &box)
            context.endPage()
        }
        context.closePDF()
        return FileTypeResolver.resolve(url)
    }

    func widths(_ url: URL) throws -> [CGFloat] {
        let doc = try #require(CGPDFDocument(url as CFURL))
        return (1...doc.numberOfPages).compactMap { doc.page(at: $0)?.getBoxRect(.mediaBox).width }
    }

    @Test func mergeKeepsDragOrder() async throws {
        let out = try await MergePDFs().perform(items: [try pdf("a.pdf", [100]), try pdf("b.pdf", [200, 300])], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == ["a merged.pdf"])
        #expect(try widths(out[0]) == [100, 200, 300])
    }

    @Test func splitWritesOnePDFPerPage() async throws {
        let out = try await SplitPDF().perform(items: [try pdf("doc.pdf", [100, 200, 300])], progress: Progress()).files
        #expect(out.map(\.lastPathComponent) == ["doc pages"])
        let files = try FileManager.default.contentsOfDirectory(atPath: out[0].path).sorted()
        #expect(files == ["doc 01.pdf", "doc 02.pdf", "doc 03.pdf"])
        #expect(try widths(out[0].appending(path: "doc 02.pdf")) == [200])
    }

    @Test func splittingOnePageIsAClearError() async throws {
        let one = try pdf("one.pdf", [100])
        await #expect(throws: PDFFailure.self) { try await SplitPDF().perform(items: [one], progress: Progress()) }
        #expect(try folder.names() == ["one.pdf"])
    }
}
