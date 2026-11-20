import SwiftUI

/// Programmatic vector brand emblem for NotchMind:
/// Dark obsidian squircle + concave notch silhouette + luminous neural spark.
public struct NotchIconView: View {
    public let size: CGFloat

    public init(size: CGFloat = 24) {
        self.size = size
    }

    public var body: some View {
        let corner = size * 0.26
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.12, blue: 0.18),
                            Color(red: 0.04, green: 0.05, blue: 0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle top concave notch pill
            VStack(spacing: 0) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: size * 0.48, height: max(size * 0.14, 2.5))
                    .padding(.top, size * 0.12)
                Spacer()
            }

            // Luminous neural spark at center-bottom
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.85, blue: 1.0),
                            Color(red: 0.58, green: 0.62, blue: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .offset(y: size * 0.10)
                .shadow(color: Color(red: 0.42, green: 0.85, blue: 1.0).opacity(0.55), radius: size * 0.14)

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.32), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(size * 0.04, 0.8)
                )
        }
        .frame(width: size, height: size)
    }
}
