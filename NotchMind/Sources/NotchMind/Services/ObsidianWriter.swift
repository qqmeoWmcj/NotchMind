import Foundation

public enum ObsidianWriter {
    public static let entriesMarker = "<!-- ENTRIES_START -->"
    public static let consoleFilename = "00-控制台与速览.md"

    public static func loadEntries(dataDir: URL) -> [KnowledgeEntry] {
        let path = dataDir.appendingPathComponent("entries.json")
        guard let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode([KnowledgeEntry].self, from: data)
        else { return [] }
        return decoded
    }

    @discardableResult
    public static func saveEntry(
        _ entry: KnowledgeEntry,
        vaultDir: URL,
        dataDir: URL
    ) throws -> KnowledgeEntry {
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        var existing = loadEntries(dataDir: dataDir)
        let incomingKey = URLCanonicalizer.canonicalKey(from: entry.url)
        if let dup = existing.first(where: { item in
            if item.id == entry.id { return true }
            if let key = incomingKey, let itemKey = URLCanonicalizer.canonicalKey(from: item.url) {
                return key == itemKey
            }
            return false
        }) {
            return dup
        }

        let domain = KnowledgeDomain.normalize(entry.domain)
        let domainFile = vaultDir.appendingPathComponent(domain.filename)
        try appendToDomainFile(entry: entry, domain: domain, fileURL: domainFile)

        existing.insert(entry, at: 0)
        try writeJSONAtomic(existing, to: dataDir.appendingPathComponent("entries.json"))
        try updateConsole(entries: existing, vaultDir: vaultDir)
        return entry
    }

    /// Deletes an entry by ID from entries.json, its domain Markdown file, and refreshes the console.
    /// Returns the deleted entry and its original index so callers can support Undo.
    @discardableResult
    public static func deleteEntry(
        id: String,
        vaultDir: URL,
        dataDir: URL
    ) throws -> (entry: KnowledgeEntry, originalIndex: Int)? {
        var existing = loadEntries(dataDir: dataDir)
        guard let idx = existing.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let removed = existing.remove(at: idx)
        try writeJSONAtomic(existing, to: dataDir.appendingPathComponent("entries.json"))

        let domain = KnowledgeDomain.normalize(removed.domain)
        let domainFile = vaultDir.appendingPathComponent(domain.filename)
        try removeEntryBlock(entry: removed, from: domainFile)
        try updateConsole(entries: existing, vaultDir: vaultDir)
        return (removed, idx)
    }

    /// Restores a previously deleted entry back into entries.json, its domain Markdown file, and refreshes the console.
    public static func restoreEntry(
        _ entry: KnowledgeEntry,
        at index: Int,
        vaultDir: URL,
        dataDir: URL
    ) throws {
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        var existing = loadEntries(dataDir: dataDir)
        if existing.contains(where: { $0.id == entry.id }) {
            return
        }
        let safeIndex = max(0, min(index, existing.count))
        existing.insert(entry, at: safeIndex)

        let domain = KnowledgeDomain.normalize(entry.domain)
        let domainFile = vaultDir.appendingPathComponent(domain.filename)
        try appendToDomainFile(entry: entry, domain: domain, fileURL: domainFile)
        try writeJSONAtomic(existing, to: dataDir.appendingPathComponent("entries.json"))
        try updateConsole(entries: existing, vaultDir: vaultDir)
    }

    /// Replaces an existing entry (matched by id or canonical URL) with a newly regenerated version.
    @discardableResult
    public static func replaceEntry(
        _ entry: KnowledgeEntry,
        replacingOldID oldID: String,
        vaultDir: URL,
        dataDir: URL
    ) throws -> KnowledgeEntry {
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        var existing = loadEntries(dataDir: dataDir)
        var insertIndex = 0
        if let idx = existing.firstIndex(where: { $0.id == oldID || $0.id == entry.id }) {
            let old = existing.remove(at: idx)
            insertIndex = idx
            let oldDomain = KnowledgeDomain.normalize(old.domain)
            let oldFile = vaultDir.appendingPathComponent(oldDomain.filename)
            try removeEntryBlock(entry: old, from: oldFile)
        }

        let domain = KnowledgeDomain.normalize(entry.domain)
        let domainFile = vaultDir.appendingPathComponent(domain.filename)
        try appendToDomainFile(entry: entry, domain: domain, fileURL: domainFile)

        existing.insert(entry, at: min(insertIndex, existing.count))
        try writeJSONAtomic(existing, to: dataDir.appendingPathComponent("entries.json"))
        try updateConsole(entries: existing, vaultDir: vaultDir)
        return entry
    }

