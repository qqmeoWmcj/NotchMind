import SwiftUI

struct NotchExpandedContentView: View {
    @ObservedObject var engine: CompanionEngine
    @ObservedObject var settings: SettingsStore
    let metrics: ScreenNotchMetrics
    @Binding var isPinnedOpen: Bool
    let statusGlyph: AnyView
    let onOpenSettings: () -> Void

    @Environment(\.notchPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredEntryID: String?
    @State private var expandedEntryID: String?
    @State private var revealed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if metrics.hasNotch {
                Spacer().frame(height: max(metrics.notchHeight - 6, 16))
            }

            headerBar
                .staggerReveal(index: 0, revealed: revealed)

            NotchModeBar(selectedMode: settings.monitoringMode) { mode in
                engine.setMonitoringMode(mode)
            }
            .staggerReveal(index: 1, revealed: revealed)

            goalRow
                .staggerReveal(index: 2, revealed: revealed)

            NotchCommandBar(engine: engine)
                .staggerReveal(index: 3, revealed: revealed)

            recentSection

            if let undo = engine.undoBanner {
                UndoToastView(
                    action: undo,
                    onUndo: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            engine.undoLastAction()
                        }
                    },
                    onDismiss: {
                        withAnimation(NotchSpring.micro) {
                            engine.dismissUndoBanner()
                        }
                    },
                    onHoverChanged: { hovering in
                        if hovering {
                            engine.pauseUndoCountdown()
                        } else {
                            engine.resumeUndoCountdown()
                        }
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    )
                )
            }
        }
        .padding(.horizontal, metrics.hasNotch ? 29 : 14)
        .padding(.top, metrics.hasNotch ? 4 : 14)
        .padding(.bottom, 14)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: engine.undoBanner)
        .onAppear {
            revealed = true
        }
    }

    // MARK: - Header (28pt)

    private var headerBar: some View {
        HStack(spacing: 8) {
            NotchIconView(size: 18)
            statusGlyph
            Text(engine.activeTarget?.title ?? engine.status.shortLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(engine.status.isError ? palette.destructive : palette.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text("今日 \(engine.captureCountToday)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.tertiary)
                .contentTransition(.numericText(value: Double(engine.captureCountToday)))
                .animation(NotchSpring.snappy, value: engine.captureCountToday)

            Button {
                engine.openInObsidian()
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotchPressStyle(scale: 0.88))
            .help("打开 Obsidian 知识库")

            Button {
                withAnimation(NotchSpring.snappy) {
                    isPinnedOpen.toggle()
                }
            } label: {
                Image(systemName: isPinnedOpen ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isPinnedOpen ? palette.primary : palette.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .rotationEffect(.degrees(isPinnedOpen ? 0 : 45))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotchPressStyle(scale: 0.88))
            .help(isPinnedOpen ? "取消固定" : "固定展开")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotchPressStyle(scale: 0.88))
            .help("设置学习目标与外观")
        }
        .frame(height: 28)
    }

    // MARK: - Goal Row (24pt)

    private var goalRow: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: 6) {
                Image(systemName: settings.currentFocusGoal.isConfigured ? "target" : "plus.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(settings.currentFocusGoal.isConfigured ? palette.primary : palette.tertiary)

                if settings.currentFocusGoal.isConfigured {
                    Text(settings.focusGoalTitle.isEmpty ? "已配置聚焦关键词" : settings.focusGoalTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                    if !settings.focusKeywords.isEmpty {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.tertiary)
                        Text(settings.focusKeywords.prefix(3).joined(separator: " · "))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.tertiary)
                            .lineLimit(1)
                    }
                } else {
                    Text("设定学习方向与本地项目")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(settings.currentFocusGoal.isConfigured ? palette.fill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchPressStyle(scale: 0.98))
        .help("点击修改学习目标与项目反哺背景")
    }

    // MARK: - Recent Entries

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("最近")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.tertiary)
                Text("\(engine.filteredEntries.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.tertiary)
                    .contentTransition(.numericText(value: Double(engine.filteredEntries.count)))
                Spacer()
            }
            .frame(height: 16)
            .staggerReveal(index: 4, revealed: revealed)

            if engine.filteredEntries.isEmpty {
                Text(
                    engine.recentEntries.isEmpty
                        ? "暂无记录 — 按 ⌘⇧S 抓拍或粘贴链接"
                        : "未找到匹配「\(engine.searchQuery)」的卡片"
                )
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.secondary)
                .padding(.vertical, 8)
                .staggerReveal(index: 5, revealed: revealed)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(Array(engine.filteredEntries.prefix(8).enumerated()), id: \.element.id) { idx, entry in
                            NotchKnowledgeCardView(
                                engine: engine,
                                entry: entry,
                                isExpanded: expandedEntryID == entry.id,
                                isHovered: hoveredEntryID == entry.id,
                                isFlashing: engine.lastRestoredEntryID == entry.id,
                                onToggleExpand: {
                                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : NotchSpring.slide) {
                                        expandedEntryID = (expandedEntryID == entry.id) ? nil : entry.id
                                    }
                                },
                                onHoverChanged: { hovering in
                                    withAnimation(NotchSpring.micro) {
                                        hoveredEntryID = hovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
                                    }
                                }
                            )
                            .staggerReveal(index: 5 + min(idx, 4), revealed: revealed)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                    removal: .opacity
                                        .combined(with: .offset(x: -28))
                                        .combined(with: .scale(scale: 0.96, anchor: .leading))
                                )
                            )
                        }
                    }
                }
                .frame(maxHeight: 208)
            }
        }
    }
}
