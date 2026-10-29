import SwiftUI

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

/// Semantic system colours adapt to Light/Dark Mode and accessibility settings.
struct AppBackground: View {
    var body: some View { Color(UIColor.systemGroupedBackground).ignoresSafeArea() }
}
struct DashboardBackground: View {
    var accent: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        ZStack {
            if contrast == .increased {
                AppBackground()
            } else {
                (scheme == .dark ? Color(red: 0.035, green: 0.045, blue: 0.065) : Color(red: 0.96, green: 0.97, blue: 0.99))
                RadialGradient(colors: [accent.opacity(scheme == .dark ? 0.25 : 0.13), .clear], center: .init(x: 0.85, y: 0.25), startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Color.teal.opacity(scheme == .dark ? 0.12 : 0.08), .clear], center: .bottomLeading, startRadius: 0, endRadius: 360)
            }
        }.ignoresSafeArea()
    }
}
struct PrimaryTimerButton: ViewModifier {
    var accent: Color
    var prominent = true
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !opaque, contrast != .increased {
            if prominent {
                content.foregroundStyle(Color(UIColor.systemBackground)).buttonStyle(.glassProminent).tint(accent).buttonBorderShape(.roundedRectangle(radius: 20))
            } else {
                content.foregroundStyle(.primary).buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 20))
            }
        } else {
            content.buttonStyle(.plain).foregroundStyle(prominent ? Color(UIColor.systemBackground) : Color.primary)
                .padding(.vertical, 8).background(prominent ? accent : Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
struct ContentSurface: ViewModifier {
    var radius: CGFloat = 22
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(Color(UIColor.separator), lineWidth: 1).allowsHitTesting(false)
                }
            }
    }
}
// Glass is limited to floating controls, never placed beneath chart or form text.
struct GlassSurface: ViewModifier {
    enum Shape { case capsule, circle, rounded(CGFloat) }
    var shape: Shape = .capsule
    var tint: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !opaque, contrast != .increased {
            switch shape {
            case .circle: content.glassEffect(.regular.tint(tint ?? .clear).interactive(), in: Circle())
            case .capsule: content.glassEffect(.regular.tint(tint ?? .clear).interactive(), in: Capsule())
            case .rounded(let radius): content.glassEffect(.regular.tint(tint ?? .clear).interactive(), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        } else {
            switch shape {
            case .circle: content.background(Color(UIColor.secondarySystemGroupedBackground), in: Circle())
                    .overlay(Circle().strokeBorder(Color(UIColor.separator), lineWidth: 1).allowsHitTesting(false))
            case .capsule: content.background(Color(UIColor.secondarySystemGroupedBackground), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(UIColor.separator), lineWidth: 1).allowsHitTesting(false))
            case .rounded(let radius): content.background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color(UIColor.separator), lineWidth: 1).allowsHitTesting(false))
            }
        }
    }
}