    private static func removeEntryBlock(entry: KnowledgeEntry, from fileURL: URL) throws {
        guard var content = try? String(contentsOf: fileURL, encoding: .utf8), !content.isEmpty else {
            return
        }
        let startMarker = "<!-- entry_start:\(entry.id) -->"
        let endMarker = "<!-- entry_end:\(entry.id) -->"

        if let startRange = content.range(of: startMarker),
           let endRange = content.range(of: endMarker, range: startRange.upperBound..<content.endIndex)
        {
            var lower = startRange.lowerBound
            var upper = endRange.upperBound
            while lower > content.startIndex, content[content.index(before: lower)] == "\n" {
                lower = content.index(before: lower)
            }
            while upper < content.endIndex, content[upper] == "\n" {
                upper = content.index(after: upper)
            }
            content.replaceSubrange(lower..<upper, with: "\n\n")
            try writeTextAtomic(content, to: fileURL)
            return
        }

        // Legacy fallback for entries written before markers existed
        let heading = "### \(entry.title)\n"
        if let hRange = content.range(of: heading) {
            let searchAfter = hRange.upperBound..<content.endIndex
            if let sepRange = content.range(of: "\n---\n", range: searchAfter) {
                content.removeSubrange(hRange.lowerBound..<sepRange.upperBound)
                try writeTextAtomic(content, to: fileURL)
            }
        }
    }

    private static func appendToDomainFile(
        entry: KnowledgeEntry,
        domain: KnowledgeDomain,
        fileURL: URL
    ) throws {
        var content: String
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8), !existing.isEmpty {
            content = existing
        } else {
            content = """
            ---
            domain: \(domain.rawValue)
            type: domain-log
            ---

            # \(domain.rawValue)

            \(entriesMarker)

            """
        }

