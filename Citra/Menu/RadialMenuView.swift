import SwiftUI

struct RadialMenuItem: Identifiable, Equatable {
    let id: String
    let title: String
    var symbol: String?
    /// PoC only: shown to exercise the layout, does nothing on drop.
    var isPlaceholder = false
}

@MainActor @Observable
final class RadialMenuModel {
    var items: [RadialMenuItem] = []
    var hovered: Int?
    var idleCenterText = ""

    static let outerRadius: CGFloat = 130
    /// Visible backdrop; the panel corners outside it are fully transparent.
    static let discRadius: CGFloat = outerRadius + 8
    static let panelSide: CGFloat = (outerRadius + 14) * 2

    var layout: RadialLayout {
        RadialLayout(count: items.count, innerRadius: 50, outerRadius: Self.outerRadius, gap: 6)
    }

    var centerText: String { hovered.map { items[$0].title } ?? idleCenterText }
}

/// PoC rendering: plain ring, highlight under the cursor. Styling is Stage 2.
struct RadialMenuView: View {
    let model: RadialMenuModel

    var body: some View {
        let layout = model.layout
        ZStack {
            Circle()
                .fill(.black.opacity(0.78))
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                .frame(width: RadialMenuModel.discRadius * 2, height: RadialMenuModel.discRadius * 2)

            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                let hovered = model.hovered == index
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
        .frame(width: RadialMenuModel.panelSide, height: RadialMenuModel.panelSide)
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
