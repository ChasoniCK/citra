import CoreGraphics
import Foundation
import Observation

struct RadialMenuItem: Identifiable, Equatable {
    let id: String
    let title: String
    var symbol: String?
    /// Center text while hovered, e.g. "PNG → JPEG"; the title when nil.
    var detail: String?
    /// PoC only: shown to exercise the layout, does nothing on drop.
    var isPlaceholder = false
}

enum RingTarget: Equatable, Sendable {
    case primary(Int)
    case overflow(Int)
}

/// Appear: hidden → shown (scale up + fade in). Completion: shown → dismissed (slight scale up + fade out).
enum RingPhase: Sendable {
    case hidden, shown, dismissed

    var scale: CGFloat {
        switch self {
        case .hidden: 0.86
        case .shown: 1
        case .dismissed: 1.04
        }
    }

    var opacity: Double { self == .shown ? 1 : 0 }
}

/// Ring dimensions in points, measured from the reference screenshots (docs/superpowers/plans/2026-10-20-stage2-radial-ui.md).
enum RingMetrics {
    static let hole: CGFloat = 46
    static let inner: CGFloat = 53.5
    static let outer: CGFloat = 129.5
    static let disc: CGFloat = 136
    static let gap: CGFloat = 5
    static let outerCorner: CGFloat = 14
    static let innerCorner: CGFloat = 8
    static let overflowInner: CGFloat = 142
    static let overflowOuter: CGFloat = 200
    static let overflowItemAngle = 28 * Double.pi / 180
    /// Room around the disc for the hover push-out and the shadow.
    static let margin: CGFloat = 20
    static let maxPrimary = 10
}

@MainActor @Observable
final class RadialMenuModel {
    static let more = RadialMenuItem(id: "citra.more", title: "More", symbol: "ellipsis")

    /// Every action for the current mode, in priority order.
    var items: [RadialMenuItem] = []
    var hovered: RingTarget?
    var idleCenterText = ""
    var phase = RingPhase.hidden
    /// Bumped on a mode switch so the sector group cross-fades instead of morphing.
    var generation = 0
    /// The sector a file was dropped on; stays lit while the ring fades out.
    var confirmed: RingTarget?

    /// Up to 10 sectors; beyond that the first 9 plus More.
    var primaryItems: [RadialMenuItem] {
        items.count > RingMetrics.maxPrimary ? Array(items.prefix(RingMetrics.maxPrimary - 1)) + [Self.more] : items
    }

    var overflowItems: [RadialMenuItem] {
        items.count > RingMetrics.maxPrimary ? Array(items.dropFirst(RingMetrics.maxPrimary - 1)) : []
    }

    var layout: RadialLayout {
        RadialLayout(count: primaryItems.count, innerRadius: RingMetrics.inner, outerRadius: RingMetrics.outer,
                     gap: RingMetrics.gap, outerCornerRadius: RingMetrics.outerCorner, innerCornerRadius: RingMetrics.innerCorner)
    }

    var overflowLayout: OverflowLayout? {
        guard !overflowItems.isEmpty else { return nil }
        return OverflowLayout(anchorAngle: layout.centerAngle(of: primaryItems.count - 1), count: overflowItems.count,
                              innerRadius: RingMetrics.overflowInner, outerRadius: RingMetrics.overflowOuter,
                              itemAngle: RingMetrics.overflowItemAngle, gap: RingMetrics.gap,
                              outerCornerRadius: 12, innerCornerRadius: RingMetrics.innerCorner)
    }

    var panelSide: CGFloat {
        2 * ((overflowItems.isEmpty ? RingMetrics.disc : RingMetrics.overflowOuter) + RingMetrics.margin)
    }

    private var moreIndex: Int? { overflowItems.isEmpty ? nil : primaryItems.count - 1 }

    /// The overflow arc is shown and hit-testable while More or one of its items is hovered.
    var isOverflowOpen: Bool {
        guard let more = moreIndex else { return false }
        switch hovered {
        case .primary(more)?, .overflow?: return true
        default: return false
        }
    }

    /// What is under `p` (relative to the ring center, y-up).
    func target(at p: CGPoint) -> RingTarget? {
        if isOverflowOpen, let arc = overflowLayout {
            if let j = arc.hitTest(p) { return .overflow(j) }
            // Moving out from More crosses the rim before reaching the arc; keep it open on the way.
            let r = hypot(p.x, p.y), a = atan2(Double(p.x), Double(p.y))
            let towardsMore = layout.hitTest(CGPoint(x: sin(a) * Double(layout.midRadius), y: cos(a) * Double(layout.midRadius))) == moreIndex
            if r > layout.outerRadius, r < arc.innerRadius, arc.spans(a) || towardsMore { return hovered }
        }
        return layout.hitTest(p).map(RingTarget.primary)
    }

    /// The item drawn at `target`, including More.
    func displayed(_ target: RingTarget) -> RadialMenuItem? {
        switch target {
        case .primary(let i): primaryItems.indices.contains(i) ? primaryItems[i] : nil
        case .overflow(let j): overflowItems.indices.contains(j) ? overflowItems[j] : nil
        }
    }

    /// The action at `target`; nil for More, which only opens the overflow arc.
    func item(for target: RingTarget) -> RadialMenuItem? {
        displayed(target).flatMap { $0 == Self.more ? nil : $0 }
    }

    var centerText: String {
        guard let t = hovered, let item = displayed(t) else { return idleCenterText }
        return item.detail ?? item.title
    }
}
