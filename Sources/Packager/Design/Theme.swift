import SwiftUI
import AppKit

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hexValue: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hexValue: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hexValue >> 16) & 0xFF) / 255.0,
            green: CGFloat((hexValue >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hexValue & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

// MARK: - Theme

enum Theme {
    static let accent = Color(hex: 0x6C4CF1)
    static let accentBright = Color(hex: 0x9A7BFF)
    static let accentSoft = Color(hex: 0x6C4CF1).opacity(0.10)
    static let accentLine = Color(hex: 0x6C4CF1).opacity(0.22)

    static let gradient = LinearGradient(
        colors: [Color(hex: 0x6A4BF2), Color(hex: 0x8E6BFF), Color(hex: 0xB183FF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let canvas = Color.adaptive(light: 0xF4F2F9, dark: 0x131118)
    static let sidebar = Color.adaptive(light: 0xEFECF7, dark: 0x18151F)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x201C2A)
    static let surfaceMuted = Color.adaptive(light: 0xFAF8FD, dark: 0x262131)
    static let surfaceSunken = Color.adaptive(light: 0xF5F2FA, dark: 0x1B1723)
    static let stroke = Color.adaptive(light: 0xE8E4F0, dark: 0x322C3E)
    static let strokeSoft = Color.adaptive(light: 0xEEEBF5, dark: 0x2A2534)

    static let primaryText = Color.adaptive(light: 0x1B1626, dark: 0xF4F1FA)
    static let secondaryText = Color.adaptive(light: 0x6B6479, dark: 0xA9A1B8)
    static let tertiaryText = Color.adaptive(light: 0x9A93A8, dark: 0x7C748C)

    static let success = Color(hex: 0x2E9E6B)
    static let successSoft = Color(hex: 0x2E9E6B).opacity(0.12)
    static let warning = Color(hex: 0xD48A00)
    static let warningSoft = Color(hex: 0xD48A00).opacity(0.12)
    static let critical = Color(hex: 0xE0454A)
    static let criticalSoft = Color(hex: 0xE0454A).opacity(0.11)
    static let info = Color(hex: 0x3B82D6)
    static let infoSoft = Color(hex: 0x3B82D6).opacity(0.11)

    static let logBackground = Color.adaptive(light: 0x17131F, dark: 0x0E0C13)
    static let logText = Color(hex: 0xD8D2E6)

    static let corner: CGFloat = 16
    static let cornerSmall: CGFloat = 10

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static var shadow: Color { Color.black.opacity(0.05) }
}

// MARK: - Formatters

enum Fmt {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter
    }()

    static func size(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        if value < 1024 { return "\(value) B" }
        return bytes.string(fromByteCount: value)
    }

    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func duration(_ value: TimeInterval) -> String {
        value < 1 ? String(format: "%.0f ms", value * 1000) : String(format: "%.1f s", value)
    }
}

// MARK: - Surfaces

struct CardBackground: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: Theme.shadow, radius: 12, x: 0, y: 5)
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View {
        modifier(CardBackground(padding: padding))
    }

    func hairline(_ color: Color = Theme.strokeSoft) -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(color).frame(height: 1)
        }
    }
}

// MARK: - Small components

struct Badge: View {
    var text: String
    var tint: Color = Theme.secondaryText
    var background: Color? = nil
    var icon: String? = nil
    var mono: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.system(size: 8.5, weight: .bold))
            }
            Text(text)
                .font(mono ? Theme.mono(9.5, weight: .medium) : Theme.body(10, weight: .medium))
                .tracking(0.1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule(style: .continuous)
                .fill(background ?? tint.opacity(0.10))
        )
    }
}

struct IconTile: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 30
    var radius: CGFloat? = nil
    var filled: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius ?? size * 0.30, style: .continuous)
                .fill(filled
                      ? LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0.10)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                      : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom))
            if !filled {
                RoundedRectangle(cornerRadius: radius ?? size * 0.30, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.body(10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.tertiaryText)
    }
}

struct Hairline: View {
    var color: Color = Theme.strokeSoft

    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

// MARK: - Buttons

struct GradientButtonStyle: ButtonStyle {
    var height: CGFloat = 40
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.gradient)
                    .opacity(enabled ? 1 : 0.45)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Theme.accent.opacity(enabled ? 0.32 : 0), radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var height: CGFloat = 30
    var horizontalPadding: CGFloat = 12
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(12, weight: .medium))
            .foregroundStyle(prominent ? Theme.accent : Theme.primaryText)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height * 0.34, style: .continuous)
                    .fill(prominent ? Theme.accentSoft : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: height * 0.34, style: .continuous)
                    .strokeBorder(prominent ? Theme.accentLine : Theme.stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var tint: Color = Theme.secondaryText

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Theme.strokeSoft : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - Toggle row

struct OptionToggle: View {
    var icon: String
    var title: String
    var detail: String
    @Binding var isOn: Bool
    var enabled: Bool = true
    var recommended: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(enabled ? Theme.accentSoft : Theme.strokeSoft)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(enabled ? Theme.accent : Theme.tertiaryText)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.body(12.5, weight: .medium))
                        .foregroundStyle(enabled ? Theme.primaryText : Theme.tertiaryText)
                }
                Text(detail)
                    .font(Theme.body(10.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            MinimalSwitch(isOn: isOn, enabled: enabled)
                .allowsHitTesting(false)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard enabled else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                isOn.toggle()
            }
        }
    }
}

struct MinimalSwitch: View {
    var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    isOn
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Theme.accent, Theme.accentBright],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        : AnyShapeStyle(Theme.stroke)
                )

            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.20), radius: 1.5, x: 0, y: 0.5)
                .padding(2.4)
                .offset(x: isOn ? 7.5 : -7.5)
        }
        .frame(width: 35, height: 20)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(isOn ? Color.white.opacity(0.16) : Theme.strokeSoft, lineWidth: 0.7)
        )
        .opacity(enabled ? 1 : 0.5)
    }
}

// MARK: - Ambient background

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Theme.canvas
            GeometryReader { proxy in
                ZStack {
                    RadialGradient(
                        colors: [Theme.accent.opacity(0.18), .clear],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: proxy.size.width * 0.55
                    )
                    .offset(x: -proxy.size.width * 0.2, y: -proxy.size.height * 0.25)

                    RadialGradient(
                        colors: [Color(hex: 0xD08BFF).opacity(0.14), .clear],
                        center: .bottomTrailing,
                        startRadius: 10,
                        endRadius: proxy.size.width * 0.5
                    )
                    .offset(x: proxy.size.width * 0.25, y: proxy.size.height * 0.3)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Window / chrome helpers

struct TrafficLightSpacer: View {
    var height: CGFloat = 28

    var body: some View {
        Color.clear.frame(height: height)
    }
}
