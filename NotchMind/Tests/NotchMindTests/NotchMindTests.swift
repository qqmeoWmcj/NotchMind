import Foundation
import SwiftUI
import Testing
@testable import NotchMind

@Test("URL canonicalizer extracts BVID and rejects localhost/private URLs")
func testURLCanonicalizer() {
    #expect(URLCanonicalizer.extractBVID(from: "https://www.bilibili.com/video/BV1ngWq6eEc2/?spm_id_from=333") == "BV1ngWq6eEc2")
    #expect(URLCanonicalizer.canonicalKey(from: "https://www.bilibili.com/video/BV1ngWq6eEc2/?vd_source=abc") == "bilibili:BV1ngWq6eEc2")
    #expect(URLCanonicalizer.canonicalKey(from: "https://bilibili.com/video/BV1ngWq6eEc2") == "bilibili:BV1ngWq6eEc2")

    #expect(URLCanonicalizer.isLocalOrPrivateURL("http://127.0.0.1:8765/"))
    #expect(URLCanonicalizer.isLocalOrPrivateURL("http://localhost:3000/dashboard"))
    #expect(!URLCanonicalizer.isSupportedWebURL("http://127.0.0.1:8765/"))
    #expect(URLCanonicalizer.canonicalKey(from: "http://127.0.0.1:8765/") == nil)
}

@Test("Strict whitelist blocks WeChat, IDE, NotchMind, and localhost while allowing PiliPlus and Bilibili/YouTube")
func testStrictWhitelist() {
    let sites = ["bilibili", "哔哩哔哩", "youtube"]

    // Blocked: WeChat, IDE, NotchMind, localhost browser tab, arbitrary webpage
    #expect(WindowMonitor.evaluate(frontApp: "WeChat", windowTitle: "朋友圈", windowID: 10, allowedSiteKeywords: sites) == nil)
    #expect(WindowMonitor.evaluate(frontApp: "Xcode", windowTitle: "NotchMind.swift", windowID: 11, allowedSiteKeywords: sites) == nil)
    #expect(WindowMonitor.evaluate(frontApp: "NotchMind", windowTitle: "NotchMind", windowID: 12, allowedSiteKeywords: sites) == nil)
    #expect(WindowMonitor.evaluate(frontApp: "Google Chrome", windowTitle: "http://127.0.0.1:8765/ - AI 热点工作台", windowID: 13, allowedSiteKeywords: sites) == nil)
    #expect(WindowMonitor.evaluate(frontApp: "Safari", windowTitle: "Gmail - 收件箱", windowID: 14, allowedSiteKeywords: sites) == nil)

    // Allowed: foreground PiliPlus, Bilibili browser tab, YouTube browser tab
    let pili = WindowMonitor.evaluate(frontApp: "PiliPlus", windowTitle: "AI 泡沫复盘 BV1ngWq6eEc2", windowID: 20, allowedSiteKeywords: sites)
    #expect(pili != nil)
    #expect(pili?.isPiliPlus == true)
    #expect(pili?.bvid == "BV1ngWq6eEc2")

    let bili = WindowMonitor.evaluate(frontApp: "Google Chrome", windowTitle: "深度解析_哔哩哔哩_bilibili", windowID: 21, allowedSiteKeywords: sites)
    #expect(bili != nil)
    #expect(bili?.isPiliPlus == false)

    let yt = WindowMonitor.evaluate(frontApp: "Arc", windowTitle: "Apple Design Awards - YouTube", windowID: 22, allowedSiteKeywords: sites)
    #expect(yt != nil)
}

@Test("SQLite DedupeStore enforces in-flight lock and persists across restarts")
func testSQLiteDedupeStore() async throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("notchmind_test_\(UUID().uuidString)")
    let dbURL = tmpDir.appendingPathComponent("notchmind.db")
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let store1 = try DedupeStore(dbURL: dbURL)
    let firstAcquire = await store1.beginIfNew(canonicalKey: "bilibili:BV1ngWq6eEc2")
    let concurrentAcquire = await store1.beginIfNew(canonicalKey: "bilibili:BV1ngWq6eEc2")
    #expect(firstAcquire == true)
    #expect(concurrentAcquire == false)

    await store1.markCommitted(canonicalKey: "bilibili:BV1ngWq6eEc2", kind: "url", entryID: "abc123")

    // Reopen fresh SQLite instance to verify persistence
    let store2 = try DedupeStore(dbURL: dbURL)
    let afterRestart = await store2.beginIfNew(canonicalKey: "bilibili:BV1ngWq6eEc2")
    #expect(afterRestart == false)
}

