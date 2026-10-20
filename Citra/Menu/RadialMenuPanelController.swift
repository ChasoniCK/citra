import AppKit
import SwiftUI

/// One borderless, non-activating panel for the whole app.
///
/// Visibility is tracked in `isShown`, not `NSWindow.isVisible`: during a drag AppKit reported the
/// panel visible again after `orderOut` (poc.log run 1), which made `show()` a silent no-op.
/// Drag messages keep reaching the panel after it is hidden until the cursor moves, so a hidden
/// ring refuses them (`acceptsDrops`) instead of running the sector that happens to be under the cursor.
@MainActor
final class RadialMenuPanelController {
    let model = RadialMenuModel()
    var onDrop: (RadialMenuItem, [URL]) -> Void = { _, _ in }

    /// PoC experiment, toggled from the menu bar: keep the panel ordered in for the whole drag and
    /// hide it by alpha + click-through instead of ordering it out.
    static let fadeExperimentKey = "CitraFadeExperiment"
    private var fade: Bool { UserDefaults.standard.bool(forKey: Self.fadeExperimentKey) }

    private let panel = RingPanel()
    private let dropView = DropTargetView()
    private(set) var isShown = false
    private var acceptsDrops = false
    private var shownAt = Date.distantPast
    private var mouseAtShow = CGPoint.zero
    private var dragMessageSinceShow = false
    private var loggedHiddenMessage = false
    private var lastLoggedMask: NSDragOperation?

