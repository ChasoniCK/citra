import Foundation

/// One menu entry. Conversions, tools and file actions all conform; the ring, the center text and
/// (later) the settings read from `Registry` only, so adding an action never touches menu code.
protocol FileAction: Sendable {
    var id: String { get }
    var title: String { get }
    var symbol: String? { get }
    /// False when a required encoder or external tool is missing; the action is then not offered.
    var isAvailable: Bool { get }
    func isApplicable(to items: [FileItem]) -> Bool
    /// Center text while hovered, e.g. "PNG → JPEG"; the title when nil.
    func centerText(for items: [FileItem]) -> String?
    /// Runs off the main thread; returns the files it created (for "Show in Finder") and/or a message.
    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult
}

struct ActionResult: Sendable, Equatable {
    var files: [URL] = []
    /// Shown when there is something to say beyond the files, e.g. "OK — 12 files".
    var message: String?
}

extension FileAction {
    var symbol: String? { nil }
    var isAvailable: Bool { true }
    func centerText(for items: [FileItem]) -> String? { nil }
}

/// Every action per mode, in menu order (clockwise from 12 o'clock).
enum Registry {
    static func all(for mode: MenuMode) -> [any FileAction] {
        switch mode {
        case .conversion: ImageConverter.all + [ImageToPDF()]
        case .tools: [ResizeImage(), RotateImage(), CompressImage(), RemoveImageMetadata(), ExtractArchive(), TestArchive()]
        case .fileActions: [CopyFilesAction(), CopyPathAction()]
        }
    }

    /// What the ring offers for these items: available and applicable to every one of them.
    static func actions(for mode: MenuMode, items: [FileItem]) -> [any FileAction] {
        guard !items.isEmpty else { return [] }
        return all(for: mode).filter { $0.isAvailable && $0.isApplicable(to: items) }
    }
}
