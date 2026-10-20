import AppKit
import SwiftUI

/// One borderless, non-activating panel for the whole app, ordered out whenever the ring is hidden
/// so an ordinary drag never meets it. Lessons from the PoC runs (docs/feasibility.md):
/// - visibility is tracked in `isShown`, because `NSWindow.isVisible` went stale during drags;
/// - drag messages keep reaching a just-hidden panel until the cursor moves, so a hidden ring
///   refuses them (`acceptsDrops`) instead of running the sector that happens to be under the cursor;
/// - AppKit spring-loading orders the window under a lingering drag front; `RingPanel` ignores that.
@MainActor
final class RadialMenuPanelController {
    let model = RadialMenuModel()
    var onDrop: (RadialMenuItem, [URL]) -> Void = { _, _ in }
    let panel: NSPanel = RingPanel()

    private let dropView = DropTargetView()
    private(set) var isShown = false
    private var acceptsDrops = false

    init() {
        let side = RingPanel.initialSide
        let container = NSView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        let hosting = NSHostingView(rootView: RadialMenuView(model: model))
        for view in [hosting, dropView] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view) // dropView last: topmost, so it is the drag destination
        }
        panel.contentView = container
        dropView.owner = self
    }

    /// Shows the ring at the cursor, or swaps its content in place if already shown.
    func show(_ items: [RadialMenuItem], idleCenterText: String) {
        model.items = items
        model.hovered = nil
        model.idleCenterText = idleCenterText
        acceptsDrops = true
        let size = CGSize(width: model.panelSide, height: model.panelSide)
        if isShown {
            // Same window; only grows or shrinks around its center when the overflow arc comes or goes.
            if panel.frame.size != size {
                place(centeredAt: CGPoint(x: panel.frame.midX, y: panel.frame.midY), size: size)
            }
            return
        }
        isShown = true
        place(centeredAt: NSEvent.mouseLocation, size: size)
        panel.orderFrontRegardless()
    }

    private func place(centeredAt point: CGPoint, size: CGSize) {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        panel.setFrame(PanelPlacement.frame(centeredAt: point, size: size, in: visible), display: true)
    }

    /// The modifier was released or the drag was cancelled: hide and refuse any drop still routed here.
    func hide() {
        acceptsDrops = false
        conceal()
    }

    /// The mouse button went up. A drop on the ring may still be in flight (it often arrives a few ms
    /// after the release is polled), so keep accepting it and only take the panel off screen.
    func endSession() {
        conceal()
    }

    private func conceal() {
        guard isShown else { return }
        isShown = false
        model.hovered = nil
        panel.orderOut(nil)
    }

    // MARK: Drag destination callbacks

    func dragMoved(_ info: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrops else { return [] }
        let target = target(of: info)
        if model.hovered != target { model.hovered = target }
        return target.flatMap(model.item(for:)) == nil ? [] : DropOperation.choose(from: info.draggingSourceOperationMask)
    }

    func dragExited() {
        model.hovered = nil
    }

    func performDrop(_ info: NSDraggingInfo) -> Bool {
        guard acceptsDrops, let target = target(of: info), let item = model.item(for: target) else { return false }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        PocLog.write("drop on \(item.title): \(urls.count) item(s)")
        onDrop(item, urls)
        return true
    }

    private func target(of info: NSDraggingInfo) -> RingTarget? {
        let p = dropView.convert(info.draggingLocation, from: nil)
        return model.target(at: CGPoint(x: p.x - dropView.bounds.midX, y: p.y - dropView.bounds.midY))
    }
}

private final class RingPanel: NSPanel {
    static let initialSide = 2 * (RingMetrics.disc + RingMetrics.margin)

    init() {
        let side = Self.initialSide
        super.init(contentRect: CGRect(x: 0, y: 0, width: side, height: side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// AppKit spring-loading sends this to the window under a lingering drag
    /// (`_NSSpringLoadingTrackingProc`), which brought a hidden ring back on screen.
    /// The ring is shown only by its controller.
    override func makeKeyAndOrderFront(_ sender: Any?) {}
}

private final class DropTargetView: NSView {
    weak var owner: RadialMenuPanelController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used from nibs") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { owner?.dragMoved(sender) ?? [] }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { owner?.dragMoved(sender) ?? [] }

    override func draggingExited(_ sender: NSDraggingInfo?) { owner?.dragExited() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { owner?.performDrop(sender) ?? false }
}
