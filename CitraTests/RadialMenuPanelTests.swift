import AppKit
import Testing
@testable import Citra

/// Stand-in for the drag session AppKit hands to a destination view.
@MainActor
private final class FakeDrag: NSObject, @MainActor NSDraggingInfo {
    var draggingLocation: NSPoint
    let draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("citra-test-\(UUID().uuidString)"))
    var draggingSourceOperationMask: NSDragOperation = .every
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    init(at point: NSPoint, file: URL) {
        draggingLocation = point
        super.init()
        draggingPasteboard.clearContents()
        draggingPasteboard.writeObjects([file as NSURL])
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}

@MainActor
struct RadialMenuPanelTests {
    let items = (0..<4).map { RadialMenuItem(id: "\($0)", title: "\($0)") }
    let file = URL(filePath: "/tmp/citra-drop.png")
    /// Window point 90 pt above the ring center: inside sector 0 (4 items, no overflow arc).
    var overSector0: NSPoint {
        let side = 2 * (RingMetrics.disc + RingMetrics.margin)
        return NSPoint(x: side / 2, y: side / 2 + 90)
    }

    @Test func shownRingAcceptsDropOnSector() {
        let panel = RadialMenuPanelController()
        var dropped: [String] = []
        panel.onDrop = { item, _ in dropped.append(item.id) }
        panel.show(items, idleCenterText: "")
        let drag = FakeDrag(at: overSector0, file: file)
        #expect(panel.dragMoved(drag) == .copy)
        #expect(panel.performDrop(drag))
        #expect(dropped == ["0"])
        panel.endSession()
    }

    /// poc.log run 1: updates kept arriving after the modifier was released and the ring hidden.
    @Test func ringHiddenByModifierReleaseRefusesLateDragMessages() {
        let panel = RadialMenuPanelController()
        var dropped: [String] = []
        panel.onDrop = { item, _ in dropped.append(item.id) }
        panel.show(items, idleCenterText: "")
        let drag = FakeDrag(at: overSector0, file: file)
        _ = panel.dragMoved(drag)
        panel.hide()
        #expect(panel.dragMoved(drag) == [])
        #expect(!panel.performDrop(drag))
        #expect(dropped.isEmpty)
        panel.endSession()
    }

    /// poc.log run 1: the release is often polled a few ms before `performDragOperation` arrives.
    @Test func dropArrivingAfterMouseUpIsStillAccepted() {
        let panel = RadialMenuPanelController()
        var dropped: [String] = []
        panel.onDrop = { item, _ in dropped.append(item.id) }
        panel.show(items, idleCenterText: "")
        let drag = FakeDrag(at: overSector0, file: file)
        _ = panel.dragMoved(drag)
        panel.endSession()
        #expect(panel.performDrop(drag))
        #expect(dropped == ["0"])
    }

    @Test func showAfterHideBringsRingBack() {
        let panel = RadialMenuPanelController()
        panel.show(items, idleCenterText: "")
        panel.hide()
        panel.show(items, idleCenterText: "")
        #expect(panel.isShown)
        let drag = FakeDrag(at: overSector0, file: file)
        #expect(panel.dragMoved(drag) == .copy)
        panel.endSession()
    }

    /// poc.log run 2: AppKit spring-loading calls `makeKeyAndOrderFront` on the window under a
    /// lingering drag, which put the hidden ring back on screen.
    @Test func springLoadingDoesNotBringHiddenRingBack() {
        let panel = RadialMenuPanelController()
        panel.show(items, idleCenterText: "")
        panel.hide()
        panel.panel.makeKeyAndOrderFront(nil)
        #expect(!panel.panel.isVisible)
        panel.endSession()
    }

    /// Window point at `degrees` clockwise from 12 o'clock and `r` from the ring center.
    func point(in panel: RadialMenuPanelController, _ degrees: Double, _ r: Double) -> NSPoint {
        let a = degrees * .pi / 180, c = panel.model.panelSide / 2
        return NSPoint(x: c + r * sin(a), y: c + r * cos(a))
    }

    @Test func dropOnMoreIsRefusedButOverflowItemIsAccepted() {
        let panel = RadialMenuPanelController()
        var dropped: [String] = []
        panel.onDrop = { item, _ in dropped.append(item.id) }
        let twelve = (0..<12).map { RadialMenuItem(id: "\($0)", title: "\($0)") }
        panel.show(twelve, idleCenterText: "")
        #expect(panel.panel.frame.width == panel.model.panelSide)

        let moreAngle = panel.model.layout.centerAngle(of: 9) * 180 / .pi
        let overMore = FakeDrag(at: point(in: panel, moreAngle, 91.5), file: file)
        #expect(panel.dragMoved(overMore) == [])
        #expect(!panel.performDrop(overMore))

        let overArc = FakeDrag(at: point(in: panel, moreAngle, 171), file: file)
        #expect(panel.dragMoved(overArc) == .copy)
        #expect(panel.performDrop(overArc))
        #expect(dropped == ["10"])
        panel.endSession()
    }
}