@Test("ObsidianWriter writes single-domain Markdown and deduplicates same URL with different LLM titles")
func testObsidianWriterAndURLDedupe() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("notchmind_vault_\(UUID().uuidString)")
    let vaultDir = tmpDir.appendingPathComponent("vault")
    let dataDir = tmpDir.appendingPathComponent("data")
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let e1 = KnowledgeEntry(
        title: "标题版本A：深度解析",
        source: "B站视频",
        url: "https://www.bilibili.com/video/BV1ngWq6eEc2/?spm_id_from=123",
        domain: "04-行业深度认知",
        oneLineEssence: "核心结论A",
        keyPoints: ["要点1"]
    )
    let e2 = KnowledgeEntry(
        title: "标题版本B：完全不同的大模型标题",
        source: "B站视频",
        url: "https://bilibili.com/video/BV1ngWq6eEc2",
        domain: "04-行业深度认知",
        oneLineEssence: "核心结论B"
    )

    // Same canonical BVID must produce identical stable ID
    #expect(e1.id == e2.id)

    try ObsidianWriter.saveEntry(e1, vaultDir: vaultDir, dataDir: dataDir)
    try ObsidianWriter.saveEntry(e2, vaultDir: vaultDir, dataDir: dataDir)

    let loaded = ObsidianWriter.loadEntries(dataDir: dataDir)
    #expect(loaded.count == 1)
    #expect(loaded.first?.title == "标题版本A：深度解析")

    let domainMD = try String(contentsOf: vaultDir.appendingPathComponent("04-行业深度认知.md"), encoding: .utf8)
    #expect(domainMD.contains("标题版本A：深度解析"))
    #expect(!domainMD.contains("标题版本B"))

    let consoleMD = try String(contentsOf: vaultDir.appendingPathComponent("00-控制台与速览.md"), encoding: .utf8)
    #expect(consoleMD.contains("[[04-行业深度认知]]"))
}

@Test("Intent-driven monitoring: manual never auto-captures, focused only matches focus keywords")
func testIntentDrivenMonitoringModes() {
    let sites = ["bilibili", "youtube"]
    let focus = ["blender", "shader"]

    // Manual mode never auto-captures even for whitelisted PiliPlus or matching title
    #expect(WindowMonitor.evaluate(
        frontApp: "PiliPlus",
        windowTitle: "Blender 角色材质节点教程 BV1ngWq6eEc2",
        windowID: 30,
        allowedSiteKeywords: sites,
        monitoringMode: .manual,
        focusKeywords: focus
    ) == nil)

    // Focused mode ignores unrelated Bilibili video
    #expect(WindowMonitor.evaluate(
        frontApp: "Google Chrome",
        windowTitle: "美食探店_哔哩哔哩_bilibili",
        windowID: 31,
        allowedSiteKeywords: sites,
        monitoringMode: .focused,
        focusKeywords: focus
    ) == nil)

    // Focused mode captures when focus keyword hits (browser or Blender app)
    let matched = WindowMonitor.evaluate(
        frontApp: "Google Chrome",
        windowTitle: "Blender Principled BSDF 材质节点实战 - YouTube",
        windowID: 32,
        allowedSiteKeywords: sites,
        monitoringMode: .focused,
        focusKeywords: focus
    )
    #expect(matched != nil)
    #expect(matched?.matchedSite == "聚焦·blender")

    // Focused mode with empty keywords does not match anything
    #expect(WindowMonitor.evaluate(
        frontApp: "Google Chrome",
        windowTitle: "Blender 教程 - YouTube",
        windowID: 33,
        allowedSiteKeywords: sites,
        monitoringMode: .focused,
        focusKeywords: []
    ) == nil)
}

