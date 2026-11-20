import AppKit
import Foundation
import Testing
@testable import NotchMind

@Test("KnowledgeEntry accurately detects Blender and 3D relevance")
func testKnowledgeEntryBlenderRelevance() {
    let entry3D = KnowledgeEntry(
        title: "Blender 4.2 角色材质与 EEVEE Next 实战",
        source: "B站视频",
        url: "https://www.bilibili.com/video/BV1yy4y1z7xx",
        domain: "03-AI创作与3D工具",
        oneLineEssence: "解析 Principled BSDF 与次表面散射参数设置"
    )
    #expect(entry3D.isBlenderRelated == true)

    let entryKeyword = KnowledgeEntry(
        title: "次世代模型拓扑与修改器优化技巧",
        source: "YouTube",
        url: "https://example.com/topology",
        domain: "02-AI学习与教程",
        oneLineEssence: "讲解 subsurf 与细分曲面在硬表面建模中的布线原则"
    )
    #expect(entryKeyword.isBlenderRelated == true)

    let entryLLM = KnowledgeEntry(
        title: "DeepSeek-V3 架构浅析与 MoE 路由原理",
        source: "技术报告",
        url: "https://example.com/deepseek",
        domain: "01-LLM与新模型",
        oneLineEssence: "分析 Multi-head Latent Attention 与无辅助损失负载均衡机制"
    )
    #expect(entryLLM.isBlenderRelated == false)
}

@Test("BlenderScriptGenerator produces executable bpy scripts for shaders, modifiers, and general 3D")
func testBlenderScriptGenerator() {
    // 1. Material / Shader entry
    let shaderEntry = KnowledgeEntry(
        title: "次表面散射皮肤材质调优",
        source: "Bilibili",
        url: "https://example.com/shader",
        domain: "03-AI创作与3D工具",
        oneLineEssence: "将 Subsurface Weight 设为 0.25 配合 Roughness 0.28 消除塑料感",
        keyPoints: ["Principled BSDF 参数联动"],
        actionableSteps: ["在材质节点中连接 Noise Texture 到粗糙度"],
        projectOptimizations: ["为本地主角模型赋予 PBR 次表面材质"]
    )

    let shaderScript = BlenderScriptGenerator.getOrGenerateScript(for: shaderEntry)
    #expect(shaderScript.contains("import bpy"))
    #expect(shaderScript.contains("def run_notchmind_recipe():"))
    #expect(shaderScript.contains("Principled BSDF"))
    #expect(shaderScript.contains("Subsurface Weight"))
    #expect(shaderScript.contains("0.25"))
    #expect(shaderScript.contains("Roughness"))
    #expect(shaderScript.contains("0.28"))
    #expect(shaderScript.contains("为本地主角模型赋予 PBR 次表面材质"))

    // 2. Modifier / Subdivision entry
    let modEntry = KnowledgeEntry(
        title: "硬表面倒角与 Subsurf 修改器工作流",
        source: "Bilibili",
        url: "https://example.com/mod",
        domain: "03-AI创作与3D工具",
        oneLineEssence: "通过 Bevel 与 Subsurf 组合实现平滑高光边缘"
    )

    let modScript = BlenderScriptGenerator.getOrGenerateScript(for: modEntry)
    #expect(modScript.contains("import bpy"))
    #expect(modScript.contains("obj.modifiers"))
    #expect(modScript.contains("Subdivision") || modScript.contains("Bevel"))

    // 3. Custom pre-extracted script takes priority
    var customEntry = shaderEntry
    customEntry.blenderScript = """
    import bpy
    # Custom Hand-crafted script
    print("Custom bpy execution")
    """
    let customOutput = BlenderScriptGenerator.getOrGenerateScript(for: customEntry)
    #expect(customOutput.contains("Custom Hand-crafted script"))
    #expect(!customOutput.contains("def run_notchmind_recipe():"))
}

@Test("ObsidianWriter preserves and renders blender_script in Markdown and feedback notes")
func testObsidianWriterWithBlenderScript() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("notchmind_blender_\(UUID().uuidString)")
    let vaultDir = tmpDir.appendingPathComponent("vault")
    let dataDir = tmpDir.appendingPathComponent("data")
    let feedbackFile = tmpDir.appendingPathComponent("feedback/learning-feedback.md")
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let scriptContent = """
    import bpy
    obj = bpy.context.active_object
    obj.location.z += 1.0
    """

    let entry = KnowledgeEntry(
        title: "Blender 物体位移与动画烘焙",
        source: "B站视频",
        url: "https://bilibili.com/video/BV1scriptTest",
        domain: "03-AI创作与3D工具",
        oneLineEssence: "用 Python 批量处理关键帧位移",
        blenderScript: scriptContent
    )

    try ObsidianWriter.saveEntry(entry, vaultDir: vaultDir, dataDir: dataDir)
    let domainMD = try String(contentsOf: vaultDir.appendingPathComponent("03-AI创作与3D工具.md"), encoding: .utf8)
    #expect(domainMD.contains("**Blender 实操脚本 (bpy)**"))
    #expect(domainMD.contains("obj.location.z += 1.0"))

    try ObsidianWriter.appendProjectFeedback(entry: entry, feedbackFileURL: feedbackFile)
    let fbMD = try String(contentsOf: feedbackFile, encoding: .utf8)
    #expect(fbMD.contains("**Blender 实操脚本 (bpy)**"))
    #expect(fbMD.contains("obj.location.z += 1.0"))
}

@Test("CompanionEngine copies Blender script to pasteboard with tactile feedback")
@MainActor
func testCompanionEngineCopyBlenderScript() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("notchmind_engine_\(UUID().uuidString)")
    let settings = SettingsStore()
    settings.vaultPath = tmpDir.appendingPathComponent("vault").path
    settings.dataPath = tmpDir.appendingPathComponent("data").path
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let engine = CompanionEngine(settings: settings)
    let entry = KnowledgeEntry(
        title: "几何节点程序化藤蔓生成",
        source: "Bilibili",
        url: "https://bilibili.com/video/BV1vineGen",
        domain: "03-AI创作与3D工具",
        oneLineEssence: "曲线转网格配合材质自发光节点",
        actionableSteps: ["添加曲线基本体", "设置 Curve to Mesh 节点"]
    )

    engine.copyBlenderScript(entry)
    #expect(engine.lastCopiedBlenderScriptID == entry.id)

    let copied = NSPasteboard.general.string(forType: .string) ?? ""
    #expect(copied.contains("import bpy"))
    #expect(copied.contains("几何节点程序化藤蔓生成"))
}