    init() {
        let side = RadialMenuModel.panelSide
        let container = NSView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        let hosting = NSHostingView(rootView: RadialMenuView(model: model))
        for view in [hosting, dropView] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view) // dropView last: topmost, so it is the drag destination
        }
        panel.contentView = container
        dropView.owner = self
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.logWindowState("occlusion changed") }
        }
    }

    /// A file drag started. In the fade experiment the panel is ordered in now, invisible and
    /// click-through, so revealing it later changes only alpha, not the window list.
    func prepare() {
        guard fade else { return }
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.ordered(.above)
        logWindowState("prepared (fade experiment)")
    }

    /// Shows the ring at the cursor, or swaps its content in place if already shown.
    func show(_ items: [RadialMenuItem], idleCenterText: String) {
        model.items = items
        model.hovered = nil
        model.idleCenterText = idleCenterText
        acceptsDrops = true
        guard !isShown else { return }
        isShown = true

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        let wasVisible = panel.isVisible
        panel.setFrame(PanelPlacement.frame(centeredAt: mouse, size: panel.frame.size, in: visible), display: false)
        if fade {
            panel.ignoresMouseEvents = false
            panel.alphaValue = 1
        }
        panel.ordered(.above)
        shownAt = .now
        mouseAtShow = mouse
        dragMessageSinceShow = false
        loggedHiddenMessage = false
        lastLoggedMask = nil
        PocLog.write("panel shown (fade=\(fade), isVisible before=\(wasVisible)) at \(Int(mouse.x)),\(Int(mouse.y)) on \(screen?.localizedName ?? "?") @\(screen?.backingScaleFactor ?? 0)x frame=\(panel.frame)")
        probeWindowState(after: [100, 500, 1500], label: "after show")
    }

    /// The modifier was released or the drag was cancelled: hide and refuse any drop still routed here.
    func hide() {
        acceptsDrops = false
        conceal("hidden")
    }

    /// The mouse button went up. A drop on the ring may still be in flight (it often arrives a few ms
    /// after the release is polled), so keep accepting it and only take the panel off screen.
    func endSession() {
        conceal("hidden at session end")
        panel.ordered(.out)
    }

    private func conceal(_ reason: String) {
        guard isShown else { return }
        isShown = false
        model.hovered = nil
        if fade {
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
        } else {
            panel.ordered(.out)
        }
        PocLog.write("panel \(reason) (fade=\(fade))")
        probeWindowState(after: [100, 500], label: "after \(reason)")
    }

    // MARK: Drag destination callbacks

    func dragMoved(_ info: NSDraggingInfo, entered: Bool) -> NSDragOperation {
        guard acceptsDrops else {
            if !loggedHiddenMessage {
                loggedHiddenMessage = true
                PocLog.write("drag \(entered ? "entered" : "update") reached the hidden panel → refused")
            }
            return []
        }
        let index = hitTest(info)
        if model.hovered != index { model.hovered = index }

        let mask = info.draggingSourceOperationMask
        let op = index == nil ? [] : DropOperation.choose(from: mask)
        if !dragMessageSinceShow {
            dragMessageSinceShow = true
            let m = NSEvent.mouseLocation
            PocLog.write("first drag message (\(entered ? "entered" : "update")) \(ms(since: shownAt))ms after show, cursor moved \(Int(hypot(m.x - mouseAtShow.x, m.y - mouseAtShow.y)))pt since show")
        }
        if mask != lastLoggedMask {
            lastLoggedMask = mask
            PocLog.write("source mask=\(Self.describe(mask)) flags=\(DragMonitor.describe(NSEvent.modifierFlags)) → op=\(Self.describe(op))")
        }
        return op
    }

    func dragExited() {
        model.hovered = nil
        PocLog.write("draggingExited (shown=\(isShown))")
    }

    func performDrop(_ info: NSDraggingInfo) -> Bool {
        guard acceptsDrops, let index = hitTest(info) else {
            PocLog.write("drop refused (accepting=\(acceptsDrops))")
            return false
        }
        let item = model.items[index]
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        PocLog.write("performDragOperation on \(item.title): \(urls.map(\.path)) mask=\(Self.describe(info.draggingSourceOperationMask))")
        onDrop(item, urls)
        return true
    }

    private func hitTest(_ info: NSDraggingInfo) -> Int? {
        let p = dropView.convert(info.draggingLocation, from: nil)
        return model.layout.hitTest(CGPoint(x: p.x - dropView.bounds.midX, y: p.y - dropView.bounds.midY))
    }

    // MARK: Diagnostics

    private func probeWindowState(after delays: [Int], label: String) {
        Task { @MainActor [weak self] in
            var elapsed = 0
            for d in delays {
                try? await Task.sleep(for: .milliseconds(d - elapsed))
                elapsed = d
                self?.logWindowState("\(label) +\(d)ms")
            }
        }
    }

    private func logWindowState(_ label: String) {
        let m = NSEvent.mouseLocation
        PocLog.write("window \(label): shown=\(isShown) isVisible=\(panel.isVisible) occlusionVisible=\(panel.occlusionState.contains(.visible)) alpha=\(panel.alphaValue) dragMessageSinceShow=\(dragMessageSinceShow) cursorMoved=\(Int(hypot(m.x - mouseAtShow.x, m.y - mouseAtShow.y)))pt")
    }

    static func describe(_ op: NSDragOperation) -> String {
        if op == .every { return "every" }
        let names: [(NSDragOperation, String)] = [(.copy, "copy"), (.link, "link"), (.generic, "generic"),
                                                  (.private, "private"), (.move, "move"), (.delete, "delete")]
        let s = names.filter { op.contains($0.0) }.map(\.1).joined(separator: "|")
        return s.isEmpty ? "none" : s
    }
}

/// Logs any ordering request that did not come from the controller, with the caller's stack.
private final class RingPanel: NSPanel {
    private var orderingFromController = false

    init() {
        let side = RadialMenuModel.panelSide
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

    func ordered(_ place: NSWindow.OrderingMode) {
        orderingFromController = true
        defer { orderingFromController = false }
        if place == .out { orderOut(nil) } else { orderFrontRegardless() }
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        logIfForeign("order(\(place.rawValue))")
        super.order(place, relativeTo: otherWin)
    }

    override func orderFrontRegardless() {
        logIfForeign("orderFrontRegardless")
        super.orderFrontRegardless()
    }

    override func setIsVisible(_ flag: Bool) {
        logIfForeign("setIsVisible(\(flag))")
        super.setIsVisible(flag)
    }

    private func logIfForeign(_ call: String) {
        guard !orderingFromController else { return }
        let stack = Thread.callStackSymbols.dropFirst(2).prefix(10)
            .map { $0.split(separator: " ", omittingEmptySubsequences: true).dropFirst(3).joined(separator: " ") }
        PocLog.write("UNEXPECTED \(call) from: \(stack.joined(separator: " ← "))")
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
