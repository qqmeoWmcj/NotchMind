import Combine
import SwiftUI

/// Bottom-docked Undo Toast with 8-second countdown ring, hover-to-pause, and ⌘Z shortcut.
struct UndoToastView: View {
    let action: UndoAction
    let onUndo: () -> Void
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void

    @Environment(\.notchPalette) private var palette
    @State private var remaining: CGFloat = 1.0
    @State private var isHovered: Bool = false
    private let countdownTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var symbolName: String {
        switch action {
        case .deleted:
            return "trash"
        case .replaced:
            return "arrow.triangle.2.circlepath"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)

            Text(action.label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Button {
                onUndo()
            } label: {
                Text("撤回")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .frame(minWidth: 44, minHeight: 24)
            }
            .buttonStyle(NotchPressStyle(scale: 0.94))
            .keyboardShortcut("z", modifiers: .command)
            .help("撤回上一次操作 (⌘Z)")

            ZStack {
                Circle()
                    .stroke(palette.separator, lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: remaining)
                    .stroke(palette.tertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            .onTapGesture(perform: onDismiss)
            .help("关闭提示")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.fillSelected)
        )
        .onAppear {
            remaining = 1.0
        }
        .onChange(of: action) { _, _ in
            remaining = 1.0
        }
        .onReceive(countdownTimer) { _ in
            guard !isHovered, remaining > 0 else { return }
            remaining = max(0, remaining - CGFloat(0.05 / 8.0))
        }
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
    }
}
