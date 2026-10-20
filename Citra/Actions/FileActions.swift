import AppKit

/// AirDrop through the system service; the share picker at the cursor when AirDrop is unavailable.
struct AirDropAction: FileAction {
    let id = "file.airdrop"
    let title = "AirDrop"
    let symbol: String? = "dot.radiowaves.left.and.right"

    func isApplicable(to items: [FileItem]) -> Bool { true }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        let urls = items.map(\.url)
        await MainActor.run {
            NSApp.activate()
            if let airDrop = NSSharingService(named: .sendViaAirDrop), airDrop.canPerform(withItems: urls) {
                airDrop.perform(withItems: urls)
            } else {
                SharePicker.show(urls)
            }
        }
        return ActionResult()
    }
}

/// Puts the items on the floating shelf; the files themselves are not touched.
struct FloatAction: FileAction {
    let id = "file.float"
    let title = "Float"
    let symbol: String? = "square.stack"

    func isApplicable(to items: [FileItem]) -> Bool { true }
    func centerText(for items: [FileItem]) -> String? { "Add to shelf" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        await MainActor.run { ShelfController.shared.add(items.map(\.url)) }
        return ActionResult()
    }
}

/// ⌘V in Finder pastes the files themselves: the pasteboard gets file URL objects.
struct CopyFilesAction: FileAction {
    let id = "file.copy"
    let title = "Copy"
    let symbol: String? = "doc.on.doc"
    var pasteboard: NSPasteboard.Name = .general

    func isApplicable(to items: [FileItem]) -> Bool { true }
    func centerText(for items: [FileItem]) -> String? { "Copy to paste in Finder" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        await MainActor.run {
            let board = NSPasteboard(name: pasteboard)
            board.clearContents()
            board.writeObjects(items.map { $0.url as NSURL })
        }
        return ActionResult()
    }
}

/// Paths as plain text, one per line.
struct CopyPathAction: FileAction {
    let id = "file.copyPath"
    let title = "Copy Path"
    let symbol: String? = "link"
    var pasteboard: NSPasteboard.Name = .general

    func isApplicable(to items: [FileItem]) -> Bool { true }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        await MainActor.run {
            let board = NSPasteboard(name: pasteboard)
            board.clearContents()
            board.setString(items.map(\.url.path).joined(separator: "\n"), forType: .string)
        }
        return ActionResult()
    }
}

/// Moves into a folder picked in an open panel; asks on name conflicts.
struct MoveAction: FileAction {
    let id = "file.move"
    let title = "Move"
    let symbol: String? = "folder"

    func isApplicable(to items: [FileItem]) -> Bool { true }
    func centerText(for items: [FileItem]) -> String? { "Move to…" }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        let urls = items.map(\.url)
        guard let destination = await MainActor.run(body: { MoveDialogs.chooseFolder(count: urls.count) }) else { throw CancellationError() }
        let mover = Mover(resolve: { name in await MainActor.run { MoveDialogs.resolveConflict(name) } },
                          trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) })
        let moved = try await mover.move(urls, to: destination, crossVolume: try Mover.crossesVolumes(urls, destination))
        return ActionResult(files: moved)
    }
}

/// Moving files without ever overwriting silently, and across volumes without losing data:
/// copy completely, then remove the source.
struct Mover: Sendable {
    enum Choice: Sendable { case replace, keepBoth, skip, stop }

    /// Asked for each name conflict.
    var resolve: @Sendable (String) async -> Choice
    /// Disposes of the existing item when the user chose Replace (the real app uses the Trash).
    var trash: @Sendable (URL) throws -> Void

    static func crossesVolumes(_ urls: [URL], _ directory: URL) throws -> Bool {
        let target = try directory.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        return try urls.contains { (try $0.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject) != target }
    }

    func move(_ urls: [URL], to directory: URL, crossVolume: Bool) async throws -> [URL] {
        let fm = FileManager.default
        var moved: [URL] = []
        for url in urls {
            try Task.checkCancellation()
            var target = directory.appending(path: url.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                switch await resolve(url.lastPathComponent) {
                case .stop: throw CancellationError()
                case .skip: continue
                case .keepBoth:
                    target = FileNaming.uniqueURL(directory: directory, baseName: url.deletingPathExtension().lastPathComponent,
                                                  pathExtension: url.pathExtension) { fm.fileExists(atPath: $0.path) }
                case .replace:
                    try trash(target)
                }
            }
            if crossVolume {
                // Copy under a hidden name first, so a failed copy never leaves a half item under the real name.
                let temp = directory.appending(path: ".citra-move-\(UUID().uuidString)")
                do {
                    try fm.copyItem(at: url, to: temp)
                    try fm.moveItem(at: temp, to: target)
                } catch {
                    try? fm.removeItem(at: temp) // best effort; the copy error is what matters
                    throw error
                }
                try fm.removeItem(at: url) // only after the copy is complete
            } else {
                try fm.moveItem(at: url, to: target)
            }
            moved.append(target)
        }
        return moved
    }
}

@MainActor
enum MoveDialogs {
    static func chooseFolder(count: Int) -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Move Here"
        panel.message = count == 1 ? "Move 1 item to:" : "Move \(count) items to:"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func resolveConflict(_ name: String) -> Mover.Choice {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "“\(name)” already exists in this folder."
        alert.informativeText = "Replace moves the existing item to the Trash."
        for title in ["Keep Both", "Replace", "Skip", "Stop"] { alert.addButton(withTitle: title) }
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        case .alertThirdButtonReturn: return .skip
        default: return .stop
        }
    }
}

/// Opens Terminal in the folder (or the file's folder) through Launch Services: no shell string, no
/// AppleScript, so any path is safe and no Automation permission is needed.
struct OpenInTerminal: FileAction {
    let id = "file.terminal"
    let title = "Terminal"
    let symbol: String? = "terminal"
    static let bundleID = "com.apple.Terminal"

    var isAvailable: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil }
    func isApplicable(to items: [FileItem]) -> Bool { true }
    func centerText(for items: [FileItem]) -> String? { "Open Terminal here" }

    /// A folder opens itself; a file or bundle opens its parent; duplicates collapse.
    static func directories(for items: [FileItem]) -> [URL] {
        var seen = Set<String>()
        return items.map { $0.isDirectory && !$0.isPackage ? $0.url : $0.url.deletingLastPathComponent() }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Terminal is not installed."])
        }
        _ = try await NSWorkspace.shared.open(Self.directories(for: items), withApplicationAt: app,
                                              configuration: NSWorkspace.OpenConfiguration())
        return ActionResult()
    }
}

/// The system share menu shown at the cursor from a tiny transparent window that lives until a choice is made.
@MainActor
final class SharePicker: NSObject, NSSharingServicePickerDelegate {
    private static var current: SharePicker?
    private let window: NSPanel

    private init(at point: CGPoint) {
        window = NSPanel(contentRect: CGRect(x: point.x, y: point.y, width: 1, height: 1),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .popUpMenu
    }

    static func show(_ urls: [URL]) {
        let presenter = SharePicker(at: NSEvent.mouseLocation)
        current = presenter
        presenter.window.orderFrontRegardless()
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = presenter
        if let view = presenter.window.contentView { picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY) }
    }

    nonisolated func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        MainActor.assumeIsolated {
            window.orderOut(nil)
            Self.current = nil
        }
    }
}