@Test("ObsidianWriter renders deep actionable fields and appends project feedback checklist")
func testDeepKnowledgeAndProjectFeedback() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("notchmind_feedback_\(UUID().uuidString)")
    let vaultDir = tmpDir.appendingPathComponent("vault")
    let dataDir = tmpDir.appendingPathComponent("data")
    let feedbackFile = tmpDir.appendingPathComponent("project/docs/learning-feedback.md")
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let entry = KnowledgeEntry(
        title: "Blender 三点布光与 Principled BSDF 皮肤质感",
        source: "B站视频",
        url: "https://www.bilibili.com/video/BV1xx411c7mD",
        domain: "03-AI创作与3D工具",
        focusGoal: "Blender 角色建模与材质优化",
        oneLineEssence: "用 Subsurface Weight 0.25 配合 Radius (1.0, 0.2, 0.1) 可消除角色塑料感",
        keyPoints: ["Principled BSDF 开启 Random Walk 次表面散射"],
        actionableSteps: ["选中角色材质节点，将 Subsurface Weight 设为 0.25", "将 Roughness 连接到 Noise Texture + ColorRamp"],
        projectOptimizations: ["替换当前角色项目的纯色漫反射材质，改为三层粗糙度贴图叠加"],
        pitfalls: ["EEVEE Next 下需开启 Raytracing 否则次表面散射失真"]
    )

    try ObsidianWriter.saveEntry(entry, vaultDir: vaultDir, dataDir: dataDir)
    let domainMD = try String(contentsOf: vaultDir.appendingPathComponent("03-AI创作与3D工具.md"), encoding: .utf8)
    #expect(domainMD.contains("反哺项目可优化手段"))
    #expect(domainMD.contains("- [ ] 替换当前角色项目的纯色漫反射材质"))
    #expect(domainMD.contains("可落地实操步骤"))

    try ObsidianWriter.appendProjectFeedback(entry: entry, feedbackFileURL: feedbackFile)
    try ObsidianWriter.appendProjectFeedback(entry: entry, feedbackFileURL: feedbackFile)
    let fbMD = try String(contentsOf: feedbackFile, encoding: .utf8)
    #expect(fbMD.contains("# 项目反哺与优化清单"))
    #expect(fbMD.contains("- [ ] 替换当前角色项目的纯色漫反射材质"))
    #expect(fbMD.contains("Blender 角色建模与材质优化"))
    let occurrences = fbMD.components(separatedBy: "<!-- feedback_id:\(entry.id) -->").count - 1
    #expect(occurrences == 1)
}

