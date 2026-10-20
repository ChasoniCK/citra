import AppKit
import ApplicationServices
import UniformTypeIdentifiers

/// Wires drag detection to the ring. PoC content: only JPEG, Copy and Copy Path do real work;
/// the other sectors exist to exercise layout and hit-testing and are marked as placeholders.
@MainActor
final class AppCoordinator {
    private let monitor = DragMonitor()
    private let panel = RadialMenuPanelController()
    private var urls: [URL] = []

    func start() {
        PocLog.write("launch: \(ProcessInfo.processInfo.operatingSystemVersionString), "
            + "accessibility trusted=\(AXIsProcessTrusted()), input monitoring granted=\(CGPreflightListenEventAccess()), "
            + "screens=\(NSScreen.screens.map { "\($0.localizedName) \($0.frame) @\($0.backingScaleFactor)x" })")

        monitor.onBegin = { [unowned self] in
            urls = $0
            panel.prepare()
        }
        monitor.onModeChange = { [unowned self] mode in
            guard let mode else { return panel.hide() }
            let items = Self.items(for: mode, urls: urls)
            guard !items.isEmpty else {
                PocLog.write("no \(mode) items for these files")
                return panel.hide()
            }
            panel.show(items, idleCenterText: Self.summary(of: urls))
        }
        monitor.onEnd = { [unowned self] in
            panel.endSession()
            urls = []
        }
        panel.onDrop = { Self.perform($0, $1) }
        monitor.start()
    }

    static func items(for mode: MenuMode, urls: [URL]) -> [RadialMenuItem] {
        switch mode {
        case .conversion:
            let allPNG = urls.allSatisfy { (try? $0.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .png) == true }
            guard allPNG else { return [] }
            return [RadialMenuItem(id: "jpeg", title: "JPEG")]
                + ["HEIC", "TIFF", "PDF"].map { RadialMenuItem(id: $0, title: $0, isPlaceholder: true) }
        case .tools:
            return [("Redact", "eye.slash"), ("Compress", "arrow.down.right.and.arrow.up.left"), ("Metadata", "tag"),
                    ("Mute", "speaker.slash"), ("Trim", "scissors"), ("Crop", "crop"), ("Speed", "gauge.with.dots.needle.67percent"),
                    ("Snapshot", "camera"), ("Split", "film")]
                .map { RadialMenuItem(id: $0.0, title: $0.0, symbol: $0.1, isPlaceholder: true) }
        case .fileActions:
            return [RadialMenuItem(id: "airdrop", title: "AirDrop", symbol: "dot.radiowaves.left.and.right", isPlaceholder: true),
                    RadialMenuItem(id: "float", title: "Float", symbol: "square.stack", isPlaceholder: true),
                    RadialMenuItem(id: "copy", title: "Copy", symbol: "doc.on.doc"),
                    RadialMenuItem(id: "move", title: "Move", symbol: "folder", isPlaceholder: true),
                    RadialMenuItem(id: "copyPath", title: "Copy Path", symbol: "link"),
                    RadialMenuItem(id: "terminal", title: "Terminal", symbol: "terminal", isPlaceholder: true)]
        }
    }

    static func summary(of urls: [URL]) -> String {
        guard urls.count == 1, let url = urls.first else { return "\(urls.count) items" }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? url.lastPathComponent
    }

    static func perform(_ item: RadialMenuItem, _ urls: [URL]) {
        switch item.id {
        case "jpeg":
            for url in urls {
                Task.detached(priority: .userInitiated) {
                    do {
                        let out = try ImageConversion.convert(url, to: .jpeg, fileExtension: "jpg")
                        await PocLog.write("JPEG written: \(out.path)")
                    } catch {
                        await report(error)
                    }
                }
            }
        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
            PocLog.write("copied \(urls.count) file URL(s) to the general pasteboard")
        case "copyPath":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            PocLog.write("copied \(urls.count) path(s) as text")
        default:
            PocLog.write("placeholder \(item.title) dropped: no-op in the PoC")
            NSSound.beep()
        }
    }

    static func report(_ error: Error) {
        PocLog.write("error: \(error.localizedDescription)")
        NSApp.activate()
        NSAlert(error: error).runModal()
    }
}
