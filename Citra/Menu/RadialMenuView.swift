import SwiftUI

/// Colors measured from the references (dark) and a matching light variant.
struct RingPalette: Equatable {
    var disc: Color
    var discEdge: Color
    var hole: Color
    var sectorTop: Color
    var sectorBottom: Color
    var sectorEdgeTop: Color
    var sectorEdgeBottom: Color
    var innerShadow: Color
    var label: Color
    var pillTop: Color
    var pillBottom: Color
    var pillEdge: Color
    var pillText: Color
    var accentTop = Accent.orange.gradient.top
    var accentBottom = Accent.orange.gradient.bottom

    static func of(_ scheme: ColorScheme, accent: Accent) -> RingPalette {
        var palette = base(scheme)
        (palette.accentTop, palette.accentBottom) = accent.gradient
        return palette
    }

    private static func base(_ scheme: ColorScheme) -> RingPalette {
        scheme == .dark
            ? RingPalette(disc: Color(white: 0.09, opacity: 0.62), discEdge: .white.opacity(0.14), hole: .black.opacity(0.14),
                          sectorTop: .white.opacity(0.13), sectorBottom: .white.opacity(0.075),
                          sectorEdgeTop: .white.opacity(0.22), sectorEdgeBottom: .white.opacity(0.04),
                          innerShadow: .black.opacity(0.35), label: .white.opacity(0.93),
                          pillTop: .white.opacity(0.2), pillBottom: .white.opacity(0.11), pillEdge: .white.opacity(0.24),
                          pillText: .white)
            : RingPalette(disc: Color(white: 0.97, opacity: 0.55), discEdge: .black.opacity(0.1), hole: .white.opacity(0.18),
                          sectorTop: .white.opacity(0.85), sectorBottom: .white.opacity(0.6),
                          sectorEdgeTop: .white, sectorEdgeBottom: .black.opacity(0.08),
                          innerShadow: .black.opacity(0.12), label: .black.opacity(0.78),
                          pillTop: .white.opacity(0.95), pillBottom: .white.opacity(0.75), pillEdge: .black.opacity(0.08),
                          pillText: .black.opacity(0.8))
    }
}

/// The ring as drawn by SwiftUI. The behind-window blur under the disc is `RingBackdrop` (AppKit),
/// because a SwiftUI material goes flat in an app that is never active.
struct RadialMenuView: View {
    let model: RadialMenuModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = RingPalette.of(scheme, accent: RingMetrics.accent)
        let layout = model.layout
        ZStack {
            Disc(palette: palette)

            ZStack {
                ForEach(Array(model.primaryItems.enumerated()), id: \.element.id) { index, item in
                    SectorView(shape: SectorShape(path: layout.sectorPath(index)), item: item,
                               direction: layout.centerAngle(of: index), labelPoint: layout.labelPoint(of: index),
                               labelWidth: layout.labelWidth, isHovered: model.hovered == .primary(index),
                               isConfirmed: model.confirmed == .primary(index), palette: palette)
                        .equatable()
                }
            }
            .id(model.generation)
            .transition(.opacity.combined(with: .scale(scale: 0.94)))

            if model.isOverflowOpen, let arc = model.overflowLayout {
                OverflowArcView(model: model, arc: arc, palette: palette)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            CenterPill(text: model.centerText, palette: palette)
        }
        .frame(width: model.panelSide, height: model.panelSide)
        .scaleEffect(model.phase.scale)
        .opacity(model.phase.opacity)
        .animation(RingMotion.scaled(.spring(duration: 0.2, bounce: 0.15)), value: model.isOverflowOpen)
    }
}

/// The dark annulus from the hole edge to the disc edge, with a thin edge highlight and a soft shadow.
private struct Disc: View {
    let palette: RingPalette

    var body: some View {
        ZStack {
            Annulus(inner: RingMetrics.hole, outer: RingMetrics.disc)
                .fill(palette.disc, style: FillStyle(eoFill: true))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            Circle()
                .strokeBorder(palette.discEdge, lineWidth: 1)
                .frame(width: RingMetrics.disc * 2, height: RingMetrics.disc * 2)
            // Tinted, not empty: a fully transparent hole would let drops fall through to the window below.
            Circle()
                .fill(palette.hole)
                .overlay(Circle().strokeBorder(palette.discEdge.opacity(0.6), lineWidth: 1))
                .frame(width: RingMetrics.hole * 2, height: RingMetrics.hole * 2)
        }
    }
}

