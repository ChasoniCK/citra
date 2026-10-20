import AppKit
import SwiftUI

/// What is on the shelf. Removing an item only takes it off the shelf; the file is never touched.
@MainActor @Observable
final class ShelfModel {
    private(set) var items: [URL] = []

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) { items.append(url) }
    }

    func remove(_ url: URL) { items.removeAll { $0 == url } }
    func clear() { items.removeAll() }
}

enum ShelfPlacement {
    static let snapDistance: CGFloat = 40

    /// Keeps the shelf on screen and pins it to the left or right edge when it ends up close to one.
    static func snapped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var f = frame
        f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        if f.minX - visible.minX < snapDistance {
            f.origin.x = visible.minX
        } else if visible.maxX - f.maxX < snapDistance {
            f.origin.x = visible.maxX - f.width
        }
        return f
    }
}

/// A compact floating panel that never takes focus from the app the user is in.
@MainActor
final class ShelfController: NSObject, NSWindowDelegate {
    static let shared = ShelfController()
    let model = ShelfModel()
    private var panel: NSPanel?
    private var snapTimer: Timer?

    func add(_ urls: [URL]) {
        model.add(urls)
        let panel = panel ?? makePanel()
        fit(panel)
        if !panel.isVisible {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                panel.setFrameOrigin(CGPoint(x: visible.maxX - panel.frame.width, y: visible.midY - panel.frame.height / 2))
            }
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 260, height: 120),
                        styleMask: [.titled, .closable, .utilityWindow, .hudWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Shelf"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.delegate = self
        let hosting = NSHostingView(rootView: ShelfView(model: model) { [weak self] in self?.itemsChanged() })
        hosting.sizingOptions = []
        p.contentView = hosting
        panel = p
        return p
    }

    private func itemsChanged() {
        guard let panel else { return }
        if model.items.isEmpty { panel.close() } else { fit(panel) }
    }

    /// Height follows the rows, up to eight; the top edge stays put.
    private func fit(_ panel: NSPanel) {
        let rows = CGFloat(min(max(model.items.count, 1), 8))
        let content = CGSize(width: 260, height: rows * 42 + 12 + 30)
        let frame = panel.frameRect(forContentRect: CGRect(origin: .zero, size: content))
        panel.setFrame(CGRect(x: panel.frame.minX, y: panel.frame.maxY - frame.height, width: frame.width, height: frame.height),
                       display: true)
    }

    func windowWillClose(_ notification: Notification) { model.clear() }

    /// Snaps to a side edge once the user lets go of the panel.
    func windowDidMove(_ notification: Notification) {
        snapTimer?.invalidate()
        snapTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons & 1 == 0, let self else { return }
                self.snapTimer?.invalidate()
                guard let panel = self.panel, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
                let snapped = ShelfPlacement.snapped(panel.frame, in: visible)
                if snapped != panel.frame { panel.setFrame(snapped, display: true, animate: true) }
            }
        }
    }
}

private struct ShelfView: View {
    let model: ShelfModel
    let changed: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.items, id: \.self) { url in
                        ShelfRow(url: url) {
                            model.remove(url)
                            changed()
                        }
                    }
                }
                .padding(6)
            }
            Divider()
            HStack {
                Text(model.items.count == 1 ? "1 item" : "\(model.items.count) items")
                Spacer()
                Button("Clear") {
                    model.clear()
                    changed()
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .frame(width: 260)
    }
}

private struct ShelfRow: View {
    let url: URL
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .overlay(FileDragSource(url: url)) // drag out as a real file URL
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0.35)
                .help("Remove from the shelf. The file is not touched.")
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.white.opacity(0.08) : .clear))
        .onHover { hovering = $0 }
    }
}

/// Drag source offering the file as a copy only, so dropping it into Finder can never move the original.
private struct FileDragSource: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> SourceView { SourceView(url: url) }
    func updateNSView(_ view: SourceView, context: Context) { view.url = url }

    final class SourceView: NSView, NSDraggingSource {
        var url: URL

        init(url: URL) {
            self.url = url
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used from nibs") }

        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {} // keep the drag, not the window move

        override func mouseDragged(with event: NSEvent) {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(CGRect(x: 0, y: (bounds.height - 28) / 2, width: 28, height: 28),
                                  contents: NSWorkspace.shared.icon(forFile: url.path))
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }
    }
}
