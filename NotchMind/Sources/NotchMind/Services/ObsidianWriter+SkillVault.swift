import Foundation

extension ObsidianWriter {
    public static let skillsDirname = "01-精选技能库"
    public static let workflowsDirname = "02-即插即用工作流"
    public static let actionsDirname = "03-项目反哺任务池"

    public static func ensureSkillDirectories(vaultDir: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: vaultDir.appendingPathComponent(skillsDirname), withIntermediateDirectories: true)
        try fm.createDirectory(at: vaultDir.appendingPathComponent(workflowsDirname), withIntermediateDirectories: true)
        try fm.createDirectory(at: vaultDir.appendingPathComponent(actionsDirname), withIntermediateDirectories: true)
    }

    public static func safeFilename(_ name: String) -> String {
        let pattern = #"[\\/:*?"<>|\r\n]+"#
        var cleaned = name.replacingOccurrences(of: pattern, with: "-", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        if cleaned.count > 48 {
            cleaned = String(cleaned.prefix(48))
        }
        return cleaned.isEmpty ? "未命名技能" : cleaned
    }

    @discardableResult
    public static func saveSkillCard(
        entry: KnowledgeEntry,
        vaultDir: URL
    ) throws -> URL {
        try ensureSkillDirectories(vaultDir: vaultDir)
        let skillsDir = vaultDir.appendingPathComponent(skillsDirname)
        let filename = "SK-\(safeFilename(entry.displaySkillName)).md"
        let fileURL = skillsDir.appendingPathComponent(filename)
        let content = renderSkillCardMarkdown(entry)

        try writeTextAtomic(content, to: fileURL)

        if !entry.projectOptimizations.isEmpty {
            try syncProjectActionBoard(entry: entry, vaultDir: vaultDir)
        }
        return fileURL
    }

    public static func renderSkillCardMarkdown(_ entry: KnowledgeEntry) -> String {
        let displayName = entry.displaySkillName
        let pain = entry.painPoint ?? entry.oneLineEssence

        var lines: [String] = [
            "---",
            "id: \"\(entry.id)\"",
            "title: \"\(entry.title.replacingOccurrences(of: "\"", with: "\\\""))\"",
            "skill_name: \"\(displayName.replacingOccurrences(of: "\"", with: "\\\""))\"",
            "domain: \"\(entry.domain)\"",
            "source_type: \"\(entry.sourceType ?? "general")\"",
            "source: \"\(entry.source)\"",
            "created_at: \"\(entry.createdAt)\"",
            "type: \"skill-card\"",
            "---",
            "",
            "# \(displayName)",
            "",
            "> 💡 **解决痛点**：\(pain)",
            "",
            "- **出处来源**：\(entry.source)" + (entry.url.isEmpty ? "" : " · [原文链接](\(entry.url))"),
            "- **领域分类**：[[\(entry.domain)]] · **成熟度**：`\(entry.ladderLevel)`",
            "",
            "## 📋 即插即用载荷（点击代码块右上角直接拷贝）",
            "",
        ]

        if !entry.copyReadyPayloads.isEmpty {
            for (idx, p) in entry.copyReadyPayloads.enumerated() {
                let fence = codeFence(for: p.type)
                lines.append("### \(idx + 1). \(p.label) (`\(p.type)`)")
                if let note = p.sourceNote, !note.isEmpty {
                    lines.append("> 说明：\(note)\n")
                }
                lines.append("```\(fence)\n\(p.content)\n```\n")
            }
        } else if let script = entry.blenderScript, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("### Blender Python (bpy) 实操脚本")
            lines.append("```python\n\(script.trimmingCharacters(in: .whitespacesAndNewlines))\n```\n")
        } else if !entry.copyableSnippets.isEmpty {
            for snip in entry.copyableSnippets {
                lines.append("```text\n\(snip)\n```\n")
            }
        } else {
            lines.append("```markdown\n\(entry.oneLineEssence)\n```\n")
        }

        if !entry.treasureLinks.isEmpty {
            lines.append("## 🔗 宝藏工具与外链（从推文/评论区精选）\n")
            for link in entry.treasureLinks {
                var item = "- [\(link.title)](\(link.url))"
                if let why = link.why, !why.isEmpty {
                    item += " — \(why)"
                }
                lines.append(item)
            }
            lines.append("")
        }

        if !entry.gotchas.isEmpty {
            lines.append("## ⚠️ 避坑提醒（小白必看）\n")
            for g in entry.gotchas {
                lines.append("- ⚠️ \(g)")
            }
            lines.append("")
        } else if !entry.pitfalls.isEmpty {
            lines.append("## ⚠️ 避坑提醒（小白必看）\n")
            for pit in entry.pitfalls {
                lines.append("- ⚠️ \(pit)")
            }
            lines.append("")
        }

        if !entry.actionableSteps.isEmpty {
            lines.append("## 🛠️ 实操执行步骤\n")
            for (idx, step) in entry.actionableSteps.enumerated() {
                lines.append("\(idx + 1). \(step)")
            }
            lines.append("")
        }

        if !entry.projectOptimizations.isEmpty {
            let proj = entry.matchedProject ?? "通用待办"
            lines.append("## 🎯 反哺项目待办（[[\(proj)]]）\n")
            for opt in entry.projectOptimizations {
                lines.append("- [ ] \(opt)")
            }
            lines.append("")
        }

        lines.append("---\n*由 NotchMind AI 技能猎手自动提炼生成*\n")
        return lines.joined(separator: "\n")
    }

    public static func syncProjectActionBoard(
        entry: KnowledgeEntry,
        vaultDir: URL
    ) throws {
        try ensureSkillDirectories(vaultDir: vaultDir)
        let actionsDir = vaultDir.appendingPathComponent(actionsDirname)
        let projName = entry.matchedProject ?? "通用技能待办池"
        let filename = "ACT-\(safeFilename(projName)).md"
        let boardURL = actionsDir.appendingPathComponent(filename)

        let marker = "<!-- entry_id:\(entry.id) -->"
        var existing = (try? String(contentsOf: boardURL, encoding: .utf8)) ?? ""
        if existing.contains(marker) {
            return
        }

        if existing.isEmpty {
            existing = """
            ---
            type: action-board
            project: "\(projName)"
            ---

            # 🎯 \(projName) · 落地待办清单

            """
        }

        var taskLines: [String] = [
            marker,
            "### 来自技能：[[SK-\(safeFilename(entry.displaySkillName))]]",
            "- 解决痛点：\(entry.painPoint ?? entry.oneLineEssence)",
        ]
        for opt in entry.projectOptimizations {
            taskLines.append("- [ ] \(opt)")
        }
        taskLines.append("")

        let updated = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + taskLines.joined(separator: "\n") + "\n"
        try writeTextAtomic(updated, to: boardURL)
    }

    private static func codeFence(for payloadType: String) -> String {
        let low = payloadType.lowercased()
        if low.contains("python") || low.contains("bpy") || low.contains("script") {
            return "python"
        }
        if low.contains("bash") || low.contains("sh") || low.contains("command") {
            return "bash"
        }
        if low.contains("json") {
            return "json"
        }
        if low.contains("yaml") || low.contains("yml") {
            return "yaml"
        }
        return "markdown"
    }
}
