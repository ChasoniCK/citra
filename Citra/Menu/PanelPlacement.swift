import CoreGraphics

enum PanelPlacement {
    /// Centers a panel on `p`, shifted (not clipped) to stay inside `visible`.
    /// A panel larger than `visible` pins to its bottom-left corner.
    static func frame(centeredAt p: CGPoint, size: CGSize, in visible: CGRect) -> CGRect {
        let x = max(visible.minX, min(p.x - size.width / 2, visible.maxX - size.width))
        let y = max(visible.minY, min(p.y - size.height / 2, visible.maxY - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
