import CoreGraphics
import Foundation
import Testing
@testable import Citra

/// Point at `degrees` clockwise from 12 o'clock, `r` from the center, y-up.
private func polar(_ degrees: Double, _ r: Double) -> CGPoint {
    let a = degrees * .pi / 180
    return CGPoint(x: r * sin(a), y: r * cos(a))
}

struct RadialLayoutTests {
    func layout(_ n: Int) -> RadialLayout {
        RadialLayout(count: n, innerRadius: 50, outerRadius: 120, gap: 6)
    }

    @Test func centerAndOutsideHitNothing() {
        let l = layout(6)
        #expect(l.hitTest(.zero) == nil)
        #expect(l.hitTest(polar(0, 49)) == nil)
        #expect(l.hitTest(polar(0, 121)) == nil)
        #expect(l.hitTest(polar(0, 50)) == 0)
        #expect(l.hitTest(polar(0, 120)) == 0)
    }

    @Test func emptyLayoutHitsNothing() {
        #expect(layout(0).hitTest(polar(0, 80)) == nil)
    }

    @Test(arguments: [0.0, 90, 179, 181, 270, 359])
    func singleSectorCoversWholeRing(_ deg: Double) {
        #expect(layout(1).hitTest(polar(deg, 80)) == 0)
    }

    @Test(arguments: [(0.0, 0), (89, 0), (91, 1), (180, 1), (269, 1), (271, 0)])
    func twoSectorsSplitTopAndBottom(_ c: (Double, Int)) {
        #expect(layout(2).hitTest(polar(c.0, 80)) == c.1)
    }

    @Test(arguments: [(0.0, 0), (29, 0), (31, 1), (60, 1), (120, 2), (180, 3), (240, 4), (300, 5), (331, 0), (359, 0)])
    func sixSectorsClockwiseFromTop(_ c: (Double, Int)) {
        #expect(layout(6).hitTest(polar(c.0, 80)) == c.1)
    }

    @Test(arguments: [(19.9, 0), (20.1, 1), (40, 1), (340.1, 0), (339.9, 8)])
    func nineSectors(_ c: (Double, Int)) {
        #expect(layout(9).hitTest(polar(c.0, 80)) == c.1)
    }

    /// Gaps are visual only: a point inside the gap belongs to the sector on its side,
    /// so the highlight never flickers to "nothing" while crossing a seam.
    @Test func gapIsNotADeadZone() {
        let l = layout(6)
        #expect(l.hitTest(polar(30, 80)) != nil)
        #expect(l.hitTest(polar(29.5, 80)) == 0)
        #expect(l.hitTest(polar(30.5, 80)) == 1)
    }

    @Test func centerAngles() {
        let l = layout(4)
        #expect(abs(l.centerAngle(of: 0) - 0) < 1e-9)
        #expect(abs(l.centerAngle(of: 1) - .pi / 2) < 1e-9)
        #expect(abs(l.centerAngle(of: 3) - 3 * .pi / 2) < 1e-9)
    }

    @Test func labelSitsOnMidRadius() {
        let p = layout(4).labelPoint(of: 1)
        #expect(abs(p.x - 85) < 1e-9)
        #expect(abs(p.y) < 1e-9)
    }

    @Test func sectorPathLeavesGapsAndCenterEmpty() {
        let l = layout(6)
        let p0 = l.sectorPath(0), p1 = l.sectorPath(1)
        #expect(p0.contains(polar(0, 85)))
        #expect(p1.contains(polar(60, 85)))
        #expect(!p0.contains(polar(30, 85)))
        #expect(!p1.contains(polar(30, 85)))
        #expect(!p0.contains(.zero))
        #expect(!p0.contains(polar(0, 130)))
    }

    @Test func singleSectorPathHasSeamAtBottom() {
        let p = layout(1).sectorPath(0)
        #expect(p.contains(polar(0, 85)))
        #expect(p.contains(polar(90, 85)))
        #expect(!p.contains(polar(180, 85)))
    }
}
