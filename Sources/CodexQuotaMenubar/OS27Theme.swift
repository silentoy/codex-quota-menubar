import SwiftUI

enum OS27 {
    enum Radius {
        static let outer: CGFloat = 18
        static let card: CGFloat = 14
        static let button: CGFloat = 10
        static let chip: CGFloat = 8
    }

    enum Padding {
        static let panel: CGFloat = 16
        static let card: CGFloat = 12
        static let section: CGFloat = 14
    }

    enum Stroke {
        static let inner = Color.white.opacity(0.12)
        static let outer = Color.black.opacity(0.06)
        static let hairline = Color.primary.opacity(0.06)
    }

    enum Shadow {
        static let contactColor = Color.black.opacity(0.04)
        static let ambientColor = Color.black.opacity(0.08)
    }

    enum Motion {
        static let interactive = Animation.spring(response: 0.35, dampingFraction: 0.78)
        static let expand = Animation.spring(response: 0.45, dampingFraction: 0.82)
    }
}

struct GlassCardBackground: ViewModifier {
    var radius: CGFloat = OS27.Radius.card
    var tint: Color = .clear
    var tintOpacity: Double = 0.0
    var emphasized: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.thinMaterial)
                    if tintOpacity > 0 {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(tint.opacity(tintOpacity))
                    }
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ), lineWidth: 0.5)
                        .blendMode(.plusLighter)
                        .opacity(0.6)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        emphasized
                            ? tint.opacity(0.28)
                            : OS27.Stroke.outer,
                        lineWidth: 0.5
                    )
            )
    }
}

struct HeroGlassBackground: ViewModifier {
    var radius: CGFloat = OS27.Radius.card
    var tint: Color

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(
                            colors: [tint.opacity(0.14), tint.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(LinearGradient(
                            colors: [Color.white.opacity(0.30), Color.white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ), lineWidth: 0.5)
                        .blendMode(.plusLighter)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 0.5)
            )
            .shadow(color: tint.opacity(0.18), radius: 12, x: 0, y: 4)
            .shadow(color: OS27.Shadow.contactColor, radius: 1, x: 0, y: 1)
    }
}

extension View {
    func glassCard(radius: CGFloat = OS27.Radius.card, tint: Color = .clear, tintOpacity: Double = 0, emphasized: Bool = false) -> some View {
        modifier(GlassCardBackground(radius: radius, tint: tint, tintOpacity: tintOpacity, emphasized: emphasized))
    }

    func heroGlass(radius: CGFloat = OS27.Radius.card, tint: Color) -> some View {
        modifier(HeroGlassBackground(radius: radius, tint: tint))
    }
}
