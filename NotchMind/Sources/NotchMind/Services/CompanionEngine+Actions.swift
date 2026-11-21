import AppKit
import Foundation

extension CompanionEngine {

    // MARK: - Blender Script Generation & Copy

    public func copyBlenderScript(_ entry: KnowledgeEntry) {
        let script = BlenderScriptGenerator.getOrGenerateScript(for: entry)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(script, forType: .string)
        lastCopiedBlenderScriptID = entry.id

        // If this entry did not have a saved script, persist the synthesized script
        if entry.blenderScript == nil || entry.blenderScript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            var updated = entry
            updated.blenderScript = script
            _ = try? ObsidianWriter.replaceEntry(
                updated,
                replacingOldID: entry.id,
                vaultDir: settings.vaultURL,
                dataDir: settings.dataURL
            )
            refreshEntries()
        }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            if self?.lastCopiedBlenderScriptID == entry.id {
                self?.lastCopiedBlenderScriptID = nil
            }
        }
    }

    // MARK: - Skill Hub & Copy Actions

    public func saveToSkillHub(_ entry: KnowledgeEntry) {
        do {
            try ObsidianWriter.saveSkillCard(entry: entry, vaultDir: settings.vaultURL)
            lastSavedSkillHubID = entry.id
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.8))
                if self?.lastSavedSkillHubID == entry.id {
                    self?.lastSavedSkillHubID = nil
                }
            }
        } catch {
            status = .error(message: "收录到技能库失败：\(error.localizedDescription)")
        }
    }

    public func copyBestPayload(_ entry: KnowledgeEntry) {
        let text = entry.bestCopyText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastCopiedID = entry.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            if self?.lastCopiedID == entry.id {
                self?.lastCopiedID = nil
            }
        }
    }

    public func openTreasureLink(_ link: TreasureLink) {
        guard let url = URL(string: link.url), url.scheme == "http" || url.scheme == "https" else {
            status = .error(message: "无效的外部链接地址")
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func copyEssence(_ entry: KnowledgeEntry) {
        let text = entry.copyableSnippets.first ?? entry.oneLineEssence
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastCopiedID = entry.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            if self?.lastCopiedID == entry.id {
                self?.lastCopiedID = nil
            }
        }
    }

    public func copyActionRecipe(_ entry: KnowledgeEntry) {
        var lines: [String] = ["### 实操与优化任务清单: \(entry.title)"]
        if !entry.projectOptimizations.isEmpty {
            lines.append("\n#### 针对项目优化建议")
            for opt in entry.projectOptimizations {
                lines.append("- [ ] 建议: \(opt)")
            }
        }
        if !entry.actionableSteps.isEmpty {
            lines.append("\n#### 实操执行步骤")
            for (idx, step) in entry.actionableSteps.enumerated() {
                lines.append("- [ ] 步骤 \(idx + 1): \(step)")
            }
        }
        let full = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
        lastCopiedID = entry.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            if self?.lastCopiedID == entry.id {
                self?.lastCopiedID = nil
            }
        }
    }

    // MARK: - Project Feedback Export

    public func exportFeedbackToProject(_ entry: KnowledgeEntry) {
        let customPath = settings.projectFeedbackPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetURL: URL
        if customPath.isEmpty {
            targetURL = settings.vaultURL.appendingPathComponent("05-项目孵化池").appendingPathComponent("99-项目反哺清单.md")
        } else {
            let expanded = (customPath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                targetURL = url.appendingPathComponent("learning-feedback.md")
            } else if url.pathExtension.isEmpty {
                targetURL = url.appendingPathComponent("learning-feedback.md")
            } else {
                targetURL = url
            }
        }
        do {
            try ObsidianWriter.appendProjectFeedback(entry: entry, feedbackFileURL: targetURL)
            lastFeedbackExportedID = entry.id
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.0))
                if self?.lastFeedbackExportedID == entry.id {
                    self?.lastFeedbackExportedID = nil
                }
            }
        } catch {
            status = .error(message: "写入反哺文档失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Obsidian & Re-Summarize

    public func openInObsidian(_ entry: KnowledgeEntry? = nil) {
        let fileURL: URL
        if let entry {
            let domain = KnowledgeDomain.normalize(entry.domain)
            fileURL = settings.vaultURL.appendingPathComponent(domain.filename)
        } else {
            fileURL = settings.vaultURL.appendingPathComponent(ObsidianWriter.consoleFilename)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.open(fileURL)
        } else {
            NSWorkspace.shared.open(settings.vaultURL)
        }
    }

    public func resummarizeEntry(_ entry: KnowledgeEntry) {
        guard URLCanonicalizer.isSupportedWebURL(entry.url) else {
            status = .error(message: "该条目无有效公网链接，无法重新深拆")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let prevStatus = self.status
            self.status = .analyzing(label: "重新深拆")
            do {
                let fetched = try await BilibiliFetcher.fetch(urlString: entry.url)
                let updated = try await GeminiClient.extractKnowledge(
                    apiKey: self.settings.apiKey,
                    model: self.settings.modelName,
                    source: fetched.source,
                    titleHint: fetched.title,
                    url: fetched.url,
                    textContent: fetched.content,
                    focusGoal: self.settings.currentFocusGoal
                )
                let saved = try ObsidianWriter.replaceEntry(
                    updated,
                    replacingOldID: entry.id,
                    vaultDir: self.settings.vaultURL,
                    dataDir: self.settings.dataURL
                )
                self.refreshEntries()
                self.showUndoBanner(.replaced(previousEntry: entry, currentID: saved.id))
                self.status = self.activeTarget.map { .watching(target: $0.matchedSite) } ?? prevStatus
            } catch {
                self.status = .error(message: "重新深拆失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Delete & Undo

    public func deleteEntry(_ entry: KnowledgeEntry) {
        do {
            guard let removed = try ObsidianWriter.deleteEntry(
                id: entry.id,
                vaultDir: settings.vaultURL,
                dataDir: settings.dataURL
            ) else { return }
            let canonicalKey = URLCanonicalizer.canonicalKey(from: entry.url)
            Task { [weak self] in
                await self?.dedupe?.deleteByEntryID(entry.id)
                if let key = canonicalKey {
                    await self?.dedupe?.deleteByCanonicalKey(key)
                }
            }
            refreshEntries()
            showUndoBanner(.deleted(entry: removed.entry, originalIndex: removed.originalIndex))
        } catch {
            status = .error(message: "删除失败：\(error.localizedDescription)")
        }
    }

    public func undoLastAction() {
        guard let action = undoBanner else { return }
        undoDismissTask?.cancel()
        undoDismissTask = nil
        undoCountdownStartedAt = nil
        undoBanner = nil

        do {
            let restoredID: String
            switch action {
            case .deleted(let entry, let originalIndex):
                try ObsidianWriter.restoreEntry(
                    entry,
                    at: originalIndex,
                    vaultDir: settings.vaultURL,
                    dataDir: settings.dataURL
                )
                restoredID = entry.id
                if let key = URLCanonicalizer.canonicalKey(from: entry.url) {
                    Task { [weak self] in
                        await self?.dedupe?.markCommitted(canonicalKey: key, kind: "url", entryID: entry.id)
                    }
                }
            case .replaced(let previousEntry, let currentID):
                try ObsidianWriter.replaceEntry(
                    previousEntry,
                    replacingOldID: currentID,
                    vaultDir: settings.vaultURL,
                    dataDir: settings.dataURL
                )
                restoredID = previousEntry.id
            }
            refreshEntries()
            lastRestoredEntryID = restoredID
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(750))
                if self?.lastRestoredEntryID == restoredID {
                    self?.lastRestoredEntryID = nil
                }
            }
        } catch {
            status = .error(message: "撤回失败：\(error.localizedDescription)")
        }
    }

    public func dismissUndoBanner() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        undoCountdownStartedAt = nil
        undoBanner = nil
    }

    public func pauseUndoCountdown() {
        guard undoBanner != nil, let startedAt = undoCountdownStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        undoRemainingSeconds = max(0.5, undoRemainingSeconds - elapsed)
        undoCountdownStartedAt = nil
        undoDismissTask?.cancel()
        undoDismissTask = nil
    }

    public func resumeUndoCountdown() {
        guard undoBanner != nil, undoCountdownStartedAt == nil else { return }
        scheduleUndoDismiss(after: undoRemainingSeconds)
    }

    public func showUndoBanner(_ action: UndoAction) {
        undoDismissTask?.cancel()
        undoBanner = action
        undoRemainingSeconds = 8.0
        scheduleUndoDismiss(after: 8.0)
    }

    public func scheduleUndoDismiss(after seconds: TimeInterval) {
        undoDismissTask?.cancel()
        undoCountdownStartedAt = Date()
        undoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled {
                self?.undoBanner = nil
                self?.undoCountdownStartedAt = nil
            }
        }
    }
}
