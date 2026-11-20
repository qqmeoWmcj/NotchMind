import SwiftUI

/// Raycast-inspired segmented monitoring mode bar with sliding selection pill.
struct NotchModeBar: View {
    let selectedMode: MonitoringMode
    let onSelect: (MonitoringMode) -> Void

    @Environment(\.notchPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var modeNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MonitoringMode.allCases) { mode in
                let selected = (selectedMode == mode)
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : NotchSpring.slide) {
                        onSelect(mode)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 11, weight: .medium))
                        Text(mode.label)
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? palette.primary : palette.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(palette.fillSelected)
                                .matchedGeometryEffect(id: "modePill", in: modeNamespace)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(NotchPressStyle(scale: 0.96))
                .help(mode.description)
            }
        }
        .padding(2)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.fill)
        )
    }
}