@Test("ObsidianWriter supports deep Feynman/QA rendering, delete, undo restore, and replace")
func testDeleteRestoreReplaceAndDeepLearningFields() async throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("notchmind_undo_\(UUID().uuidString)")
    let vaultDir = tmpDir.appendingPathComponent("vault")
    let dataDir = tmpDir.appendingPathComponent("data")
    let dbURL = dataDir.appendingPathComponent("notchmind.db")
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let e1 = KnowledgeEntry(
        title: "注意力机制与 KV Cache 内存原理",
        source: "技术文章",
        url: "https://example.com/kv-cache",
        domain: "01-LLM与新模型",
        ladderLevel: "L2工具与AI联动",
        oneLineEssence: "KV Cache 通过缓存历史 Token 的 Key/Value 矩阵将自回归解码复杂度从 O(n²) 降至 O(n)",
        prerequisites: ["理解 Transformer Scaled Dot-Product Attention"],
        conceptBreakdown: [
            ConceptItem(term: "KV Cache", explanation: "缓存已生成 token 的 K/V 投影避免重复计算", analogy: "像做长除法时保留草稿纸上的中间商")
        ],
        keyPoints: ["Prefill 阶段计算密集，Decode 阶段显存带宽密集"],
        actionableSteps: ["在推理引擎开启 PagedAttention 减少显存碎片"],
        projectOptimizations: ["本地小模型服务改用 GQA + FP8 KV Cache 降低 50% 显存"],
        pitfalls: ["超长上下文下 KV Cache 会迅速撑爆显存"],
        selfCheckQA: [
            QuizItem(question: "为什么不缓存 Q 矩阵？", answer: "因为解码每步只用当前新 token 的 Q 去查询历史 K/V，历史 Q 不会再被用到。")
        ],
        furtherExploration: ["对比 MLA (Multi-head Latent Attention) 与 GQA"]
    )

    let e2 = KnowledgeEntry(
        title: "SwiftUI Liquid Glass 防遮挡实践",
        source: "技术文章",
        url: "https://example.com/liquid-glass",
        domain: "02-AI学习与教程",
        oneLineEssence: "禁止内外层嵌套 glassEffect，仅外层使用液态玻璃并叠加暗色衬底确保可读性"
    )

    try ObsidianWriter.saveEntry(e1, vaultDir: vaultDir, dataDir: dataDir)
    try ObsidianWriter.saveEntry(e2, vaultDir: vaultDir, dataDir: dataDir)

    let domainFile = vaultDir.appendingPathComponent("01-LLM与新模型.md")
    let mdBefore = try String(contentsOf: domainFile, encoding: .utf8)
    #expect(mdBefore.contains("核心概念精讲（费曼拆解）"))
    #expect(mdBefore.contains("像做长除法时保留草稿纸上的中间商"))
    #expect(mdBefore.contains("> [!question]- 为什么不缓存 Q 矩阵？"))
    #expect(mdBefore.contains("延伸思考与下一步"))

    // DedupeStore integration: commit then delete by entry ID
    let dedupe = try DedupeStore(dbURL: dbURL)
    let key1 = try #require(URLCanonicalizer.canonicalKey(from: e1.url))
    #expect(await dedupe.beginIfNew(canonicalKey: key1) == true)
    await dedupe.markCommitted(canonicalKey: key1, kind: "url", entryID: e1.id)
    #expect(await dedupe.hasSeen(canonicalKey: key1) == true)

    // Delete e1 and verify removal from JSON, Markdown, and DedupeStore
    let removed = try ObsidianWriter.deleteEntry(id: e1.id, vaultDir: vaultDir, dataDir: dataDir)
    #expect(removed?.entry.id == e1.id)
    #expect(removed?.originalIndex == 1)
    await dedupe.deleteByEntryID(e1.id)
    #expect(await dedupe.hasSeen(canonicalKey: key1) == false)

    let afterDelete = ObsidianWriter.loadEntries(dataDir: dataDir)
    #expect(afterDelete.count == 1)
    #expect(afterDelete.first?.id == e2.id)
    let mdAfterDelete = try String(contentsOf: domainFile, encoding: .utf8)
    #expect(!mdAfterDelete.contains("注意力机制与 KV Cache 内存原理"))

    // Undo restore e1 at originalIndex
    try ObsidianWriter.restoreEntry(e1, at: removed!.originalIndex, vaultDir: vaultDir, dataDir: dataDir)
    let afterRestore = ObsidianWriter.loadEntries(dataDir: dataDir)
    #expect(afterRestore.count == 2)
    #expect(afterRestore[1].id == e1.id)
    let mdAfterRestore = try String(contentsOf: domainFile, encoding: .utf8)
    #expect(mdAfterRestore.contains("注意力机制与 KV Cache 内存原理"))

    // Replace e1 with updated summary
    let e1Updated = KnowledgeEntry(
        id: e1.id,
        title: "KV Cache 与 PagedAttention 进阶",
        source: e1.source,
        url: e1.url,
        domain: e1.domain,
        oneLineEssence: "新版总结：结合 PagedAttention 实现零碎片显存管理"
    )
    try ObsidianWriter.replaceEntry(e1Updated, replacingOldID: e1.id, vaultDir: vaultDir, dataDir: dataDir)
    let afterReplace = ObsidianWriter.loadEntries(dataDir: dataDir)
    #expect(afterReplace.count == 2)
    #expect(afterReplace[1].title == "KV Cache 与 PagedAttention 进阶")
    let mdAfterReplace = try String(contentsOf: domainFile, encoding: .utf8)
    #expect(mdAfterReplace.contains("KV Cache 与 PagedAttention 进阶"))
    #expect(!mdAfterReplace.contains("注意力机制与 KV Cache 内存原理"))
}

