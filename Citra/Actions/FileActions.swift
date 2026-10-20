import AppKit

/// ⌘V in Finder pastes the files themselves: the general pasteboard gets file URL objects.
struct CopyFilesAction: FileAction {
    let id = "copy"
    let title = "Copy"
    let symbol: String? = "doc.on.doc"

    func isApplicable(to items: [FileItem]) -> Bool { true }

    func perform(items: [FileItem], progress: Progress) async throws -> [URL] {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(items.map { $0.url as NSURL })
        }
        return []
    }
}

/// Paths as plain text, one per line.
struct CopyPathAction: FileAction {
    let id = "copyPath"
    let title = "Copy Path"
    let symbol: String? = "link"

    func isApplicable(to items: [FileItem]) -> Bool { true }

    func perform(items: [FileItem], progress: Progress) async throws -> [URL] {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(items.map(\.url.path).joined(separator: "\n"), forType: .string)
        }
        return []
    }
}
