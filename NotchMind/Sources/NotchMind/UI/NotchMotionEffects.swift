import SwiftUI

public enum NotchSpring {
    /// Asymmetric expansion: gentle bounce like liquid emerging from the notch.
    public static let expand = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Asymmetric collapse: critically damped, crisp, zero overshoot.
    public static let collapse = Animation.spring(response: 0.30, dampingFraction: 1.0)
    /// Ear extension & status transitions.
    public static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
    /// Mode pill sliding & card expansion.
    public static let slide = Animation.spring(response: 0.30, dampingFraction: 0.86)
    /// Tactile button press-in.
    public static let pressIn = Animation.easeOut(duration: 0.08)
    /// Tactile button release.
    public static let release = Animation.spring(response: 0.26, dampingFraction: 0.58)
    /// Hover micro-feedback.
    public static let micro = Animation.easeOut(duration: 0.12)

    public static func expandAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : expand
    }

    public static func collapseAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : collapse
    }
}

/// Tactile press feedback style for HUD buttons and cards.
public struct NotchPressStyle: ButtonStyle {
    public var scale: CGFloat

    public init(scale: CGFloat = 0.94) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(
                configuration.isPressed ? NotchSpring.pressIn : NotchSpring.release,
                value: configuration.isPressed
            )
    }
}

/// Staggered entrance animation for expanded HUD sections.
/// Entry only — exit is handled by fast opacity fade-out on the parent container.
public struct StaggerReveal: ViewModifier {
    public let index: Int
    public let revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(index: Int, revealed: Bool) {
        self.index = index
        self.revealed = revealed
    }

    public func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : -6)
            .blur(radius: revealed || reduceMotion ? 0 : 4)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.34, dampingFraction: 0.84)
                        .delay(0.05 + Double(index) * 0.035),
                value: revealed
            )
    }
}

public extension View {
    func staggerReveal(index: Int, revealed: Bool) -> some View {
        modifier(StaggerReveal(index: index, revealed: revealed))
    }
}

/// Compact 3-bar fluid waveform indicator for active watching / analyzing states.
/// Automatically falls back to a static balanced glyph when Reduce Motion is enabled.
public struct NotchWaveformView: View {
    public let isAnalyzing: Bool
    public let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Bool = false

    public init(isAnalyzing: Bool, tint: Color) {
        self.isAnalyzing = isAnalyzing
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 2) {
            bar(minHeight: 4, maxHeight: isAnalyzing ? 12 : 9, delay: 0.0)
            bar(minHeight: 6, maxHeight: isAnalyzing ? 14 : 11, delay: 0.14)
            bar(minHeight: 4, maxHeight: isAnalyzing ? 11 : 8, delay: 0.28)
        }
        .frame(width: 14, height: 14, alignment: .center)
        .onAppear {
            guard !reduceMotion else { return }
            phase = true
        }
        .onDisappear {
            phase = false
        }
    }

    private func bar(minHeight: CGFloat, maxHeight: CGFloat, delay: Double) -> some View {
        let height: CGFloat = reduceMotion ? (minHeight + maxHeight) * 0.5 : (phase ? maxHeight : minHeight)
        return Capsule(style: .continuous)
            .fill(tint)
            .frame(width: 2.4, height: height)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: isAnalyzing ? 0.42 : 0.72)
                        .repeatForever(autoreverses: true)
                        .delay(delay),
                value: phase
            )
    }
}
