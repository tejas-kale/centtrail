import SwiftUI

/// The Ayu colour theme (https://github.com/ayu-theme/ayu-colors, themes/*.yaml).
///
/// `accent` and `onAccent` are Ayu's `common.accent.tint` and `.on`; surfaces come from
/// `surface` and `ui.panel`; `text` is `editor.fg` over the row colour. Ayu Light's
/// accent, error, vcs-added and orange are too pale for text on a light background, so
/// their `tint`, `error`, `positive` and `warning` are the same hues darkened in OKLCH
/// until they reach 4.5:1 (AyuPaletteTests checks every pair).
struct AyuPalette: Equatable {
    var background: UInt32
    var row: UInt32
    var text: UInt32
    var tint: UInt32
    var accent: UInt32
    var onAccent: UInt32
    var error: UInt32
    var positive: UInt32
    var warning: UInt32
}

enum AyuVariant: String, CaseIterable, Sendable {
    case light, mirage, dark

    var palette: AyuPalette {
        switch self {
        case .light:
            AyuPalette(background: 0xEBEEF0, row: 0xFCFCFC, text: 0x5C6166, tint: 0xAA5400,
                       accent: 0xF29718, onAccent: 0x913D00,
                       error: 0xC83237, positive: 0x287B00, warning: 0xB84900)
        case .mirage:
            AyuPalette(background: 0x1F2430, row: 0x282E3B, text: 0xCDCBC3, tint: 0xFFCC66,
                       accent: 0xFFCC66, onAccent: 0x825400,
                       error: 0xFF6666, positive: 0x87D96C, warning: 0xFFA659)
        case .dark:
            AyuPalette(background: 0x0D1017, row: 0x141821, text: 0xC0BEB7, tint: 0xE6B450,
                       accent: 0xE6B450, onAccent: 0x835500,
                       error: 0xD95757, positive: 0x70BF56, warning: 0xFF8F40)
        }
    }

    static func forAppearance(isDark: Bool, darkChoice: AyuDarkChoice) -> AyuVariant {
        guard isDark else { return .light }
        return darkChoice == .dark ? .dark : .mirage
    }
}

/// Which Ayu variant the app uses when the system is in Dark Mode.
enum AyuDarkChoice: String, CaseIterable, Identifiable, Sendable {
    case mirage, dark

    static let `default` = AyuDarkChoice.mirage
    static let storageKey = "ayuDarkTheme"

    var id: Self { self }
    var title: String { self == .mirage ? "Mirage" : "Dark" }
}

extension Color {
    init(ayuHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension EnvironmentValues {
    @Entry var ayuDarkChoice: AyuDarkChoice = .default
}

/// One Ayu role, resolved against the view's colour scheme and dark-theme choice.
struct AyuStyle: ShapeStyle {
    enum Role { case background, row, text, tint, accent, onAccent, error, positive, warning }

    let role: Role

    func resolve(in environment: EnvironmentValues) -> Color {
        let palette = AyuVariant.forAppearance(
            isDark: environment.colorScheme == .dark,
            darkChoice: environment.ayuDarkChoice
        ).palette
        let hex: UInt32 = switch role {
        case .background: palette.background
        case .row: palette.row
        case .text: palette.text
        case .tint: palette.tint
        case .accent: palette.accent
        case .onAccent: palette.onAccent
        case .error: palette.error
        case .positive: palette.positive
        case .warning: palette.warning
        }
        return Color(ayuHex: hex)
    }
}

extension ShapeStyle where Self == AyuStyle {
    static var ayuBackground: AyuStyle { AyuStyle(role: .background) }
    static var ayuRow: AyuStyle { AyuStyle(role: .row) }
    static var ayuText: AyuStyle { AyuStyle(role: .text) }
    static var ayuTint: AyuStyle { AyuStyle(role: .tint) }
    static var ayuAccent: AyuStyle { AyuStyle(role: .accent) }
    static var ayuOnAccent: AyuStyle { AyuStyle(role: .onAccent) }
    static var ayuError: AyuStyle { AyuStyle(role: .error) }
    static var ayuPositive: AyuStyle { AyuStyle(role: .positive) }
    static var ayuWarning: AyuStyle { AyuStyle(role: .warning) }
}

/// Applies the theme to a view tree: tint, text colour and the dark-theme choice.
/// Sheets get it again at their root, so they match the screen that opened them.
private struct AyuThemeModifier: ViewModifier {
    @AppStorage(AyuDarkChoice.storageKey) private var darkChoice: AyuDarkChoice = .default
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = AyuVariant.forAppearance(isDark: colorScheme == .dark, darkChoice: darkChoice).palette
        content
            .environment(\.ayuDarkChoice, darkChoice)
            .tint(Color(ayuHex: palette.tint))
            .foregroundStyle(Color(ayuHex: palette.text))
    }
}

extension View {
    func ayuTheme() -> some View { modifier(AyuThemeModifier()) }

    /// Ayu background behind a List or Form; pair with `ayuRows()` on each section.
    func ayuGroupedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(.ayuBackground)
    }

    /// Ayu row colour for every row of a List or Form section.
    func ayuRows() -> some View {
        listRowBackground(Rectangle().fill(.ayuRow))
    }
}

/// The app's filled call-to-action: Ayu accent with Ayu's on-accent text.
struct AyuProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.ayuOnAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.ayuAccent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == AyuProminentButtonStyle {
    static var ayuProminent: AyuProminentButtonStyle { AyuProminentButtonStyle() }
}
