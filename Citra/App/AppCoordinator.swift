import AppKit
import ApplicationServices

/// Wires drag detection to the ring and the ring to the action registry and task manager.
@MainActor
final class AppCoordinator {
    let notifier = Notifier()
    lazy var tasks = TaskManager(onFinished: { [notifier] in notifier.finished($0, result: $1) },
                                 onFailed: { [notifier] in notifier.failed($0, error: $1) })
    private let monitor = DragMonitor()
    private let panel = RadialMenuPanelController()
    private var items: [FileItem] = []
    /// The actions on the ring right now, by item id; kept after the drag ends for a drop still in flight.
    private var shown: [String: any FileAction] = [:]

    func start() {
        PocLog.write("launch: \(ProcessInfo.processInfo.operatingSystemVersionString), "
            + "accessibility trusted=\(AXIsProcessTrusted()), input monitoring granted=\(CGPreflightListenEventAccess())")
        notifier.start()

        monitor.onBegin = { [unowned self] urls in
            // No file contents before the drop (folder-access prompt); the drop path re-resolves with content.
            items = urls.map { FileTypeResolver.resolve($0, readingContent: false) }
            panel.sessionBegan()
        }
        monitor.onModeChange = { [unowned self] mode in
            guard let mode else { return panel.hide() }
            let actions = Registry.actions(for: mode, items: items)
            guard !actions.isEmpty else { return panel.hide() }
            shown = Dictionary(actions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            panel.show(actions.map { RadialMenuItem(id: $0.id, title: $0.title, symbol: $0.symbol, detail: $0.centerText(for: items)) },
                       idleCenterText: Self.summary(of: items))
        }
        monitor.onEnd = { [unowned self] in
            panel.endSession()
            items = []
        }
        panel.onDrop = { [unowned self] item, urls in
            guard let action = shown[item.id], !urls.isEmpty else { return }
            tasks.run(action, items: urls.map { FileTypeResolver.resolve($0) })
        }
        monitor.start()
    }

    /// Idle center text: the file size, "Folder", or the item count.
    static func summary(of items: [FileItem]) -> String {
        guard items.count == 1, let item = items.first else { return "\(items.count) items" }
        if item.isDirectory && !item.isPackage { return "Folder" }
        let size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? item.typeLabel
    }
}
