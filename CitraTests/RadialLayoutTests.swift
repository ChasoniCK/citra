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

    // MARK: Rounded corners (Stage 2 reference geometry)

    func rounded(_ n: Int) -> RadialLayout {
        RadialLayout(count: n, innerRadius: 53.5, outerRadius: 129.5, gap: 5, outerCornerRadius: 14, innerCornerRadius: 8)
    }

    /// Point `along` the end-boundary ray of sector 0 (n = 6, boundary at 30°), `off` pt into the sector.
    func nearEndSeam(along: Double, off: Double) -> CGPoint {
        let b = 30.0 * .pi / 180
        return CGPoint(x: along * sin(b) - off * cos(b), y: along * cos(b) + off * sin(b))
    }

    @Test func roundingCutsTheSharpOuterCorner() {
        let sharp = RadialLayout(count: 6, innerRadius: 53.5, outerRadius: 129.5, gap: 5)
        let p = nearEndSeam(along: 127, off: 3.5)
        #expect(sharp.sectorPath(0).contains(p))
        #expect(!rounded(6).sectorPath(0).contains(p))
    }

    @Test func roundingCutsTheSharpInnerCorner() {
        let sharp = RadialLayout(count: 6, innerRadius: 53.5, outerRadius: 129.5, gap: 5)
        let p = nearEndSeam(along: 55, off: 3.5)
        #expect(sharp.sectorPath(0).contains(p))
        #expect(!rounded(6).sectorPath(0).contains(p))
    }

    @Test func roundedSectorKeepsItsBodyAndStaysInsideTheRing() {
        let l = rounded(6)
        for i in 0..<6 {
            let path = l.sectorPath(i)
            #expect(path.contains(polar(Double(i) * 60, 91.5)))
            #expect(path.contains(polar(Double(i) * 60, 127)))
            let box = path.boundingBoxOfPath
            #expect(max(abs(box.minX), abs(box.maxX), abs(box.minY), abs(box.maxY)) <= 129.5 + 0.01)
        }
    }

    @Test func roundedSingleSectorKeepsBottomSeam() {
        let p = rounded(1).sectorPath(0)
        #expect(p.contains(polar(0, 91.5)))
        #expect(p.contains(polar(90, 91.5)))
        #expect(p.contains(polar(270, 91.5)))
        #expect(!p.contains(polar(180, 91.5)))
    }

    @Test func roundedTwoSectorsSplitAtHorizontalSeams() {
        let l = rounded(2)
        #expect(l.sectorPath(0).contains(polar(0, 91.5)))
        #expect(l.sectorPath(1).contains(polar(180, 91.5)))
        #expect(!l.sectorPath(0).contains(polar(90, 91.5)))
        #expect(!l.sectorPath(1).contains(polar(270, 91.5)))
    }

    /// With 10 sectors the inner arc is short; corners must shrink instead of inverting the arc.
    @Test func crowdedRingClampsCornersWithoutBreakingPaths() {
        let l = RadialLayout(count: 10, innerRadius: 53.5, outerRadius: 129.5, gap: 5,
                             outerCornerRadius: 40, innerCornerRadius: 30)
        for i in 0..<10 {
            let path = l.sectorPath(i)
            let box = path.boundingBoxOfPath
            #expect(!box.isNull && box.width.isFinite && box.height.isFinite)
            #expect(path.contains(polar(Double(i) * 36, 91.5)))
            #expect(!path.contains(polar(Double(i) * 36 + 18, 91.5)))
        }
    }

    @Test func labelWidthIsTheChordAtMidRadiusMinusPadding() {
        #expect(abs(rounded(6).labelWidth - (2 * 91.5 * sin(Double.pi / 6) - 5 - 16)) < 1e-9)
        #expect(abs(rounded(1).labelWidth - (2 * 91.5 - 5 - 16)) < 1e-9)
    }
}
