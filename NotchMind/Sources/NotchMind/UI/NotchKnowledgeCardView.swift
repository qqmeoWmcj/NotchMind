import SwiftUI

/// Compact-by-default knowledge card (44pt) with hover-revealed actions, context menu,
/// and deep Feynman / project-feedback / self-check expansion.
struct NotchKnowledgeCardView: View {
    @ObservedObject var engine: CompanionEngine
    let entry: KnowledgeEntry
    let isExpanded: Bool
    let isHovered: Bool
    let isFlashing: Bool
    let onToggleExpand: () -> Void
    let onHoverChanged: (Bool) -> Void

    @Environment(\.notchPalette) private var palette
    @State private var revealedQuizIDs: Set<String> = []
    @State private var hoveredAction: String?

    private var backgroundFill: Color {
        if isExpanded || isFlashing {
            return palette.fillSelected
        }
        return isHovered ? palette.fillHover : palette.fill
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            if isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundFill)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onToggleExpand)
        .onHover(perform: onHoverChanged)
        .animation(NotchSpring.micro, value: isHovered)
        .animation(.easeOut(duration: 0.6), value: isFlashing)
        .contextMenu {
            Button("导出到项目优化清单") {
                engine.exportFeedbackToProject(entry)
            }
            Button("拷贝实操任务配方 (Markdown)") {
                engine.copyActionRecipe(entry)
            }
            Button("拷贝核心参数与结论") {
                engine.copyEssence(entry)
            }
            Button("在 Obsidian 打开") {
                engine.openInObsidian(entry)
            }
            if URLCanonicalizer.isSupportedWebURL(entry.url) {
                Button("重新深拆") {
                    engine.resummarizeEntry(entry)
                }
            }
            Divider()
            Button("删除", role: .destructive) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    engine.deleteEntry(entry)
                }
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .lineLimit(isExpanded ? 2 : 1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                ZStack(alignment: .trailing) {
                    Text(relativeTimeString(from: entry.createdAt))
                        .font(.system(size: 11, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(palette.tertiary)
                        .opacity(isHovered || isExpanded ? 0 : 1)

                    actionButtons
                        .opacity(isHovered || isExpanded ? 1 : 0)
                        .allowsHitTesting(isHovered || isExpanded)
                }
                .animation(NotchSpring.micro, value: isHovered || isExpanded)
            }

            Text(entry.oneLineEssence)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.secondary)
                .lineLimit(isExpanded ? 4 : 1)
                .truncationMode(.tail)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            let exported = (engine.lastFeedbackExportedID == entry.id)
            iconButton(
                id: "feedback",
                symbol: exported ? "checkmark.circle.fill" : "arrow.uturn.left.circle",
                tint: palette.primary,
                help: "反哺到项目优化清单"
            ) {
                engine.exportFeedbackToProject(entry)
            }
            .symbolEffect(.bounce, value: exported)

            let copied = (engine.lastCopiedID == entry.id)
            iconButton(
                id: "copy",
                symbol: copied ? "checkmark" : "doc.on.doc",
                tint: palette.secondary,
                help: "拷贝核心参数与结论"
            ) {
                engine.copyEssence(entry)
            }
            .symbolEffect(.bounce, value: copied)

            if URLCanonicalizer.isSupportedWebURL(entry.url) {
                iconButton(
                    id: "resummarize",
                    symbol: "arrow.clockwise",
                    tint: palette.secondary,
                    help: "按当前学习目标重新深拆"
                ) {
                    engine.resummarizeEntry(entry)
                }
            }

            iconButton(
                id: "obsidian",
                symbol: "arrow.up.right",
                tint: palette.secondary,
                help: "在 Obsidian 中打开"
            ) {
                engine.openInObsidian(entry)
            }

            iconButton(
                id: "delete",
                symbol: "trash",
                tint: hoveredAction == "delete" ? palette.destructive : palette.tertiary,
                help: "删除卡片（支持 ⌘Z 撤回）"
            ) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    engine.deleteEntry(entry)
                }
            }
        }
    }

    private func iconButton(
        id: String,
        symbol: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(hoveredAction == id ? palette.fillHover : .clear)
                )
        }
        .buttonStyle(NotchPressStyle(scale: 0.88))
        .onHover { hovering in
            withAnimation(NotchSpring.micro) {
                hoveredAction = hovering ? id : (hoveredAction == id ? nil : hoveredAction)
            }
        }
        .help(help)
    }

    // MARK: - Expanded Deep Knowledge Body

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(palette.separator)
                .frame(height: 0.5)
                .padding(.vertical, 2)

            if !entry.prerequisites.isEmpty {
                sectionHeader("前置知识")
                ForEach(entry.prerequisites.prefix(2), id: \.self) { pre in
                    bulletLine(pre, color: palette.secondary)
                }
            }

            if !entry.conceptBreakdown.isEmpty {
                sectionHeader("核心概念精讲")
                ForEach(entry.conceptBreakdown.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• \(item.term)：\(item.explanation)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.primary.opacity(0.92))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let analogy = item.analogy, !analogy.isEmpty {
                            Text("  类比：\(analogy)")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(palette.tertiary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !entry.projectOptimizations.isEmpty {
                sectionHeader("反哺项目优化")
                ForEach(entry.projectOptimizations.prefix(3), id: \.self) { opt in
                    bulletLine(opt, color: palette.primary.opacity(0.92))
                }
            }

            if !entry.actionableSteps.isEmpty {
                sectionHeader("实操步骤")
                ForEach(Array(entry.actionableSteps.prefix(3).enumerated()), id: \.offset) { idx, step in
                    Text("\(idx + 1). \(step)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !entry.pitfalls.isEmpty {
                sectionHeader("避坑与边界")
                ForEach(entry.pitfalls.prefix(2), id: \.self) { pit in
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.tertiary)
                        Text(pit)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !entry.selfCheckQA.isEmpty {
                sectionHeader("主动回忆自测")
                ForEach(entry.selfCheckQA.prefix(2)) { qa in
                    let revealed = revealedQuizIDs.contains(qa.id)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: revealed ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.tertiary)
                            Text(qa.question)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.primary.opacity(0.92))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if revealed {
                            Text(qa.answer)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(palette.secondary)
                                .lineSpacing(2)
                                .padding(.leading, 14)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(NotchSpring.micro) {
                            if revealed {
                                revealedQuizIDs.remove(qa.id)
                            } else {
                                revealedQuizIDs.insert(qa.id)
                            }
                        }
                    }
                }
            }

            if !entry.furtherExploration.isEmpty {
                sectionHeader("延伸思考")
                ForEach(entry.furtherExploration.prefix(2), id: \.self) { next in
                    bulletLine(next, color: palette.secondary)
                }
            }

            Text(entry.domain)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.tertiary)
                .padding(.top, 2)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.secondary)
            .padding(.top, 2)
    }

    private func bulletLine(_ text: String, color: Color) -> some View {
        Text("• \(text)")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(color)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func relativeTimeString(from iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "刚刚" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }
        if seconds < 86400 { return "\(seconds / 3600) 小时前" }
        return "\(seconds / 86400) 天前"
    }
}
