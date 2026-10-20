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
    var outerCornerRadius: CGFloat = 0
    var innerCornerRadius: CGFloat = 0

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

    var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }

    func labelPoint(of index: Int) -> CGPoint {
        let a = centerAngle(of: index), r = Double(midRadius)
        return CGPoint(x: r * sin(a), y: r * cos(a))
    }

    /// Room for a label: the chord at mid radius, minus the seam and 8 pt padding per side.
    var labelWidth: CGFloat {
        2 * midRadius * sin(min(.pi / Double(max(count, 1)), .pi / 2)) - gap - 16
    }

    func sectorPath(_ index: Int) -> CGPath {
        guard count > 0 else { return CGMutablePath() }
        let c = centerAngle(of: index), half = step / 2
        return annularSectorPath(from: c - half, to: c + half, inner: innerRadius, outer: outerRadius,
                                 gap: gap, outerCorner: outerCornerRadius, innerCorner: innerCornerRadius)
    }
}

/// Annular sector between the boundary rays `from` → `to` (radians clockwise from 12 o'clock, y-up),
/// with straight seams `gap / 2` inside each ray and every corner filleted (exact tangency to the arcs).
/// Corner radii shrink when the sector is too narrow for them.
func annularSectorPath(from a0: Double, to a1: Double, inner: CGFloat, outer: CGFloat,
                       gap: CGFloat, outerCorner: CGFloat, innerCorner: CGFloat) -> CGPath {
    let h = Double(gap) / 2, span = a1 - a0

    struct Corner { var seam: CGPoint; var arc: CGPoint; var center: CGPoint; var radius: Double; var spread: Double }

    /// Fillet at boundary `b` against the arc of radius `arcR`; `side` +1 = sector lies clockwise of `b`.
    func corner(_ b: Double, side: Double, arcR: Double, isOuter: Bool, radius rho: Double) -> Corner? {
        let u = (x: sin(b), y: cos(b)), n = (x: side * cos(b), y: -side * sin(b))
        let d = isOuter ? arcR - rho : arcR + rho, k = h + rho
        guard d > k else { return nil }
        let s = (d * d - k * k).squareRoot()
        func point(_ a: Double, _ c: Double) -> CGPoint { CGPoint(x: a * u.x + c * n.x, y: a * u.y + c * n.y) }
        let q = point(s, k)
        return Corner(seam: point(s, h), arc: CGPoint(x: q.x * arcR / d, y: q.y * arcR / d),
                      center: q, radius: rho, spread: atan2(k, s))
    }

    /// Largest radius ≤ `wanted` whose two corners leave a non-negative arc between them.
    func fit(arcR: Double, isOuter: Bool, wanted: Double) -> (Corner, Corner)? {
        var rho = wanted
        while true {
            if let s = corner(a0, side: 1, arcR: arcR, isOuter: isOuter, radius: rho),
               let e = corner(a1, side: -1, arcR: arcR, isOuter: isOuter, radius: rho),
               span - 2 * s.spread >= 0 {
                return (s, e)
            }
            if rho <= 0 { return nil }
            rho = max(0, rho - 0.25)
        }
    }

    let path = CGMutablePath()
    guard let (os, oe) = fit(arcR: Double(outer), isOuter: true, wanted: Double(outerCorner)),
          let (is_, ie) = fit(arcR: Double(inner), isOuter: false, wanted: Double(innerCorner))
    else { return path }

    func angle(_ p: CGPoint, around c: CGPoint = .zero) -> CGFloat { atan2(p.y - c.y, p.x - c.x) }
    func fillet(_ c: Corner, from p: CGPoint, to q: CGPoint) {
        guard c.radius > 0 else { return }
        path.addArc(center: c.center, radius: c.radius, startAngle: angle(p, around: c.center),
                    endAngle: angle(q, around: c.center), clockwise: true)
    }

    // Clockwise loop: out along the start seam, clockwise over the outer arc, in along the end seam,
    // back counter-clockwise over the inner arc. Every corner is convex, so every fillet turns right.
    path.move(to: is_.seam)
    path.addLine(to: os.seam)
    fillet(os, from: os.seam, to: os.arc)
    path.addArc(center: .zero, radius: outer, startAngle: angle(os.arc), endAngle: angle(oe.arc), clockwise: true)
    fillet(oe, from: oe.arc, to: oe.seam)
    path.addLine(to: ie.seam)
    fillet(ie, from: ie.seam, to: ie.arc)
    path.addArc(center: .zero, radius: inner, startAngle: angle(ie.arc), endAngle: angle(is_.arc), clockwise: false)
    fillet(is_, from: is_.arc, to: is_.seam)
    path.closeSubpath()
    return path
}
