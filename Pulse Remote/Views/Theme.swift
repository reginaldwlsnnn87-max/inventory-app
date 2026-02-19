import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case classic
    case modern
    case vibrant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:
            return "Classic"
        case .modern:
            return "Modern"
        case .vibrant:
            return "Vibrant"
        }
    }
}

enum InventoryModule: String, CaseIterable, Identifiable {
    case counts
    case replenishment
    case shrink
    case automation
    case intelligence
    case trust
    case catalog
    case reports
    case support
    case workspace

    var id: String { rawValue }
}

struct InventoryModuleVisual {
    let tint: Color
    let softTint: Color
    let deepTint: Color
    let symbol: String
}

private struct ThemePalette {
    let accent: Color
    let accentSoft: Color
    let accentDeep: Color
    let backgroundTop: Color
    let backgroundBottom: Color
    let backgroundEdge: Color
    let cardBackground: Color
    let subtleBorder: Color
    let strongBorder: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let glow: Color

    static let classic = ThemePalette(
        accent: Color(red: 0.08, green: 0.47, blue: 0.43),
        accentSoft: Color(red: 0.61, green: 0.83, blue: 0.78),
        accentDeep: Color(red: 0.03, green: 0.24, blue: 0.27),
        backgroundTop: Color(red: 0.95, green: 0.98, blue: 0.97),
        backgroundBottom: Color(red: 0.79, green: 0.89, blue: 0.92),
        backgroundEdge: Color(red: 0.72, green: 0.84, blue: 0.88),
        cardBackground: Color(red: 0.98, green: 0.99, blue: 0.99),
        subtleBorder: Color(red: 0.06, green: 0.18, blue: 0.22).opacity(0.14),
        strongBorder: Color.white.opacity(0.55),
        textPrimary: Color(red: 0.04, green: 0.10, blue: 0.13),
        textSecondary: Color(red: 0.16, green: 0.26, blue: 0.30),
        textTertiary: Color(red: 0.28, green: 0.38, blue: 0.43),
        glow: Color(red: 0.08, green: 0.47, blue: 0.43).opacity(0.22)
    )

    static let modern = ThemePalette(
        accent: Color(red: 0.17, green: 0.33, blue: 0.82),
        accentSoft: Color(red: 0.76, green: 0.83, blue: 0.98),
        accentDeep: Color(red: 0.07, green: 0.14, blue: 0.36),
        backgroundTop: Color(red: 0.99, green: 0.95, blue: 0.90),
        backgroundBottom: Color(red: 0.88, green: 0.92, blue: 0.99),
        backgroundEdge: Color(red: 0.80, green: 0.87, blue: 0.97),
        cardBackground: Color(red: 1.00, green: 0.99, blue: 0.98),
        subtleBorder: Color(red: 0.10, green: 0.16, blue: 0.28).opacity(0.16),
        strongBorder: Color.white.opacity(0.68),
        textPrimary: Color(red: 0.09, green: 0.11, blue: 0.24),
        textSecondary: Color(red: 0.24, green: 0.29, blue: 0.44),
        textTertiary: Color(red: 0.39, green: 0.43, blue: 0.57),
        glow: Color(red: 0.30, green: 0.45, blue: 0.93).opacity(0.25)
    )

    static let vibrant = ThemePalette(
        accent: Color(red: 0.91, green: 0.31, blue: 0.42),
        accentSoft: Color(red: 1.00, green: 0.80, blue: 0.59),
        accentDeep: Color(red: 0.25, green: 0.13, blue: 0.39),
        backgroundTop: Color(red: 1.00, green: 0.95, blue: 0.84),
        backgroundBottom: Color(red: 0.91, green: 0.86, blue: 1.00),
        backgroundEdge: Color(red: 0.82, green: 0.95, blue: 0.94),
        cardBackground: Color(red: 1.00, green: 0.98, blue: 0.97),
        subtleBorder: Color(red: 0.29, green: 0.13, blue: 0.34).opacity(0.16),
        strongBorder: Color.white.opacity(0.72),
        textPrimary: Color(red: 0.20, green: 0.10, blue: 0.26),
        textSecondary: Color(red: 0.36, green: 0.21, blue: 0.37),
        textTertiary: Color(red: 0.49, green: 0.34, blue: 0.46),
        glow: Color(red: 0.97, green: 0.48, blue: 0.54).opacity(0.26)
    )
}

