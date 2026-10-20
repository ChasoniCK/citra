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
    /// Window point 90 pt above the ring center: inside sector 0.
    var overSector0: NSPoint { NSPoint(x: RadialMenuModel.panelSide / 2, y: RadialMenuModel.panelSide / 2 + 90) }

    @Test func shownRingAcceptsDropOnSector() {
        let panel = RadialMenuPanelController(fadeExperiment: { false })
        var dropped: [String] = []
        panel.onDrop = { item, _ in dropped.append(item.id) }
        panel.show(items, idleCenterText: "")
        let drag = FakeDrag(at: overSector0, file: file)
        #expect(panel.dragMoved(drag, entered: true) == .copy)
        #expect(panel.performDrop(drag))
        #expect(dropped == ["0"])
        panel.endSession()
    }

    /// poc.log run 1: updates kept arriving after the modifier was released and the ring hidden.
    @Test func ringHiddenByModifierReleaseRefusesLateDragMessages() {
        let panel = RadialMenuPanelController(fadeExperiment: { false })
        var dropped: [String] = []
        panel.onDrop = { item, _ in dropped.append(item.id) }
        panel.show(items, idleCenterText: "")
        let drag = FakeDrag(at: overSector0, file: file)
        _ = panel.dragMoved(drag, entered: true)
        panel.hide()
        #expect(panel.dragMoved(drag, entered: false) == [])
        #expect(!panel.performDrop(drag))
        #expect(dropped.isEmpty)
        panel.endSession()
    }

    /// poc.log run 1: the release is often polled a few ms before `performDragOperation` arrives.
    @Test func dropArrivingAfterMouseUpIsStillAccepted() {
        let panel = RadialMenuPanelController(fadeExperiment: { false })
        var dropped: [String] = []
        panel.onDrop = { item, _ in dropped.append(item.id) }
        panel.show(items, idleCenterText: "")
        let drag = FakeDrag(at: overSector0, file: file)
        _ = panel.dragMoved(drag, entered: true)
        panel.endSession()
        #expect(panel.performDrop(drag))
        #expect(dropped == ["0"])
    }

    @Test func showAfterHideBringsRingBack() {
        let panel = RadialMenuPanelController(fadeExperiment: { false })
        panel.show(items, idleCenterText: "")
        panel.hide()
        panel.show(items, idleCenterText: "")
        #expect(panel.isShown)
        let drag = FakeDrag(at: overSector0, file: file)
        #expect(panel.dragMoved(drag, entered: true) == .copy)
        panel.endSession()
    }

    /// poc.log run 2: AppKit spring-loading calls `makeKeyAndOrderFront` on the window under a
    /// lingering drag, which put the hidden ring back on screen.
    @Test func springLoadingDoesNotBringHiddenRingBack() {
        let panel = RadialMenuPanelController(fadeExperiment: { false })
        panel.show(items, idleCenterText: "")
        panel.hide()
        panel.panel.makeKeyAndOrderFront(nil)
        #expect(!panel.panel.isVisible)
        panel.endSession()
    }
}
