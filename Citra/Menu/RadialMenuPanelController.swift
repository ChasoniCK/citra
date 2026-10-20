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
    private let backdrop = RingBackdrop()
    private(set) var isShown = false
    private var acceptsDrops = false
    /// Bumped whenever a pending fade-out must not order the panel out any more.
    private var dismissToken = 0

    init() {
        let side = RingPanel.initialSide
        let container = NSView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        backdrop.setFrameOrigin(CGPoint(x: (side - backdrop.frame.width) / 2, y: (side - backdrop.frame.height) / 2))
        backdrop.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin] // stays centered on resize
        container.addSubview(backdrop)
        let hosting = NSHostingView(rootView: RadialMenuView(model: model))
        hosting.sizingOptions = [] // the controller sizes the panel (with or without the overflow arc)
        for view in [hosting, dropView] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view) // dropView last: topmost, so it is the drag destination
        }
        panel.contentView = container
        dropView.owner = self
    }

    /// A new drag started: a previous ring still fading out must neither linger nor take this drag's drop.
    func sessionBegan() {
        acceptsDrops = false
        if !isShown { finishHiding() }
    }

    /// Shows the ring at the cursor, or switches its content in place (cross-fade) if already shown.
    func show(_ items: [RadialMenuItem], idleCenterText: String) {
        acceptsDrops = true
        model.idleCenterText = idleCenterText
        model.confirmed = nil
        if isShown {
            if model.items != items {
                withAnimation(RingMotion.scaled(.snappy(duration: 0.2))) {
                    model.items = items
                    model.hovered = nil
                    model.generation += 1
                }
            }
            // Same window; it only grows or shrinks around its center when the overflow arc comes or goes.
            let size = CGSize(width: model.panelSide, height: model.panelSide)
            if panel.frame.size != size { place(centeredAt: CGPoint(x: panel.frame.midX, y: panel.frame.midY), size: size) }
            return
        }

        isShown = true
        dismissToken += 1
        RingMetrics.capture() // Appearance settings apply from this ring on
        model.items = items
        model.hovered = nil
        place(centeredAt: NSEvent.mouseLocation, size: CGSize(width: model.panelSide, height: model.panelSide))
        backdrop.fit()
        guard RingMetrics.motion != .off else {
            model.phase = .shown
            backdrop.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        model.phase = .hidden
        backdrop.alphaValue = 0
        panel.orderFrontRegardless()
        // Next run-loop pass, so the first frame on screen is the start state and the appear animates.
        DispatchQueue.main.async { [weak self] in
            guard let self, isShown else { return }
            withAnimation(RingMotion.scaled(.spring(duration: 0.22, bounce: 0.18))) { model.phase = .shown }
            fadeBackdrop(to: 1, duration: RingMotion.duration(0.16))
        }
    }

    /// The modifier was released or the drag was cancelled: gone at once, and any drop still routed here is refused.
    func hide() {
        acceptsDrops = false
        guard isShown else { return }
        isShown = false
        finishHiding()
    }

    /// The mouse button went up. A drop on the ring may still be in flight (it often arrives a few ms after
    /// the release is polled), so keep accepting it while the ring fades out, then take the panel off screen.
    func endSession() {
        guard isShown else { return }
        isShown = false
        dismissToken += 1
        let token = dismissToken
        guard RingMetrics.motion != .off else { return finishHiding() }
        withAnimation(RingMotion.scaled(.easeIn(duration: 0.18))) { model.phase = .dismissed }
        fadeBackdrop(to: 0, duration: RingMotion.duration(0.18))
        DispatchQueue.main.asyncAfter(deadline: .now() + RingMotion.duration(0.2)) { [weak self] in
            guard let self, dismissToken == token else { return }
            finishHiding()
        }
    }

    private func finishHiding() {
        dismissToken += 1
        panel.orderOut(nil)
        model.hovered = nil
        model.confirmed = nil
        model.phase = .hidden
    }

    private func fadeBackdrop(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            backdrop.animator().alphaValue = alpha
        }
    }

    private func place(centeredAt point: CGPoint, size: CGSize) {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        panel.setFrame(PanelPlacement.frame(centeredAt: point, size: size, in: visible), display: true)
    }

    // MARK: Drag destination callbacks

    func dragMoved(_ info: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrops else { return [] }
        let target = target(of: info)
        if model.hovered != target { model.hovered = target }
        return target.flatMap(model.item(for:)) == nil ? [] : DropOperation.choose(from: info.draggingSourceOperationMask)
    }

    func dragExited() {
        if isShown { model.hovered = nil }
    }

    func performDrop(_ info: NSDraggingInfo) -> Bool {
        guard acceptsDrops, let target = target(of: info), let item = model.item(for: target) else { return false }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        PocLog.write("drop on \(item.title): \(urls.count) item(s)")
        model.confirmed = target
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
