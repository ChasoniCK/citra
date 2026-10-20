import AppKit
import SwiftUI

/// One borderless, non-activating panel for the whole app. It is ordered out (not just made
/// transparent) whenever the ring is hidden, so it never intercepts an ordinary drag.
@MainActor
final class RadialMenuPanelController {
    let model = RadialMenuModel()
    var onDrop: (RadialMenuItem, [URL]) -> Void = { _, _ in }
    /// The drag left the panel while the cursor is still over it: the drag was cancelled (Escape).
    var onCancelOverPanel: () -> Void = {}

    private let panel: NSPanel
    private let dropView = DropTargetView()
    private var shownAt = Date.distantPast
    private var enteredSinceShow = false
    private var lastLoggedMask: NSDragOperation?

    init() {
        let side = RadialMenuModel.panelSide
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: side, height: side),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

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

    var isVisible: Bool { panel.isVisible }

    /// Shows the ring at the cursor, or swaps its content in place if already visible.
    func show(_ items: [RadialMenuItem], idleCenterText: String) {
        model.items = items
        model.hovered = nil
        model.idleCenterText = idleCenterText
        guard !panel.isVisible else { return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        panel.setFrame(PanelPlacement.frame(centeredAt: mouse, size: panel.frame.size, in: visible), display: false)
        panel.orderFrontRegardless()
        shownAt = .now
        enteredSinceShow = false
        lastLoggedMask = nil
        PocLog.write("panel shown at \(Int(mouse.x)),\(Int(mouse.y)) on \(screen?.localizedName ?? "?") scale=\(screen?.backingScaleFactor ?? 0) visible=\(visible) frame=\(panel.frame)")
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        model.hovered = nil
        PocLog.write("panel hidden")
    }

    // MARK: Drag destination callbacks

    fileprivate func dragMoved(_ info: NSDraggingInfo, entered: Bool) -> NSDragOperation {
        let index = hitTest(info)
        if model.hovered != index { model.hovered = index }

        let mask = info.draggingSourceOperationMask
        let op = index == nil ? [] : DropOperation.choose(from: mask)
        if entered && !enteredSinceShow {
            enteredSinceShow = true
            PocLog.write("draggingEntered \(ms(since: shownAt))ms after show, mouse moved since show: \(NSEvent.mouseLocation != panelCenter)")
        }
        if mask != lastLoggedMask {
            lastLoggedMask = mask
            PocLog.write("source mask=\(Self.describe(mask)) flags=\(DragMonitor.describe(NSEvent.modifierFlags)) → op=\(Self.describe(op))")
        }
        return op
    }

    fileprivate func dragExited() {
        model.hovered = nil
        // Measured against the visible disc, not the square frame: its corners are transparent.
        let m = NSEvent.mouseLocation
        let inside = hypot(m.x - panelCenter.x, m.y - panelCenter.y) < RadialMenuModel.discRadius
        PocLog.write("draggingExited, cursor inside disc: \(inside)")
        if inside && panel.isVisible { onCancelOverPanel() }
    }

    fileprivate func performDrop(_ info: NSDraggingInfo) -> Bool {
        guard let index = hitTest(info) else { return false }
        let item = model.items[index]
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        PocLog.write("performDragOperation on \(item.title): \(urls.map(\.path)) mask=\(Self.describe(info.draggingSourceOperationMask))")
        onDrop(item, urls)
        return true
    }

    private var panelCenter: CGPoint { CGPoint(x: panel.frame.midX, y: panel.frame.midY) }

    private func hitTest(_ info: NSDraggingInfo) -> Int? {
        let p = dropView.convert(info.draggingLocation, from: nil)
        return model.layout.hitTest(CGPoint(x: p.x - dropView.bounds.midX, y: p.y - dropView.bounds.midY))
    }

    static func describe(_ op: NSDragOperation) -> String {
        if op == .every { return "every" }
        let names: [(NSDragOperation, String)] = [(.copy, "copy"), (.link, "link"), (.generic, "generic"),
                                                  (.private, "private"), (.move, "move"), (.delete, "delete")]
        let s = names.filter { op.contains($0.0) }.map(\.1).joined(separator: "|")
        return s.isEmpty ? "none" : s
    }
}

private final class DropTargetView: NSView {
    weak var owner: RadialMenuPanelController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used from nibs") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        owner?.dragMoved(sender, entered: true) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        owner?.dragMoved(sender, entered: false) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { owner?.dragExited() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { owner?.performDrop(sender) ?? false }

    override func draggingEnded(_ sender: NSDraggingInfo) { PocLog.write("draggingEnded") }
}
