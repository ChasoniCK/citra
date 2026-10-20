import CoreGraphics
import Foundation
import Testing
@testable import Citra

/// Point at `degrees` clockwise from 12 o'clock, `r` from the center, y-up.
private func polar(_ degrees: Double, _ r: Double) -> CGPoint {
    let a = degrees * .pi / 180
    return CGPoint(x: r * sin(a), y: r * cos(a))
}

struct OverflowLayoutTests {
    let arc = OverflowLayout(anchorAngle: 0, count: 3, innerRadius: 142, outerRadius: 200, itemAngle: 28 * .pi / 180, gap: 5)

    @Test(arguments: [(-20.0, 0), (0, 1), (20, 2)])
    func itemsAreCentredOnTheAnchor(_ c: (Double, Int)) {
        #expect(arc.hitTest(polar(c.0, 171)) == c.1)
    }

    @Test func outsideTheArcOrBandHitsNothing() {
        #expect(arc.hitTest(polar(45, 171)) == nil)
        #expect(arc.hitTest(polar(0, 210)) == nil)
        #expect(arc.hitTest(polar(0, 135)) == nil)
    }

    @Test func tooManyItemsShrinkToFitTheCircle() {
        let crowded = OverflowLayout(anchorAngle: 0, count: 20, innerRadius: 142, outerRadius: 200, itemAngle: 28 * .pi / 180, gap: 5)
        #expect(crowded.itemAngle * 20 <= 340 * .pi / 180 + 1e-9)
    }
}

@MainActor
struct RadialMenuModelTests {
    func model(_ n: Int) -> RadialMenuModel {
        let m = RadialMenuModel()
        m.items = (0..<n).map { RadialMenuItem(id: "\($0)", title: "Item \($0)") }
        return m
    }

    @Test func tenOrFewerItemsAllFitTheRing() {
        let m = model(10)
        #expect(m.primaryItems.count == 10)
        #expect(m.overflowItems.isEmpty)
        #expect(m.overflowLayout == nil)
    }

    @Test func moreThanTenFoldTheRestIntoMore() {
        let m = model(12)
        #expect(m.primaryItems.count == 10)
        #expect(m.primaryItems.last == RadialMenuModel.more)
        #expect(m.overflowItems.map(\.id) == ["9", "10", "11"])
    }

    @Test func overflowArcIsHitOnlyWhileMoreIsOpen() {
        let m = model(12)
        let moreAngle = m.layout.centerAngle(of: 9) * 180 / .pi
        let middleOfArc = polar(moreAngle, 171)
        #expect(m.target(at: middleOfArc) == nil)
        m.hovered = .primary(9)
        #expect(m.target(at: middleOfArc) == .overflow(1))
    }

    /// Moving out from More crosses the rim before the arc; the arc must not close on the way.
    @Test func rimBetweenMoreAndArcKeepsTheArcOpen() {
        let m = model(12)
        let moreAngle = m.layout.centerAngle(of: 9) * 180 / .pi
        m.hovered = .primary(9)
        #expect(m.target(at: polar(moreAngle, 135)) == .primary(9))
        m.hovered = .overflow(2)
        #expect(m.target(at: polar(moreAngle, 135)) == .overflow(2))
    }

    @Test func movingBackToAnotherSectorClosesTheArc() {
        let m = model(12)
        m.hovered = .overflow(0)
        #expect(m.target(at: polar(0, 91.5)) == .primary(0))
        m.hovered = .primary(0)
        let moreAngle = m.layout.centerAngle(of: 9) * 180 / .pi
        #expect(m.target(at: polar(moreAngle, 171)) == nil)
    }

    @Test func moreIsNotAnAction() {
        let m = model(12)
        #expect(m.item(for: .primary(9)) == nil)
        #expect(m.item(for: .primary(0))?.id == "0")
        #expect(m.item(for: .overflow(0))?.id == "9")
        #expect(m.item(for: .overflow(7)) == nil)
    }

    @Test func centerShowsHoveredDetailOrIdleText() {
        let m = model(2)
        m.items[0].detail = "PNG → JPEG"
        m.idleCenterText = "1 MB"
        #expect(m.centerText == "1 MB")
        m.hovered = .primary(0)
        #expect(m.centerText == "PNG → JPEG")
        m.hovered = .primary(1)
        #expect(m.centerText == "Item 1")
    }
}
