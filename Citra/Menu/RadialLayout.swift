import CoreGraphics
import Foundation

/// Ring geometry, independent of any view. Points are relative to the ring center with
/// y pointing up (AppKit); angles are radians clockwise from 12 o'clock.
struct RadialLayout: Sendable, Equatable {
    var count: Int
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    /// Constant-width seam between neighbouring sectors, in points.
    var gap: CGFloat

    private var step: Double { 2 * .pi / Double(count) }

    func centerAngle(of index: Int) -> Double { Double(index) * step }

    /// Sector under `p`, or nil in the center hole or outside the ring. Seams belong to the
    /// sector on their side, so crossing one never clears the selection.
    func hitTest(_ p: CGPoint) -> Int? {
        guard count > 0 else { return nil }
        let r = hypot(p.x, p.y)
        guard r >= innerRadius, r <= outerRadius else { return nil }
        var a = (atan2(Double(p.x), Double(p.y)) + step / 2).truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return min(Int(a / step), count - 1)
    }

    func labelPoint(of index: Int) -> CGPoint {
        let a = centerAngle(of: index), r = Double(innerRadius + outerRadius) / 2
        return CGPoint(x: r * sin(a), y: r * cos(a))
    }

    /// Annular sector with straight, parallel-sided seams of width `gap`.
    func sectorPath(_ index: Int) -> CGPath {
        let path = CGMutablePath()
        guard count > 0 else { return path }
        let c = centerAngle(of: index), half = step / 2
        // Angular inset that keeps gap/2 of straight-line clearance from the boundary ray at radius r.
        func inset(_ r: CGFloat) -> Double { asin(min(1, Double(gap / 2 / r))) }
        // CG arcs run counter-clockwise from +x; convert from clockwise-from-top.
        func cg(_ a: Double) -> CGFloat { CGFloat(.pi / 2 - a) }
        path.addArc(center: .zero, radius: outerRadius,
                    startAngle: cg(c - half + inset(outerRadius)), endAngle: cg(c + half - inset(outerRadius)), clockwise: true)
        path.addArc(center: .zero, radius: innerRadius,
                    startAngle: cg(c + half - inset(innerRadius)), endAngle: cg(c - half + inset(innerRadius)), clockwise: false)
        path.closeSubpath()
        return path
    }
}
