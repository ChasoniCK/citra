import SwiftUI

/// The colors around the glass, dark and light; the sectors and the pill are system glass.
struct RingPalette: Equatable {
    /// Under the sectors; never alpha 0, or a drop between two sectors would fall through.
    var backing: Color
    var hole: Color
    var holeEdge: Color
    var label: Color
    var accentTop = Accent.orange.gradient.top
    var accentBottom = Accent.orange.gradient.bottom

    static func of(_ scheme: ColorScheme, accent: Accent) -> RingPalette {
        var palette = base(scheme)
        (palette.accentTop, palette.accentBottom) = accent.gradient
        return palette
    }

    private static func base(_ scheme: ColorScheme) -> RingPalette {
        scheme == .dark
            ? RingPalette(backing: .black.opacity(0.22), hole: .black.opacity(0.14), holeEdge: .white.opacity(0.08), label: .white.opacity(0.93))
            : RingPalette(backing: .black.opacity(0.08), hole: .white.opacity(0.18), holeEdge: .black.opacity(0.06), label: .black.opacity(0.78))
    }
}

/// The ring as drawn by SwiftUI: every sector and the center pill are Liquid Glass.
struct RadialMenuView: View {
    let model: RadialMenuModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = RingPalette.of(scheme, accent: RingMetrics.accent)
        let layout = model.layout
        ZStack {
            Disc(palette: palette, scale: model.scale)

            GlassEffectContainer(spacing: 0) { // 0: neighbouring sectors never melt into each other
                ZStack { // the container alone stacks its content vertically
                    ForEach(Array(model.primaryItems.enumerated()), id: \.element.id) { index, item in
                        SectorView(shape: SectorShape(path: layout.sectorPath(index)), item: item,
                                   direction: layout.centerAngle(of: index), labelPoint: layout.labelPoint(of: index),
                                   labelWidth: layout.labelWidth, isHovered: model.hovered == .primary(index),
                                   isConfirmed: model.confirmed == .primary(index), palette: palette, scale: model.scale)
                            .equatable()
                    }
                }
            }
            .id(model.generation)
            .transition(.opacity.combined(with: .scale(scale: 0.94)))

            if model.isOverflowOpen, let arc = model.overflowLayout {
                OverflowArcView(model: model, arc: arc, palette: palette)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            CenterPill(text: model.centerText, palette: palette, scale: model.scale)
        }
        .frame(width: model.panelSide, height: model.panelSide)
        .scaleEffect(model.phase.scale)
        .opacity(model.phase.opacity)
        .animation(RingMotion.scaled(.spring(duration: 0.2, bounce: 0.15)), value: model.isOverflowOpen)
    }
}

/// What lies under the glass: a near-invisible annulus and the tinted hole.
private struct Disc: View {
    let palette: RingPalette
    let scale: CGFloat // an input so SwiftUI redraws on a size change

    var body: some View {
        ZStack {
            Annulus(inner: RingMetrics.hole, outer: RingMetrics.disc)
                .fill(palette.backing, style: FillStyle(eoFill: true))
            // Tinted, not empty: a fully transparent hole would let drops fall through to the window below.
            Circle()
                .fill(palette.hole)
                .overlay(Circle().strokeBorder(palette.holeEdge, lineWidth: 1))
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
    let scale: CGFloat

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.item == b.item && a.isHovered == b.isHovered && a.isConfirmed == b.isConfirmed
            && a.direction == b.direction && a.labelWidth == b.labelWidth && a.shape.path == b.shape.path
            && a.palette == b.palette && a.scale == b.scale
    }

    var body: some View {
        let lit = isHovered || isConfirmed
        let push: CGFloat = isHovered ? 4 * scale : 0
        SectorLabel(item: item, width: labelWidth, color: lit ? .white : palette.label, scale: scale)
            .offset(x: labelPoint.x, y: -labelPoint.y)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Our own accent fill: a glass tint renders gray in an app that is never active.
            .background(shape.fill(LinearGradient(colors: [palette.accentTop, palette.accentBottom], startPoint: .top, endPoint: .bottom))
                .opacity(lit ? 1 : 0))
            .brightness(isConfirmed ? 0.12 : 0)
            .glassEffect(.regular, in: shape)
            .offset(x: push * sin(direction), y: -push * cos(direction))
            .animation(RingMotion.scaled(.spring(duration: 0.18, bounce: 0.2)), value: isHovered)
    }
}

/// Uppercase, tracked label; symbol above when the item has one (tools, file actions), larger text when not (formats).
private struct SectorLabel: View {
    let item: RadialMenuItem
    let width: CGFloat
    let color: Color
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 4 * scale) {
            if let symbol = item.symbol {
                Image(systemName: symbol).font(.system(size: 17 * scale, weight: .medium))
            }
            Text(item.title.uppercased())
                .font(.system(size: (item.symbol == nil ? 15 : 10) * scale, weight: .bold))
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
            SectorShape(path: band).fill(palette.backing)
            GlassEffectContainer(spacing: 0) {
                ZStack {
                    ForEach(Array(model.overflowItems.enumerated()), id: \.element.id) { index, item in
                        SectorView(shape: SectorShape(path: arc.sectorPath(index)), item: item,
                                   direction: arc.centerAngle(of: index), labelPoint: arc.labelPoint(of: index),
                                   labelWidth: arc.labelWidth, isHovered: model.hovered == .overflow(index),
                                   isConfirmed: model.confirmed == .overflow(index), palette: palette, scale: model.scale)
                            .equatable()
                    }
                }
            }
        }
    }
}

private struct CenterPill: View {
    let text: String
    let palette: RingPalette
    let scale: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 13 * scale, weight: .semibold))
            .foregroundStyle(palette.label)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 14 * scale)
            .frame(minWidth: 84 * scale, maxWidth: 100 * scale, minHeight: 39 * scale, maxHeight: 39 * scale)
            .glassEffect(.regular, in: Capsule())
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
