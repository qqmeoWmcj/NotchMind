import Foundation
import Testing
@testable import NotchMind

@Suite("Skill Vault & Payload Tests")
struct SkillVaultTests {

    @Test("KnowledgeEntry bestCopyText and displaySkillName prioritization")
    func testPriorities() {
        let entryWithPayload = KnowledgeEntry(
            title: "Fallback Title",
            source: "Twitter",
            url: "https://x.com/post/1",
            domain: "02-AI学习与教程",
            oneLineEssence: "Essence line",
            blenderScript: "import bpy; bpy.ops.mesh.primitive_cube_add()",
            skillName: "Cursor高级Rules",
            painPoint: "痛点说明",
            copyReadyPayloads: [
                CopyPayload(type: "prompt", label: "Prompt 模板", content: "You are an expert coder.")
            ]
        )

        #expect(entryWithPayload.displaySkillName == "Cursor高级Rules")
        #expect(entryWithPayload.bestCopyText == "You are an expert coder.")

        let entryFallback = KnowledgeEntry(
            title: "Only Title",
            source: "General",
            url: "https://example.com",
            domain: "01-LLM与新模型",
            oneLineEssence: "Essence text"
        )
        #expect(entryFallback.displaySkillName == "Only Title")
        #expect(entryFallback.bestCopyText == "Essence text")
    }

    @Test("ObsidianWriter saveSkillCard writes SK-*.md and action board ACT-*.md")
    func testSaveSkillCard() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vaultDir = tempDir.appendingPathComponent("vault")
        let dataDir = tempDir.appendingPathComponent("data")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = KnowledgeEntry(
            title: "Claude 3.7 Prompt 模式",
            source: "推特精选",
            url: "https://x.com/someone/status/888",
            domain: "02-AI学习与教程",
            matchedProject: "NotchMind",
            oneLineEssence: "精准提示词模式可以让模型少走弯路",
            actionableSteps: [
                "复制上述 Prompt 到常用模版",
                "在客户端中设定为预设指令"
            ],
            projectOptimizations: [
                "为 NotchMind 项目注入此 Prompt 规则"
            ],
            skillName: "Claude37Prompt工程",
            painPoint: "模型经常回答不切题或遗漏约束",
            copyReadyPayloads: [
                CopyPayload(type: "prompt", label: "核心Prompt", content: "Focus on zero-overhead design.", sourceNote: "原帖")
            ],
            treasureLinks: [
                TreasureLink(title: "PromptLib", url: "https://promptlib.com", why: "社区开源提示词库")
            ],
            gotchas: [
                "避免在 System Prompt 里写入冲突的否定句"
            ],
            sourceType: "x_post"
        )

        let saved = try ObsidianWriter.saveEntry(entry, vaultDir: vaultDir, dataDir: dataDir)
        #expect(saved.id == entry.id)

        // Verify SK-*.md was created in 01-精选技能库
        let skillFile = vaultDir.appendingPathComponent("01-精选技能库").appendingPathComponent("SK-Claude37Prompt工程.md")
        #expect(FileManager.default.fileExists(atPath: skillFile.path))

        let content = try String(contentsOf: skillFile, encoding: .utf8)
        #expect(content.contains("# Claude37Prompt工程"))
        #expect(content.contains("💡 **解决痛点**：模型经常回答不切题或遗漏约束"))
        #expect(content.contains("Focus on zero-overhead design."))
        #expect(content.contains("https://promptlib.com"))
        #expect(content.contains("避免在 System Prompt 里写入冲突的否定句"))

        // Verify ACT-*.md was created in 03-项目反哺任务池
        let actFile = vaultDir.appendingPathComponent("03-项目反哺任务池").appendingPathComponent("ACT-NotchMind.md")
        #expect(FileManager.default.fileExists(atPath: actFile.path))
        let actContent = try String(contentsOf: actFile, encoding: .utf8)
        #expect(actContent.contains("为 NotchMind 项目注入此 Prompt 规则"))
    }
}
