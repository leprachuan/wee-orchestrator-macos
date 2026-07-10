import SwiftUI

enum WeeTheme {
    // A restrained, high-contrast desktop palette. Surfaces are deliberately
    // opaque so text remains readable regardless of what sits behind a panel.
    static let background = Color(red: 0.025, green: 0.020, blue: 0.040)
    static let sidebar = Color(red: 0.055, green: 0.035, blue: 0.095)
    static let surface = Color(red: 0.075, green: 0.052, blue: 0.125)
    static let surfaceRaised = Color(red: 0.105, green: 0.075, blue: 0.170)
    static let surfaceHover = Color(red: 0.145, green: 0.105, blue: 0.225)

    static let emerald = Color(red: 0.243, green: 0.812, blue: 0.557)
    static let accent = emerald
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.32)
    static let danger = Color(red: 1.0, green: 0.39, blue: 0.43)
    static let textPrimary = Color(red: 0.95, green: 0.98, blue: 0.96)
    static let textSecondary = Color(red: 0.74, green: 0.80, blue: 0.76)
    static let textMuted = Color(red: 0.54, green: 0.61, blue: 0.57)
    static let glassFill = surface
    static let glassStroke = Color.white.opacity(0.10)
    static let divider = Color.white.opacity(0.09)
    static let sunken = Color.black.opacity(0.24)
}

struct WeeBackground: View {
    var body: some View {
        WeeTheme.background.ignoresSafeArea()
    }
}

struct GlassPanel: ViewModifier {
    var radius: CGFloat = 10
    var fill: Color = WeeTheme.glassFill

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(WeeTheme.glassStroke, lineWidth: 1)
            )
    }
}

extension View {
    func glassPanel(radius: CGFloat = 10, fill: Color = WeeTheme.glassFill) -> some View {
        modifier(GlassPanel(radius: radius, fill: fill))
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = WeeTheme.accent
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(color.opacity(0.22), lineWidth: 1))
    }
}

struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WeeTheme.accent)
                .frame(width: 32, height: 32)
                .background(WeeTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WeeTheme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassPanel(radius: 9, fill: WeeTheme.surface)
    }
}

struct CompactIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? WeeTheme.textPrimary : WeeTheme.textSecondary)
            .frame(minWidth: 28, minHeight: 28)
            .background(configuration.isPressed ? WeeTheme.surfaceHover : WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(WeeTheme.glassStroke))
    }
}

enum RuntimeIcons {
    private static let mapping: [String: String] = [
        "claude": "RuntimeIcon-claude", "claude-sdk": "RuntimeIcon-claude",
        "copilot": "RuntimeIcon-copilot", "copilot-sdk": "RuntimeIcon-copilot",
        "gemini": "RuntimeIcon-gemini", "opencode": "RuntimeIcon-opencode",
        "codex": "RuntimeIcon-openai", "devin": "RuntimeIcon-devin",
        "cursor": "RuntimeIcon-cursor", "wee": "RuntimeIcon-wee",
    ]

    static func imageName(for runtime: String) -> String? { mapping[runtime] }
}

struct RuntimeIconView: View {
    let runtime: String
    var size: CGFloat = 10

    var body: some View {
        if let name = RuntimeIcons.imageName(for: runtime) {
            Image(name).resizable().aspectRatio(contentMode: .fit)
                .frame(width: size, height: size).opacity(0.9)
        } else {
            Image(systemName: "server.rack")
                .font(.system(size: size * 0.7)).frame(width: size, height: size).opacity(0.9)
        }
    }
}

struct WeePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(red: 0.015, green: 0.075, blue: 0.045))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(WeeTheme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

struct WeeGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(configuration.isPressed ? WeeTheme.textPrimary : WeeTheme.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? WeeTheme.surfaceHover : WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WeeTheme.glassStroke))
    }
}