        let block = renderEntryMarkdown(entry)
        if let range = content.range(of: entriesMarker) {
            let insertPoint = range.upperBound
            content.insert(contentsOf: "\n\n\(block)\n", at: insertPoint)
        } else {
            content.append("\n\n\(block)\n")
        }
        try writeTextAtomic(content, to: fileURL)
    }

    private static func renderEntryMarkdown(_ entry: KnowledgeEntry) -> String {
        var lines: [String] = [
            "<!-- entry_start:\(entry.id) -->",
            "### \(entry.title)",
            "- **时间**：\(entry.createdAt) | **来源**：\(entry.source) | **层级**：\(entry.ladderLevel)",
        ]
        if let goal = entry.focusGoal, !goal.isEmpty {
            lines.append("- **学习目标**：\(goal)")
        }
        if !entry.url.isEmpty {
            lines.append("- **原链**：\(entry.url)")
        }
        lines.append("")
        lines.append("> \(entry.oneLineEssence)")
        if !entry.prerequisites.isEmpty {
            lines.append("")
            lines.append("**前置知识与适用场景**")
            for pre in entry.prerequisites {
                lines.append("- \(pre)")
            }
        }
        if !entry.conceptBreakdown.isEmpty {
            lines.append("")
            lines.append("**核心概念精讲（费曼拆解）**")
            for item in entry.conceptBreakdown {
                var line = "- **\(item.term)**：\(item.explanation)"
                if let analogy = item.analogy, !analogy.isEmpty {
                    line += "（类比：\(analogy)）"
                }
                lines.append(line)
            }
        }
        if !entry.keyPoints.isEmpty {
            lines.append("")
            lines.append("**核心知识点与参数**")
            for pt in entry.keyPoints {
                lines.append("- \(pt)")
            }
        }
        if !entry.actionableSteps.isEmpty {
            lines.append("")
            lines.append("**可落地实操步骤**")
            for (idx, step) in entry.actionableSteps.enumerated() {
                lines.append("\(idx + 1). \(step)")
            }
        }
        if !entry.projectOptimizations.isEmpty {
            lines.append("")
            lines.append("**反哺项目可优化手段**")
            for opt in entry.projectOptimizations {
                lines.append("- [ ] \(opt)")
            }
        }
        if !entry.pitfalls.isEmpty {
            lines.append("")
            lines.append("**避坑与边界**")
            for pit in entry.pitfalls {
                lines.append("- ⚠️ \(pit)")
            }
        }
        if !entry.selfCheckQA.isEmpty {
            lines.append("")
            lines.append("**主动回忆自测（点击展开答案）**")
            for qa in entry.selfCheckQA {
                lines.append("> [!question]- \(qa.question)")
                lines.append("> \(qa.answer)")
            }
        }
        if !entry.copyableSnippets.isEmpty {
            lines.append("")
            lines.append("**可复用片段**")
            for sn in entry.copyableSnippets {
                lines.append("```text\n\(sn)\n```")
            }
        }
        if !entry.furtherExploration.isEmpty {
            lines.append("")
            lines.append("**延伸思考与下一步**")
            for next in entry.furtherExploration {
                lines.append("- \(next)")
            }
        }
        lines.append("")
        lines.append("---")
        lines.append("<!-- entry_end:\(entry.id) -->")
        return lines.joined(separator: "\n")
    }

    /// Appends actionable project optimization items from a KnowledgeEntry into a project feedback Markdown file.
    /// Returns the URL of the written file.
    @discardableResult
    public static func appendProjectFeedback(
        entry: KnowledgeEntry,
        feedbackFileURL: URL
    ) throws -> URL {
        let dir = feedbackFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var content: String
        if let existing = try? String(contentsOf: feedbackFileURL, encoding: .utf8), !existing.isEmpty {
            content = existing
        } else {
            content = """
            ---
            type: project-feedback
            generated_by: NotchMind
            ---

            # 项目反哺与优化清单

            \(entriesMarker)

            """
        }

        let feedbackMarker = "<!-- feedback_id:\(entry.id) -->"
        if content.contains(feedbackMarker) {
            return feedbackFileURL
        }

        var blockLines: [String] = [
            feedbackMarker,
            "### [\(entry.createdAt)] \(entry.title)",
        ]
        if let goal = entry.focusGoal, !goal.isEmpty {
            blockLines.append("- **关联目标**：\(goal)")
        }
        if !entry.url.isEmpty {
            blockLines.append("- **参考来源**：\(entry.url)")
        }
        blockLines.append("")
        blockLines.append("> \(entry.oneLineEssence)")

        let optimizations = entry.projectOptimizations.isEmpty ? entry.actionableSteps : entry.projectOptimizations
        if !optimizations.isEmpty {
            blockLines.append("")
            blockLines.append("**可执行优化项**")
            for item in optimizations {
                blockLines.append("- [ ] \(item)")
            }
        }
        if !entry.pitfalls.isEmpty {
            blockLines.append("")
            blockLines.append("**注意事项**")
            for pit in entry.pitfalls {
                blockLines.append("- \(pit)")
            }
        }
        blockLines.append("")
        blockLines.append("---")
        let block = blockLines.joined(separator: "\n")

        if let range = content.range(of: entriesMarker) {
            content.insert(contentsOf: "\n\n\(block)\n", at: range.upperBound)
        } else {
            content.append("\n\n\(block)\n")
        }
        try writeTextAtomic(content, to: feedbackFileURL)
        return feedbackFileURL
    }

    private static func updateConsole(entries: [KnowledgeEntry], vaultDir: URL) throws {
        let recent = entries.prefix(15)
        var rows: [String] = [
            "---",
            "type: console",
            "updated_at: \(KnowledgeEntry.nowTimestamp())",
            "---",
            "",
            "# 控制台与速览",
            "",
            "## 最新捕获速览",
            "",
            "| 时间 | 领域 | 标题 | 一句话精华 |",
            "|---|---|---|---|",
        ]
        for e in recent {
            let safeTitle = e.title.replacingOccurrences(of: "|", with: "\\|")
            let safeEssence = e.oneLineEssence.replacingOccurrences(of: "|", with: "\\|")
            rows.append("| \(e.createdAt) | [[\(e.domain)]] | \(safeTitle) | \(safeEssence) |")
        }
        rows.append("")
        try writeTextAtomic(rows.joined(separator: "\n"), to: vaultDir.appendingPathComponent(consoleFilename))
    }

    private static func writeJSONAtomic<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    private static func writeTextAtomic(_ text: String, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try text.write(to: tmp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}