@Test("SurfaceSpec enforces pure black on collapsed notch, locks colorScheme per preset, and handles accessibility fallbacks")
func testSurfaceSpecResolution() {
    // Collapsed MacBook notch is ALWAYS pure black even in liquidGlass mode
    let collapsedNotch = SurfaceSpec.resolve(
        style: .liquidGlass,
        preset: .frosted,
        intensity: 0.25,
        isExpanded: false,
        hasNotch: true,
        reduceTransparency: false,
        increasedContrast: false
    )
    #expect(collapsedNotch.isGlass == false)
    #expect(collapsedNotch.palette.scheme == .dark)

    // Expanded frosted locks .light scheme; clear enables text shadow
    let expandedFrosted = SurfaceSpec.resolve(
        style: .liquidGlass,
        preset: .frosted,
        intensity: 0.25,
        isExpanded: true,
        hasNotch: true,
        reduceTransparency: false,
        increasedContrast: false
    )
    #expect(expandedFrosted.isGlass == true)
    #expect(expandedFrosted.palette.scheme == .light)
    #expect(expandedFrosted.needsTextShadow == false)

    let expandedClear = SurfaceSpec.resolve(
        style: .liquidGlass,
        preset: .clear,
        intensity: 0.25,
        isExpanded: true,
        hasNotch: false,
        reduceTransparency: false,
        increasedContrast: false
    )
    #expect(expandedClear.isGlass == true)
    #expect(expandedClear.palette.scheme == .dark)
    #expect(expandedClear.needsTextShadow == true)

    // Reduce Transparency falls back to solid material
    let reduced = SurfaceSpec.resolve(
        style: .liquidGlass,
        preset: .regular,
        intensity: 0.25,
        isExpanded: true,
        hasNotch: true,
        reduceTransparency: true,
        increasedContrast: false
    )
    #expect(reduced.isGlass == false)

    // Increased Contrast boosts edgeWidth to 1.0
    let highContrast = SurfaceSpec.resolve(
        style: .liquidGlass,
        preset: .regular,
        intensity: 0.25,
        isExpanded: true,
        hasNotch: true,
        reduceTransparency: false,
        increasedContrast: true
    )
    #expect(highContrast.edgeWidth == 1.0)
}

@Test("Liquid glass 3-tier tone accurately maps intensities and drives specular/frosted surface specs")
func testLiquidGlassThreeTiers() {
    #expect(GlassToneTier.from(intensity: 0.10) == .clear)
    #expect(GlassToneTier.from(intensity: 0.50) == .regular)
    #expect(GlassToneTier.from(intensity: 0.85) == .tinted)

    let clearSpec = SurfaceSpec.resolve(
        style: .liquidGlass,
        preset: .regular,
        intensity: 0.15,
        isExpanded: true,
        hasNotch: false,
        reduceTransparency: false,
        increasedContrast: false
    )
    #expect(clearSpec.isGlass == true)
    #expect(clearSpec.needsTextShadow == true)

    let regularSpec = SurfaceSpec.resolve(
        style: .liquidGlass,
        preset: .regular,
        intensity: 0.50,
        isExpanded: true,
        hasNotch: false,
        reduceTransparency: false,
        increasedContrast: false
    )
    #expect(regularSpec.isGlass == true)
    #expect(regularSpec.needsTextShadow == false)

    let tintedSpec = SurfaceSpec.resolve(
        style: .liquidGlass,
        preset: .regular,
        intensity: 0.90,
        isExpanded: true,
        hasNotch: false,
        reduceTransparency: false,
        increasedContrast: false
    )
    #expect(tintedSpec.isGlass == true)
    #expect(tintedSpec.frostedDiffusion != .clear)
}

@Test("External display placements provide top-center, leading, trailing-safe, and drag-memory modes")
func testExternalDisplayPlacements() {
    #expect(ExternalDisplayPlacement.allCases.count == 4)
    #expect(ExternalDisplayPlacement.topCenter.rawValue == "topCenter")
    #expect(ExternalDisplayPlacement.topTrailingSafe.label.contains("避让"))
}

@Test("HUDHostingView accepts first mouse for full-screen responsiveness")
@MainActor
func testHUDHostingViewFirstMouse() {
    let view = HUDHostingView(rootView: Text("Test"))
    #expect(view.acceptsFirstMouse(for: nil) == true)
}
