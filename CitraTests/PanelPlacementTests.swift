import CoreGraphics
import Testing
@testable import Citra

struct PanelPlacementTests {
    let visible = CGRect(x: 0, y: 25, width: 1000, height: 700)
    let size = CGSize(width: 300, height: 300)

    @Test func centersOnCursorWhenItFits() {
        let f = PanelPlacement.frame(centeredAt: CGPoint(x: 500, y: 400), size: size, in: visible)
        #expect(f == CGRect(x: 350, y: 250, width: 300, height: 300))
    }

    @Test(arguments: [
        (CGPoint(x: 10, y: 400), CGPoint(x: 0, y: 250)),
        (CGPoint(x: 995, y: 400), CGPoint(x: 700, y: 250)),
        (CGPoint(x: 500, y: 30), CGPoint(x: 350, y: 25)),
        (CGPoint(x: 500, y: 720), CGPoint(x: 350, y: 425)),
        (CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 25)),
    ])
    func shiftsInsideVisibleFrameAtEdges(_ c: (CGPoint, CGPoint)) {
        #expect(PanelPlacement.frame(centeredAt: c.0, size: size, in: visible).origin == c.1)
    }

    @Test func worksOnSecondaryScreenWithNegativeOrigin() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 875)
        let f = PanelPlacement.frame(centeredAt: CGPoint(x: -5, y: 500), size: size, in: left)
        #expect(f.origin == CGPoint(x: -300, y: 350))
    }

    @Test func oversizePanelPinsToBottomLeft() {
        let f = PanelPlacement.frame(centeredAt: CGPoint(x: 500, y: 400), size: CGSize(width: 1200, height: 800), in: visible)
        #expect(f.origin == CGPoint(x: 0, y: 25))
    }
}