/// One sector. Equatable so a hover change re-renders only the two sectors whose state changed.
struct SectorView: View, Equatable {
    let shape: SectorShape
    let item: RadialMenuItem
    let direction: Double
    let labelPoint: CGPoint
    let labelWidth: CGFloat
    let isHovered: Bool
    let isConfirmed: Bool
    let palette: RingPalette

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.item == b.item && a.isHovered == b.isHovered && a.isConfirmed == b.isConfirmed
            && a.direction == b.direction && a.labelWidth == b.labelWidth && a.shape.path == b.shape.path
            && a.palette == b.palette
    }

    var body: some View {
        let lit = isHovered || isConfirmed
        let push: CGFloat = isHovered ? 4 * RingMetrics.scale : 0
        ZStack {
            shape
                .fill(LinearGradient(colors: [palette.sectorTop, palette.sectorBottom], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: palette.innerShadow, radius: 2, y: 1)))
            shape
                .fill(LinearGradient(colors: [palette.accentTop, palette.accentBottom], startPoint: .top, endPoint: .bottom))
                .opacity(lit ? 1 : 0)
            shape
                .stroke(LinearGradient(colors: [palette.sectorEdgeTop, palette.sectorEdgeBottom], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                .opacity(lit ? 0.6 : 1)
            SectorLabel(item: item, width: labelWidth, color: lit ? .white : palette.label)
                .offset(x: labelPoint.x, y: -labelPoint.y)
        }
        .brightness(isConfirmed ? 0.12 : 0)
        .offset(x: push * sin(direction), y: -push * cos(direction))
        .animation(RingMotion.scaled(.spring(duration: 0.18, bounce: 0.2)), value: isHovered)
    }
}

/// Uppercase, tracked label; symbol above when the item has one (tools, file actions), larger text when not (formats).
private struct SectorLabel: View {
    let item: RadialMenuItem
    let width: CGFloat
    let color: Color

    var body: some View {
        VStack(spacing: 4 * RingMetrics.scale) {
            if let symbol = item.symbol {
                Image(systemName: symbol).font(.system(size: 17 * RingMetrics.scale, weight: .medium))
            }
            Text(item.title.uppercased())
                .font(.system(size: (item.symbol == nil ? 15 : 10) * RingMetrics.scale, weight: .bold))
                .tracking(item.symbol == nil ? 0.3 : 0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(color)
        .frame(width: max(width, 20))
    }
}

private struct OverflowArcView: View {
    let model: RadialMenuModel
    let arc: OverflowLayout
    let palette: RingPalette

    var body: some View {
        let band = annularSectorPath(from: arc.centerAngle(of: 0) - arc.itemAngle / 2 - 0.05,
                                     to: arc.centerAngle(of: arc.count - 1) + arc.itemAngle / 2 + 0.05,
                                     inner: arc.innerRadius - 5, outer: arc.outerRadius + 5, gap: 0,
                                     outerCorner: 18, innerCorner: 12)
        ZStack {
            // No behind-window blur out here (overflow is rare); a denser tint keeps it legible.
            SectorShape(path: band)
                .fill(palette.disc.opacity(1.35))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            SectorShape(path: band).stroke(palette.discEdge, lineWidth: 1)
            ForEach(Array(model.overflowItems.enumerated()), id: \.element.id) { index, item in
                SectorView(shape: SectorShape(path: arc.sectorPath(index)), item: item,
                           direction: arc.centerAngle(of: index), labelPoint: arc.labelPoint(of: index),
                           labelWidth: arc.labelWidth, isHovered: model.hovered == .overflow(index),
                           isConfirmed: model.confirmed == .overflow(index), palette: palette)
                    .equatable()
            }
        }
    }
}

private struct CenterPill: View {
    let text: String
    let palette: RingPalette

    var body: some View {
        Text(text)
            .font(.system(size: 13 * RingMetrics.scale, weight: .semibold))
            .foregroundStyle(palette.pillText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 14 * RingMetrics.scale)
            .frame(minWidth: 84 * RingMetrics.scale, maxWidth: 100 * RingMetrics.scale,
                   minHeight: 39 * RingMetrics.scale, maxHeight: 39 * RingMetrics.scale)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [palette.pillTop, palette.pillBottom], startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: palette.innerShadow, radius: 2, y: 1)))
                    .overlay(Capsule().strokeBorder(palette.pillEdge, lineWidth: 1))
            }
            .fixedSize()
            .contentTransition(.opacity)
            .animation(RingMotion.scaled(.easeOut(duration: 0.12)), value: text)
    }
}

/// Draws a ring-geometry path (y-up, centered) inside a SwiftUI rect (y-down).
struct SectorShape: Shape {
    let path: Path

    init(path: CGPath) { self.path = Path(path) }

    func path(in rect: CGRect) -> Path {
        path.applying(CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: 1, y: -1))
    }
}

private struct Annulus: Shape {
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
        p.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
        return p
    }
}

extension Accent {
    /// Top → bottom of the hovered sector; orange is the references' `#FA7349` → `#D44F02`.
    var gradient: (top: Color, bottom: Color) {
        func rgb(_ hex: UInt32) -> Color {
            Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        return switch self {
        case .orange: (rgb(0xFA7349), rgb(0xD44F02))
        case .blue: (rgb(0x4D9BFF), rgb(0x1A64DB))
        case .purple: (rgb(0xB17DFF), rgb(0x7744DB))
        case .pink: (rgb(0xFF6EA8), rgb(0xD9306D))
        case .green: (rgb(0x52D67F), rgb(0x1F9E4C))
        case .graphite: (rgb(0x9A9AA0), rgb(0x5C5C62))
        }
    }
}
