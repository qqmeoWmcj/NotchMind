import SwiftUI

/// Tactile, legible action button with large text designed for non-coder users.
struct SkillActionButton: View {
    let title: String
    let symbol: String
    let isHighlighted: Bool
    var isDone: Bool = false
    let action: () -> Void

    @Environment(\.notchPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isDone ? "checkmark" : symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isDone ? Color.green : (isHighlighted ? palette.primary : palette.secondary))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isDone ? Color.green : (isHighlighted ? palette.primary : palette.secondary))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isDone ? Color.green.opacity(0.12) : (isHighlighted ? palette.primary.opacity(0.14) : palette.fill))
            )
        }
        .buttonStyle(NotchPressStyle(scale: 0.95))
    }
}

/// One-click external tool/repo pills discovered in posts or comments.
struct SkillTreasureLinksView: View {
    let links: [TreasureLink]
    let onOpen: (TreasureLink) -> Void

    @Environment(\.notchPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("宝藏外链")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)

            FlowLayout(spacing: 6) {
                ForEach(links) { link in
                    Button {
                        onOpen(link)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 9, weight: .regular))
                            Text(link.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .regular))
                                .foregroundStyle(palette.tertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(palette.fill)
                        )
                        .foregroundStyle(palette.primary.opacity(0.92))
                    }
                    .buttonStyle(NotchPressStyle(scale: 0.95))
                    .help(link.why ?? link.url)
                }
            }
        }
    }
}

/// Simple flow layout helper for treasure link capsules.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                height += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

/// Standalone payload code/prompt card with inline copy button and state
struct SkillPayloadBlockView: View {
    let payload: CopyPayload
    let isCopied: Bool
    let onCopy: () -> Void

    @Environment(\.notchPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(payload.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.primary)
                Spacer()
                if let note = payload.sourceNote, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.tertiary)
                }
            }
            Text(payload.content)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.secondary)
                .lineLimit(8)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.fill))

            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(isCopied ? "已拷贝到剪贴板" : "拷贝此载荷")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(palette.fillHover))
                .foregroundStyle(palette.primary)
            }
            .buttonStyle(NotchPressStyle(scale: 0.96))
        }
        .padding(.vertical, 2)
    }
}

func timeAgoString(from iso: String) -> String {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: iso) else { return "刚刚" }
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "刚刚" }
    if seconds < 3600 { return "\(seconds / 60) 分钟前" }
    if seconds < 86400 { return "\(seconds / 3600) 小时前" }
    return "\(seconds / 86400) 天前"
}
