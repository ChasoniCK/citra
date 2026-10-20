import CoreGraphics
import Foundation

/// Arc of extra sectors outside the ring, centred on the More sector. Same conventions as
/// `RadialLayout`: points relative to the ring center, y-up, angles clockwise from 12 o'clock.
struct OverflowLayout: Sendable, Equatable {
    var anchorAngle: Double
    var count: Int
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    /// Angle per item; shrinks so the whole arc never exceeds 340°.
    var itemAngle: Double
    var gap: CGFloat
    var outerCornerRadius: CGFloat
    var innerCornerRadius: CGFloat

    init(anchorAngle: Double, count: Int, innerRadius: CGFloat, outerRadius: CGFloat, itemAngle: Double,
         gap: CGFloat, outerCornerRadius: CGFloat = 0, innerCornerRadius: CGFloat = 0) {
        self.anchorAngle = anchorAngle
        self.count = count
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.itemAngle = min(itemAngle, 340 * .pi / 180 / Double(max(count, 1)))
        self.gap = gap
        self.outerCornerRadius = outerCornerRadius
        self.innerCornerRadius = innerCornerRadius
    }

    private var start: Double { anchorAngle - Double(count) * itemAngle / 2 }
    private var total: Double { Double(count) * itemAngle }

    func centerAngle(of index: Int) -> Double { start + (Double(index) + 0.5) * itemAngle }

    /// Offset of `angle` from the arc start, in [0, 2π).
    private func offset(_ angle: Double) -> Double {
        let d = (angle - start).truncatingRemainder(dividingBy: 2 * .pi)
        return d < 0 ? d + 2 * .pi : d
    }

    /// Whether `angle` lies within the arc's angular range.
    func spans(_ angle: Double) -> Bool { offset(angle) <= total }

    func hitTest(_ p: CGPoint) -> Int? {
        guard count > 0 else { return nil }
        let r = hypot(p.x, p.y)
        guard r >= innerRadius, r <= outerRadius else { return nil }
        let d = offset(atan2(Double(p.x), Double(p.y)))
        guard d <= total else { return nil }
        return min(Int(d / itemAngle), count - 1)
    }

    var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }

    func labelPoint(of index: Int) -> CGPoint {
        let a = centerAngle(of: index), r = Double(midRadius)
        return CGPoint(x: r * sin(a), y: r * cos(a))
    }

    var labelWidth: CGFloat { 2 * midRadius * sin(itemAngle / 2) - gap - 8 }

    func sectorPath(_ index: Int) -> CGPath {
        let a0 = start + Double(index) * itemAngle
        return annularSectorPath(from: a0, to: a0 + itemAngle, inner: innerRadius, outer: outerRadius,
                                 gap: gap, outerCorner: outerCornerRadius, innerCorner: innerCornerRadius)
    }
}
