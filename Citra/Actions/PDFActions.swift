import Foundation
import PDFKit

enum PDFFailure: LocalizedError {
    case unreadable(URL)
    case locked(URL)
    case onePage(URL)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): "“\(url.lastPathComponent)” is not a readable PDF."
        case .locked(let url): "“\(url.lastPathComponent)” is password-protected."
        case .onePage(let url): "“\(url.lastPathComponent)” has only one page, so there is nothing to split."
        case .writeFailed: "Could not write the PDF."
        }
    }
}

private func openPDF(_ url: URL) throws -> PDFDocument {
    guard let document = PDFDocument(url: url) else { throw PDFFailure.unreadable(url) }
    guard !document.isLocked else { throw PDFFailure.locked(url) }
    return document
}

/// Two or more PDFs into one, in the order they were dragged.
struct MergePDFs: FileAction {
    let id = "pdf.merge"
    let title = "Merge"
    let symbol: String? = "square.stack.3d.down.right"

    func isApplicable(to items: [FileItem]) -> Bool { items.count >= 2 && items.allSatisfy { $0.conforms(to: .pdf) } }
    func centerText(for items: [FileItem]) -> String? { "Merge \(items.count) PDFs" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        progress.totalUnitCount = Int64(items.count)
        let merged = PDFDocument()
        for item in items {
            try Task.checkCancellation()
            let document = try openPDF(item.url)
            for index in 0..<document.pageCount {
                if let page = document.page(at: index)?.copy() as? PDFPage { merged.insert(page, at: merged.pageCount) }
            }
            progress.completedUnitCount += 1
        }
        let first = items[0].url
        return ActionResult(files: [try await OutputWriter.write(into: OutputWriter.destination(for: first),
                                                                 baseName: "\(first.deletingPathExtension().lastPathComponent) merged",
                                                                 pathExtension: "pdf") { temp in
            guard merged.write(to: temp) else { throw PDFFailure.writeFailed }
        }])
    }
}

/// One PDF per page, in a folder named after the document.
struct SplitPDF: FileAction {
    let id = "pdf.split"
    let title = "Split"
    let symbol: String? = "doc.on.doc"

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy { $0.conforms(to: .pdf) } }
    func centerText(for items: [FileItem]) -> String? { "One PDF per page" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        progress.totalUnitCount = Int64(items.count)
        var outputs: [URL] = []
        for item in items {
            try Task.checkCancellation()
            let document = try openPDF(item.url)
            guard document.pageCount > 1 else { throw PDFFailure.onePage(item.url) }
            let name = item.url.deletingPathExtension().lastPathComponent
            let digits = max(2, String(document.pageCount).count)
            outputs.append(try await OutputWriter.write(into: OutputWriter.destination(for: item.url), baseName: "\(name) pages",
                                                        pathExtension: "") { temp in
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
                for index in 0..<document.pageCount {
                    try Task.checkCancellation()
                    let single = PDFDocument()
                    if let page = document.page(at: index)?.copy() as? PDFPage { single.insert(page, at: 0) }
                    let number = String(index + 1).leftPadded(to: digits)
                    guard single.write(to: temp.appending(path: "\(name) \(number).pdf")) else { throw PDFFailure.writeFailed }
                }
            })
            progress.completedUnitCount += 1
        }
        return ActionResult(files: outputs)
    }
}

private extension String {
    func leftPadded(to width: Int) -> String { String(repeating: "0", count: max(0, width - count)) + self }
}
