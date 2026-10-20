import SwiftUI

/// PoC rendering: plain ring, highlight under the cursor. Styling is Stage 2.
struct RadialMenuView: View {
    let model: RadialMenuModel

    var body: some View {
        let layout = model.layout
        ZStack {
            Circle()
                .fill(.black.opacity(0.78))
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                .frame(width: RingMetrics.disc * 2, height: RingMetrics.disc * 2)

            ForEach(Array(model.primaryItems.enumerated()), id: \.element.id) { index, item in
                let hovered = model.hovered == .primary(index)
                SectorShape(layout: layout, index: index)
                    .fill(hovered ? Color.orange : .white.opacity(item.isPlaceholder ? 0.06 : 0.16))
                    .scaleEffect(hovered ? 1.04 : 1)
                let p = layout.labelPoint(of: index)
                VStack(spacing: 3) {
                    if let symbol = item.symbol { Image(systemName: symbol).font(.system(size: 15)) }
                    Text(item.title).font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(item.isPlaceholder ? 0.45 : 1))
                .offset(x: p.x, y: -p.y)
            }

            Text(model.centerText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 84)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .animation(.easeOut(duration: 0.12), value: model.hovered)
        .frame(width: model.panelSide, height: model.panelSide)
    }
}

/// Draws a `RadialLayout` path (y-up, centered) inside a SwiftUI rect (y-down).
struct SectorShape: Shape {
    let layout: RadialLayout
    let index: Int

    func path(in rect: CGRect) -> Path {
        Path(layout.sectorPath(index)).applying(CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: 1, y: -1))
    }
}
