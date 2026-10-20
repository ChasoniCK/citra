import AppKit

/// Behind-window blur under the disc, masked to the annulus between the hole and the disc edge
/// (the hole stays clear, as in the references). `state = .active` because Citra is never the active
/// app and the default state follows window activity, which renders the material flat.
final class RingBackdrop: NSVisualEffectView {
    init() {
        let side = RingMetrics.disc * 2
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        blendingMode = .behindWindow
        state = .active
        maskImage = Self.annulus(outer: RingMetrics.disc, inner: RingMetrics.hole)
        updateMaterial()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used from nibs") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
    }

    private func updateMaterial() {
        material = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .hudWindow : .popover
    }

    private static func annulus(outer: CGFloat, inner: CGFloat) -> NSImage {
        NSImage(size: CGSize(width: outer * 2, height: outer * 2), flipped: false) { rect in
            let ring = NSBezierPath(ovalIn: rect)
            ring.append(NSBezierPath(ovalIn: rect.insetBy(dx: outer - inner, dy: outer - inner)))
            ring.windingRule = .evenOdd
            NSColor.black.setFill()
            ring.fill()
            return true
        }
    }
}
