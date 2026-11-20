import SwiftUI

/// Unified Raycast-style command bar: paste a URL to analyze, or type keywords to filter cards.
/// Right-side action button morphs between "抓当前帧 ⌘⇧S" and "拆解" when input is a URL.
struct NotchCommandBar: View {
    @ObservedObject var engine: CompanionEngine
    @Environment(\.notchPalette) private var palette

    private var isURLInput: Bool {
        let trimmed = engine.manualLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return URLCanonicalizer.isSupportedWebURL(trimmed) || URLCanonicalizer.extractBVID(from: trimmed) != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isURLInput ? "link" : "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(palette.tertiary)
                .contentTransition(.symbolEffect(.replace))

            TextField("粘贴链接拆解，或搜索知识点…", text: $engine.manualLinkInput)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.primary)
                .onChange(of: engine.manualLinkInput) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isURL = URLCanonicalizer.isSupportedWebURL(trimmed) || URLCanonicalizer.extractBVID(from: trimmed) != nil
                    engine.searchQuery = isURL ? "" : trimmed
                }
                .onSubmit {
                    if isURLInput {
                        engine.submitManualLink()
                    }
                }

            if !engine.manualLinkInput.isEmpty && !isURLInput {
                Button {
                    engine.manualLinkInput = ""
                    engine.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.tertiary)
                }
                .buttonStyle(NotchPressStyle(scale: 0.88))
                .help("清空搜索")
            }

            Button {
                if isURLInput {
                    engine.submitManualLink()
                } else {
                    engine.triggerManualCapture()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(isURLInput ? "拆解" : "抓当前帧")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.primary)
                        .contentTransition(.interpolate)
                    if !isURLInput {
                        Text("⌘⇧S")
                            .font(.system(size: 11, weight: .regular))
                            .monospacedDigit()
                            .foregroundStyle(palette.tertiary)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.fillSelected)
                )
            }
            .buttonStyle(NotchPressStyle(scale: 0.96))
            .help(isURLInput ? "按当前学习目标拆解链接" : "抓取当前窗口帧并提炼知识点 (⌘⇧S)")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.fill)
        )
    }
}
