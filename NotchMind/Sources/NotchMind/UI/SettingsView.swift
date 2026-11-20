import AppKit
import CoreGraphics
import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var settings: SettingsStore
    @State private var newSiteKeyword: String = ""
    @State private var newFocusKeyword: String = ""
    @State private var hasScreenPermission: Bool = CGPreflightScreenCaptureAccess()

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section("外观与液态玻璃（macOS 原生 Liquid Glass）") {
                Picker("HUD 外观模式", selection: $settings.capsuleStyle) {
                    ForEach(CapsuleStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Text("刘海屏收起时始终为纯黑，以融合硬件刘海")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if settings.capsuleStyle == .liquidGlass {
                    Picker("玻璃色调档位", selection: Binding(
                        get: { settings.glassToneTier },
                        set: { settings.applyGlassToneTier($0) }
                    )) {
                        ForEach(GlassToneTier.allCases) { tier in
                            Text(tier.label).tag(tier)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        ForEach(GlassToneTier.allCases) { tier in
                            let selected = (settings.glassToneTier == tier)
                            let previewShape = ConcaveNotchShape(
                                hasNotch: false,
                                topEarRadius: 0,
                                bottomRadius: 8
                            )
                            let spec = SurfaceSpec.resolve(
                                style: .liquidGlass,
                                preset: tier == .clear ? .clear : (tier == .tinted ? .tintedDark : .regular),
                                intensity: tier.targetIntensity,
                                isExpanded: true,
                                hasNotch: false,
                                reduceTransparency: false,
                                increasedContrast: false
                            )
                            Button {
                                settings.applyGlassToneTier(tier)
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        NotchSurface(shape: previewShape, spec: spec, notchFuseHeight: 0)
                                        Text("Aa")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(spec.palette.primary)
                                            .shadow(
                                                color: spec.needsTextShadow ? .black.opacity(0.35) : .clear,
                                                radius: spec.needsTextShadow ? 1.5 : 0,
                                                y: spec.needsTextShadow ? 0.5 : 0
                                            )
                                    }
                                    .frame(width: 64, height: 30)
                                    .clipShape(previewShape)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                    Text(tier.label)
                                        .font(.system(size: 11))
                                        .foregroundStyle(selected ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("色调强度")
                            Spacer()
                            Text(settings.glassToneTier.label)
                                .font(.system(size: 11, weight: .semibold))
                            Text("\(Int(settings.glassTintIntensity * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.glassTintIntensity, in: 0.0...1.0, step: 0.05)
                        Text(settings.glassToneTier.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("允许录屏与截图显示 HUD", isOn: $settings.allowScreenRecording)
            }

            Section("外接显示器挂载策略（自适应不同比例显示器）") {
                Picker("挂载位置", selection: $settings.externalDisplayPlacement) {
                    ForEach(ExternalDisplayPlacement.allCases) { placement in
                        Text(placement.label).tag(placement)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.externalDisplayPlacement.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("当前屏幕比例")
                    Spacer()
                    Text(screenRatioDescription)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if settings.externalDisplayPlacement == .custom {
                    HStack {
                        Text("记忆位置：水平 \(Int(settings.externalDisplayCustomXRatio * 100))%，顶距 \(Int(settings.externalDisplayCustomYOffset)) pt")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("重置为顶部居中") {
                            settings.externalDisplayPlacement = .topCenter
                        }
                        .font(.system(size: 11))
                    }
                }
            }

            Section("模型与接口") {
                SecureField("GEMINI_API_KEY", text: $settings.apiKey)
                TextField("GEMINI_MODEL", text: $settings.modelName)
            }

            Section("监测模式与学习目标（按需监测 + 反哺项目）") {
                Picker("监测模式", selection: $settings.monitoringMode) {
                    ForEach(MonitoringMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.monitoringMode.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("当前学习目标（如：Blender 角色建模与材质优化）", text: $settings.focusGoalTitle)
                TextField("项目痛点/背景（告诉 AI 你想优化什么）", text: $settings.projectContext)

                VStack(alignment: .leading, spacing: 6) {
                    Text("聚焦关键词（聚焦模式下仅命中这些词时自动伴学）")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if !settings.focusKeywords.isEmpty {
                        FlowTagList(tags: settings.focusKeywords) { tag in
                            settings.focusKeywords.removeAll { $0 == tag }
                        }
                    }
                    HStack {
                        TextField("添加聚焦词（如 blender、shader、swiftui）", text: $newFocusKeyword)
                            .onSubmit { addFocusKeyword() }
                        Button("添加") { addFocusKeyword() }
                    }
                }

                HStack {
                    TextField("项目反哺文档路径（留空则写入 Vault/05-项目孵化池/99-项目反哺清单.md）", text: $settings.projectFeedbackPath)
                    Button("选择") { pickFeedbackFolder() }
                }
            }

            Section("伴随同看与白名单") {
                Toggle("自动识别剪贴板视频/知识链接", isOn: $settings.clipboardWatchEnabled)
                Stepper(
                    value: $settings.captureIntervalSeconds,
                    in: 6...120,
                    step: 2
                ) {
                    HStack {
                        Text("自动抓拍间隔")
                        Spacer()
                        Text("\(Int(settings.captureIntervalSeconds)) 秒")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("浏览器标题白名单（PiliPlus 始终在白名单内）")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    FlowTagList(tags: settings.allowedSiteKeywords) { tag in
                        settings.allowedSiteKeywords.removeAll { $0 == tag }
                    }
                    HStack {
                        TextField("添加站点关键词（如 bilibili、youtube）", text: $newSiteKeyword)
                            .onSubmit { addKeyword() }
                        Button("添加") { addKeyword() }
                    }
                }
            }

            Section("知识库路径") {
                HStack {
                    TextField("Obsidian Vault 路径", text: $settings.vaultPath)
                    Button("选择") { pickVaultFolder() }
                }
            }

            Section("系统权限（仅 NotchMind 单一主体）") {
                HStack {
                    Text("屏幕录制权限")
                    Spacer()
                    Text(hasScreenPermission ? "已授权" : "未授权")
                        .foregroundStyle(hasScreenPermission ? .secondary : Color.red)
                    Button("打开系统设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                HStack {
                    Text("手动抓拍快捷键")
                    Spacer()
                    Text("⌘ ⇧ S")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 680)
        .onAppear {
            hasScreenPermission = CGPreflightScreenCaptureAccess()
        }
    }

    private var screenRatioDescription: String {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return "默认 16:9" }
        let sf = screen.frame
        let ratio = sf.height > 0 ? (sf.width / sf.height) : 1.77
        let metrics = ScreenNotchMetrics.detect(for: screen)
        let notchText = metrics.hasNotch ? " (内置刘海屏)" : " (外接/无刘海屏)"
        if ratio >= 2.2 {
            return "21:9 超宽带鱼屏\(notchText)"
        } else if ratio >= 1.7 {
            return "16:9 标准宽屏\(notchText)"
        } else if ratio >= 1.55 {
            return "16:10 生产力屏\(notchText)"
        } else {
            return "\(Int(sf.width))×\(Int(sf.height))\(notchText)"
        }
    }

    private func addFocusKeyword() {
        let trimmed = newFocusKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.focusKeywords.contains(trimmed) else { return }
        settings.focusKeywords.append(trimmed)
        newFocusKeyword = ""
    }

    private func pickFeedbackFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.projectFeedbackPath = url.path
        }
    }

    private func addKeyword() {
        let trimmed = newSiteKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.allowedSiteKeywords.contains(trimmed) else { return }
        settings.allowedSiteKeywords.append(trimmed)
        newSiteKeyword = ""
    }

    private func pickVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.vaultPath = url.path
        }
    }
}

private struct FlowTagList: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(.system(size: 12))
                    Button {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                )
            }
        }
    }
}