enum Theme {
    static let modeStorageKey = "inventory.theme.mode"

    static var mode: ThemeMode {
        let rawValue = UserDefaults.standard.string(forKey: modeStorageKey)
        return ThemeMode(rawValue: rawValue ?? "") ?? .vibrant
    }

    static func setMode(_ mode: ThemeMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: modeStorageKey)
    }

    private static var palette: ThemePalette {
        switch mode {
        case .classic:
            return .classic
        case .modern:
            return .modern
        case .vibrant:
            return .vibrant
        }
    }

    static var accent: Color { palette.accent }
    static var accentSoft: Color { palette.accentSoft }
    static var accentDeep: Color { palette.accentDeep }
    static var backgroundTop: Color { palette.backgroundTop }
    static var backgroundBottom: Color { palette.backgroundBottom }
    static var backgroundEdge: Color { palette.backgroundEdge }
    static var cardBackground: Color { palette.cardBackground }
    static var subtleBorder: Color { palette.subtleBorder }
    static var strongBorder: Color { palette.strongBorder }
    static var textPrimary: Color { palette.textPrimary }
    static var textSecondary: Color { palette.textSecondary }
    static var textTertiary: Color { palette.textTertiary }
    static var glow: Color { palette.glow }

    static func titleFont() -> Font {
        font(32, weight: .bold)
    }

    static func sectionFont() -> Font {
        font(11, weight: .bold)
    }

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch mode {
        case .classic:
            return .custom("Avenir Next", size: size).weight(weight)
        case .modern:
            return .custom("Avenir Next Condensed", size: size).weight(weight)
        case .vibrant:
            return .custom("Avenir Next Demi Bold", size: size).weight(weight)
        }
    }

    static func cardGradient(emphasis: Double = 0) -> LinearGradient {
        let clamped = max(0, min(emphasis, 1))
        let top: Color
        let middle: Color
        let bottom: Color
        switch mode {
        case .classic:
            top = Color(
                red: 0.99 - 0.05 * clamped,
                green: 1.00 - 0.06 * clamped,
                blue: 1.00 - 0.05 * clamped
            )
            middle = Color(
                red: 0.97 - 0.07 * clamped,
                green: 1.00 - 0.09 * clamped,
                blue: 0.99 - 0.05 * clamped
            )
            bottom = Color(
                red: 0.95 - 0.08 * clamped,
                green: 0.97 - 0.12 * clamped,
                blue: 0.97 - 0.08 * clamped
            )
        case .modern:
            top = Color(
                red: 1.00 - 0.03 * clamped,
                green: 0.99 - 0.08 * clamped,
                blue: 0.97 - 0.08 * clamped
            )
            middle = Color(
                red: 0.95 - 0.05 * clamped,
                green: 0.97 - 0.09 * clamped,
                blue: 1.00 - 0.06 * clamped
            )
            bottom = Color(
                red: 0.90 - 0.07 * clamped,
                green: 0.93 - 0.10 * clamped,
                blue: 0.98 - 0.04 * clamped
            )
        case .vibrant:
            top = Color(
                red: 1.00 - 0.02 * clamped,
                green: 0.97 - 0.06 * clamped,
                blue: 0.93 - 0.05 * clamped
            )
            middle = Color(
                red: 0.99 - 0.03 * clamped,
                green: 0.90 - 0.08 * clamped,
                blue: 0.97 - 0.07 * clamped
            )
            bottom = Color(
                red: 0.93 - 0.07 * clamped,
                green: 0.88 - 0.10 * clamped,
                blue: 0.98 - 0.08 * clamped
            )
        }
        return LinearGradient(
            colors: [top, middle, bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardSheenGradient(emphasis: Double = 0) -> LinearGradient {
        let clamped = max(0, min(emphasis, 1))
        switch mode {
        case .classic:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.44 - 0.12 * clamped),
                    accentSoft.opacity(0.20 + 0.08 * clamped),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .modern:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.52 - 0.16 * clamped),
                    accentSoft.opacity(0.22 + 0.10 * clamped),
                    accent.opacity(0.10 + 0.06 * clamped)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .vibrant:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.56 - 0.18 * clamped),
                    accentSoft.opacity(0.24 + 0.12 * clamped),
                    accent.opacity(0.12 + 0.08 * clamped)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func rimGradient(emphasis: Double = 0) -> LinearGradient {
        let clamped = max(0, min(emphasis, 1))
        return LinearGradient(
            colors: [
                strongBorder.opacity(0.52 + 0.22 * clamped),
                subtleBorder.opacity(0.75),
                accent.opacity(0.18 + 0.10 * clamped)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardShadow(emphasis: Double = 0) -> Color {
        let clamped = max(0, min(emphasis, 1))
        switch mode {
        case .classic:
            return Color.black.opacity(0.10 + 0.08 * clamped)
        case .modern:
            return Color(red: 0.05, green: 0.08, blue: 0.17).opacity(0.12 + 0.10 * clamped)
        case .vibrant:
            return Color(red: 0.30, green: 0.11, blue: 0.35).opacity(0.14 + 0.12 * clamped)
        }
    }

    static func pillGradient() -> LinearGradient {
        switch mode {
        case .classic:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.76),
                    accentSoft.opacity(0.30),
                    accent.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .modern:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.88),
                    accentSoft.opacity(0.42),
                    accent.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .vibrant:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.90),
                    accentSoft.opacity(0.44),
                    accent.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func primaryButtonGradient(pressed: Bool) -> LinearGradient {
        let pressBoost = pressed ? -0.06 : 0
        switch mode {
        case .classic:
            return LinearGradient(
                colors: [
                    accent.opacity(0.95 + pressBoost),
                    accentDeep.opacity(0.92 + pressBoost)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .modern:
            return LinearGradient(
                colors: [
                    accent.opacity(0.98 + pressBoost),
                    accentDeep.opacity(0.96 + pressBoost)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .vibrant:
            return LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.42, blue: 0.50).opacity(0.98 + pressBoost),
                    Color(red: 0.54, green: 0.24, blue: 0.86).opacity(0.95 + pressBoost)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func secondaryButtonGradient(pressed: Bool) -> LinearGradient {
        let pressAlpha = pressed ? 0.86 : 1.0
        switch mode {
        case .classic:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.92 * pressAlpha),
                    accentSoft.opacity(0.38 * pressAlpha)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .modern:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.94 * pressAlpha),
                    accentSoft.opacity(0.42 * pressAlpha)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .vibrant:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.94 * pressAlpha),
                    accentSoft.opacity(0.46 * pressAlpha),
                    accent.opacity(0.12 * pressAlpha)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func moduleVisual(_ module: InventoryModule) -> InventoryModuleVisual {
        switch module {
        case .counts:
            return InventoryModuleVisual(
                tint: Color(red: 0.20, green: 0.58, blue: 0.88),
                softTint: Color(red: 0.76, green: 0.89, blue: 1.00),
                deepTint: Color(red: 0.12, green: 0.34, blue: 0.62),
                symbol: "target"
            )
        case .replenishment:
            return InventoryModuleVisual(
                tint: Color(red: 0.16, green: 0.66, blue: 0.48),
                softTint: Color(red: 0.78, green: 0.95, blue: 0.86),
                deepTint: Color(red: 0.11, green: 0.38, blue: 0.24),
                symbol: "chart.line.uptrend.xyaxis"
            )
        case .shrink:
            return InventoryModuleVisual(
                tint: Color(red: 0.93, green: 0.42, blue: 0.25),
                softTint: Color(red: 1.00, green: 0.87, blue: 0.74),
                deepTint: Color(red: 0.56, green: 0.22, blue: 0.13),
                symbol: "exclamationmark.triangle.fill"
            )
        case .automation:
            return InventoryModuleVisual(
                tint: Color(red: 0.60, green: 0.43, blue: 0.95),
                softTint: Color(red: 0.89, green: 0.84, blue: 1.00),
                deepTint: Color(red: 0.31, green: 0.18, blue: 0.62),
                symbol: "sparkles.rectangle.stack.fill"
            )
        case .intelligence:
            return InventoryModuleVisual(
                tint: Color(red: 0.20, green: 0.63, blue: 0.62),
                softTint: Color(red: 0.78, green: 0.94, blue: 0.92),
                deepTint: Color(red: 0.12, green: 0.36, blue: 0.35),
                symbol: "waveform.path.ecg.rectangle"
            )
        case .trust:
            return InventoryModuleVisual(
                tint: Color(red: 0.31, green: 0.54, blue: 0.93),
                softTint: Color(red: 0.80, green: 0.88, blue: 1.00),
                deepTint: Color(red: 0.19, green: 0.32, blue: 0.63),
                symbol: "checkmark.shield.fill"
            )
        case .catalog:
            return InventoryModuleVisual(
                tint: Color(red: 0.79, green: 0.45, blue: 0.27),
                softTint: Color(red: 0.95, green: 0.84, blue: 0.76),
                deepTint: Color(red: 0.46, green: 0.25, blue: 0.14),
                symbol: "shippingbox.fill"
            )
        case .reports:
            return InventoryModuleVisual(
                tint: Color(red: 0.40, green: 0.53, blue: 0.93),
                softTint: Color(red: 0.84, green: 0.88, blue: 1.00),
                deepTint: Color(red: 0.23, green: 0.30, blue: 0.62),
                symbol: "chart.bar.fill"
            )
        case .support:
            return InventoryModuleVisual(
                tint: Color(red: 0.68, green: 0.39, blue: 0.82),
                softTint: Color(red: 0.91, green: 0.82, blue: 0.98),
                deepTint: Color(red: 0.36, green: 0.20, blue: 0.51),
                symbol: "questionmark.bubble.fill"
            )
        case .workspace:
            return InventoryModuleVisual(
                tint: Color(red: 0.93, green: 0.36, blue: 0.46),
                softTint: Color(red: 1.00, green: 0.82, blue: 0.86),
                deepTint: Color(red: 0.53, green: 0.19, blue: 0.28),
                symbol: "briefcase.fill"
            )
        }
    }

    static func moduleChipGradient(_ module: InventoryModule, pressed: Bool = false) -> LinearGradient {
        let visual = moduleVisual(module)
        let alpha = pressed ? 0.88 : 1
        return LinearGradient(
            colors: [
                Color.white.opacity(0.92 * alpha),
                visual.softTint.opacity(0.84 * alpha),
                visual.tint.opacity(0.18 * alpha)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func inputPrompt(_ title: String) -> Text {
        Text(title)
            .foregroundStyle(textTertiary.opacity(0.8))
    }
}

private struct InventoryCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let emphasis: Double

    func body(content: Content) -> some View {
        let clamped = max(0, min(emphasis, 1))
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(
                shape
                    .fill(Theme.cardGradient(emphasis: clamped))
                    .overlay(
                        shape
                            .fill(Theme.cardSheenGradient(emphasis: clamped))
                            .blendMode(.screen)
                    )
            )
            .overlay(
                shape
                    .stroke(Theme.subtleBorder.opacity(0.9), lineWidth: 1)
            )
            .overlay(
                shape
                    .stroke(Theme.rimGradient(emphasis: clamped), lineWidth: 0.9)
            )
            .overlay(
                shape
                    .stroke(Color.white.opacity(0.22 + 0.12 * clamped), lineWidth: 0.6)
                    .blur(radius: 0.25)
                    .blendMode(.screen)
            )
            .shadow(
                color: Theme.cardShadow(emphasis: clamped),
                radius: 14 + 10 * clamped,
                x: 0,
                y: 6 + 4 * clamped
            )
            .shadow(
                color: Theme.accent.opacity(0.04 + 0.08 * clamped),
                radius: 18 + 12 * clamped,
                x: 0,
                y: 0
            )
            .compositingGroup()
    }
}

private struct InventoryTextInputFieldModifier: ViewModifier {
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .font(Theme.font(14, weight: .medium))
            .foregroundColor(Theme.textPrimary)
            .tint(Theme.accentDeep)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.textSecondary.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct InventoryPrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.98))
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.primaryButtonGradient(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.85)
            )
            .shadow(
                color: Theme.accent.opacity(configuration.isPressed ? 0.14 : 0.24),
                radius: configuration.isPressed ? 4 : 10,
                x: 0,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct InventorySecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.secondaryButtonGradient(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Theme.strongBorder.opacity(0.55), lineWidth: 0.85)
            )
            .shadow(
                color: Theme.cardShadow(emphasis: configuration.isPressed ? 0.16 : 0.3),
                radius: configuration.isPressed ? 3 : 8,
                x: 0,
                y: configuration.isPressed ? 1 : 3
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct InventoryInteractiveRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.94 : 1)
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .shadow(
                color: Theme.accent.opacity(configuration.isPressed ? 0.08 : 0),
                radius: configuration.isPressed ? 6 : 0,
                x: 0,
                y: configuration.isPressed ? 2 : 0
            )
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct InventoryStaggeredEntranceModifier: ViewModifier {
    let index: Int
    let baseDelay: Double
    let initialYOffset: CGFloat
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : initialYOffset)
            .scaleEffect(isVisible ? 1 : 0.985)
            .onAppear {
                guard !isVisible else { return }
                withAnimation(
                    .spring(response: 0.54, dampingFraction: 0.84)
                        .delay(Double(max(0, index)) * baseDelay)
                ) {
                    isVisible = true
                }
            }
    }
}

struct InventoryModuleBadge: View {
    let module: InventoryModule
    var symbol: String? = nil
    var size: CGFloat = 34

    var body: some View {
        let visual = Theme.moduleVisual(module)
        Image(systemName: symbol ?? visual.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(visual.tint)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(Theme.moduleChipGradient(module))
            )
            .overlay(
                Circle()
                    .stroke(Theme.strongBorder.opacity(0.56), lineWidth: 0.8)
            )
    }
}

extension View {
    func inventoryCard(cornerRadius: CGFloat = 18, emphasis: Double = 0) -> some View {
        modifier(InventoryCardModifier(cornerRadius: cornerRadius, emphasis: emphasis))
    }

    func inventoryPrimaryAction() -> some View {
        buttonStyle(InventoryPrimaryActionButtonStyle())
    }

    func inventorySecondaryAction() -> some View {
        buttonStyle(InventorySecondaryActionButtonStyle())
    }

    func inventoryInteractiveRow() -> some View {
        buttonStyle(InventoryInteractiveRowButtonStyle())
    }

    func inventoryStaggered(
        index: Int,
        baseDelay: Double = 0.05,
        initialYOffset: CGFloat = 18
    ) -> some View {
        modifier(
            InventoryStaggeredEntranceModifier(
                index: index,
                baseDelay: baseDelay,
                initialYOffset: initialYOffset
            )
        )
    }

    func inventoryTextInputField(
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 11
    ) -> some View {
        modifier(
            InventoryTextInputFieldModifier(
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
        )
    }
}
