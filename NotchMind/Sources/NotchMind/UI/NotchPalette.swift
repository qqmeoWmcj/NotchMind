import SwiftUI

/// Semantic monochrome palette injected via `@Environment(\.notchPalette)`.
/// Strictly adheres to DESIGN.md §2: black/white/gray only, with `destructive` (red) as the sole semantic exception.
public struct NotchPalette: Equatable, Sendable {
    public let scheme: ColorScheme
    public let primary: Color
    public let secondary: Color
    public let tertiary: Color
    public let fill: Color
    public let fillHover: Color
    public let fillSelected: Color
    public let separator: Color
    public let destructive: Color = .red

    public static let dark = NotchPalette(
        scheme: .dark,
        primary: .white,
        secondary: .white.opacity(0.72),
        tertiary: .white.opacity(0.48),
        fill: .white.opacity(0.07),
        fillHover: .white.opacity(0.12),
        fillSelected: .white.opacity(0.18),
        separator: .white.opacity(0.08)
    )

    public static let light = NotchPalette(
        scheme: .light,
        primary: .black.opacity(0.88),
        secondary: .black.opacity(0.60),
        tertiary: .black.opacity(0.42),
        fill: .black.opacity(0.05),
        fillHover: .black.opacity(0.08),
        fillSelected: .black.opacity(0.13),
        separator: .black.opacity(0.07)
    )

    public func withIncreasedContrast() -> NotchPalette {
        switch scheme {
        case .dark:
            return NotchPalette(
                scheme: .dark,
                primary: .white,
                secondary: .white.opacity(0.85),
                tertiary: .white.opacity(0.62),
                fill: .white.opacity(0.11),
                fillHover: .white.opacity(0.17),
                fillSelected: .white.opacity(0.24),
                separator: .white.opacity(0.16)
            )
        case .light:
            return NotchPalette(
                scheme: .light,
                primary: .black,
                secondary: .black.opacity(0.85),
                tertiary: .black.opacity(0.58),
                fill: .black.opacity(0.08),
                fillHover: .black.opacity(0.12),
                fillSelected: .black.opacity(0.18),
                separator: .black.opacity(0.14)
            )
        @unknown default:
            return self
        }
    }
}

private struct NotchPaletteKey: EnvironmentKey {
    static let defaultValue: NotchPalette = .dark
}

public extension EnvironmentValues {
    var notchPalette: NotchPalette {
        get { self[NotchPaletteKey.self] }
        set { self[NotchPaletteKey.self] = newValue }
    }
}
