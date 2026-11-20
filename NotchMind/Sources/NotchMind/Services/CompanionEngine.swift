import AppKit
import Combine
import CryptoKit
import Foundation

public enum UndoAction: Equatable, Sendable {
    case deleted(entry: KnowledgeEntry, originalIndex: Int)
    case replaced(previousEntry: KnowledgeEntry, currentID: String)

    public var label: String {
        switch self {
        case .deleted(let entry, _):
            return "已删除「\(entry.title)」"
        case .replaced(let prev, _):
            return "已重拆「\(prev.title)」"
        }
    }
}

@MainActor
public final class CompanionEngine: ObservableObject {
    @Published public var status: CompanionStatus = .idle
    @Published public var activeTarget: TargetWindow?
    @Published public var recentEntries: [KnowledgeEntry] = []
    @Published public var manualLinkInput: String = ""
    @Published public var searchQuery: String = ""
    @Published public var lastCopiedID: String?
    @Published public var lastFeedbackExportedID: String?
    @Published public var captureCountToday: Int = 0
    @Published public var undoBanner: UndoAction?
    @Published public var lastRestoredEntryID: String?
    @Published public var isHUDForceExpanded: Bool = false

    public let settings: SettingsStore
    private var dedupe: DedupeStore?
    private var watchTimer: Timer?
    private var undoDismissTask: Task<Void, Never>?
    private var undoRemainingSeconds: TimeInterval = 8.0
    private var undoCountdownStartedAt: Date?
    private var lastAutoCaptureTime: Date = .distantPast
    private var clipboardMonitor: ClipboardMonitor?
    private let hotkeyManager = HotkeyManager()

    public var filteredEntries: [KnowledgeEntry] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return recentEntries }
        return recentEntries.filter { entry in
            entry.title.lowercased().contains(q)
                || entry.oneLineEssence.lowercased().contains(q)
                || entry.domain.lowercased().contains(q)
                || (entry.focusGoal?.lowercased().contains(q) ?? false)
                || entry.conceptBreakdown.contains { $0.term.lowercased().contains(q) }
                || entry.keyPoints.contains { $0.lowercased().contains(q) }
        }
    }

    public init(settings: SettingsStore = .shared) {
        self.settings = settings
        let dbURL = settings.dataURL.appendingPathComponent("notchmind.db")
        self.dedupe = try? DedupeStore(dbURL: dbURL)
        self.recentEntries = ObsidianWriter.loadEntries(dataDir: settings.dataURL)
        self.captureCountToday = Self.countToday(recentEntries)
    }

    public func start() {
        refreshEntries()
        hotkeyManager.registerShortcuts(
            onCapture: { [weak self] in
                self?.triggerManualCapture()
            },
            onToggle: { [weak self] in
                self?.toggleHUDExpansion()
            }
        )
        clipboardMonitor = ClipboardMonitor { [weak self] url in
            guard let self, self.settings.clipboardWatchEnabled else { return }
            self.submitLink(url, isAutoClipboard: true)
        }
        clipboardMonitor?.start()
        startWatchLoop()
    }

    public func stop() {
        watchTimer?.invalidate()
        watchTimer = nil
        clipboardMonitor?.stop()
        hotkeyManager.unregister()
    }

    public func refreshEntries() {
        recentEntries = ObsidianWriter.loadEntries(dataDir: settings.dataURL)
        captureCountToday = Self.countToday(recentEntries)
    }

    public func setMonitoringMode(_ mode: MonitoringMode) {
        settings.monitoringMode = mode
        if mode == .manual {
            activeTarget = nil
            status = .idle
        }
    }

    public func toggleCompanion() {
        if settings.monitoringMode == .manual {
            let next: MonitoringMode = settings.focusKeywords.isEmpty ? .continuous : .focused
            setMonitoringMode(next)
        } else {
            setMonitoringMode(.manual)
        }
    }

    public func triggerManualCapture() {
        Task { [weak self] in
            guard let self else { return }
            guard let target = await WindowMonitor.detectManualForegroundWindow() else {
                self.status = .error(message: "未检测到可抓取的前台窗口")
                return
            }
            await self.captureWindow(target, manual: true)
        }
    }

    public func submitManualLink() {
        let trimmed = manualLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        manualLinkInput = ""
        submitLink(trimmed, isAutoClipboard: false)
    }

    public func submitLink(_ rawURL: String, isAutoClipboard: Bool) {
        guard URLCanonicalizer.isSupportedWebURL(rawURL) else {
            if !isAutoClipboard {
                status = .error(message: "仅支持公网 http/https 链接")
            }
            return
        }
        guard let canonicalKey = URLCanonicalizer.canonicalKey(from: rawURL) else { return }

        Task { [weak self] in
            guard let self else { return }
            if let dedupe = self.dedupe {
                let acquired = await dedupe.beginIfNew(canonicalKey: canonicalKey)
                guard acquired else {
                    if !isAutoClipboard {
                        self.status = .paused(reason: "已收录，跳过重复")
                    }
                    return
                }
            }

            let prevStatus = self.status
            self.status = .analyzing(label: "链接精拆")
            do {
                let fetched = try await BilibiliFetcher.fetch(urlString: rawURL)
                let entry = try await GeminiClient.extractKnowledge(
                    apiKey: self.settings.apiKey,
                    model: self.settings.modelName,
                    source: fetched.source,
                    titleHint: fetched.title,
                    url: fetched.url,
                    textContent: fetched.content,
                    focusGoal: self.settings.currentFocusGoal
                )
                let saved = try ObsidianWriter.saveEntry(
                    entry,
                    vaultDir: self.settings.vaultURL,
                    dataDir: self.settings.dataURL
                )
                await self.dedupe?.markCommitted(canonicalKey: canonicalKey, kind: "url", entryID: saved.id)
                self.refreshEntries()
                self.status = self.activeTarget.map { .watching(target: $0.matchedSite) } ?? .idle
            } catch {
                await self.dedupe?.releaseInFlight(canonicalKey: canonicalKey)
                self.status = .error(message: error.localizedDescription)
                if isAutoClipboard {
                    try? await Task.sleep(for: .seconds(4))
                    if self.status.isError { self.status = prevStatus }
                }
            }
        }
    }

    public func toggleHUDExpansion() {
        isHUDForceExpanded.toggle()
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

    private func showUndoBanner(_ action: UndoAction) {
        undoDismissTask?.cancel()
        undoBanner = action
        undoRemainingSeconds = 8.0
        scheduleUndoDismiss(after: 8.0)
    }

    private func scheduleUndoDismiss(after seconds: TimeInterval) {
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

    private func startWatchLoop() {
        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tick()
            }
        }
    }

    private func tick() async {
        let mode = settings.monitoringMode
        guard mode != .manual else {
            if case .watching = status { status = .idle }
            activeTarget = nil
            return
        }
        if case .analyzing = status { return }

        let target = await WindowMonitor.detectWhitelistedForegroundWindow(
            allowedSiteKeywords: settings.allowedSiteKeywords,
            monitoringMode: mode,
            focusKeywords: settings.focusKeywords
        )
        activeTarget = target

        guard let target else {
            if !status.isError { status = .idle }
            return
        }

        status = .watching(target: target.matchedSite)

        let elapsed = Date().timeIntervalSince(lastAutoCaptureTime)
        if elapsed >= settings.captureIntervalSeconds {
            lastAutoCaptureTime = Date()
            await captureWindow(target, manual: false)
        }
    }

    private func captureWindow(_ target: TargetWindow, manual: Bool) async {
        // If a BVID is directly present in window title, prefer clean metadata extraction first
        if let bvid = target.bvid {
            let bvidKey = "bilibili:\(bvid)"
            if let dedupe, await !dedupe.hasSeen(canonicalKey: bvidKey) {
                submitLink("https://www.bilibili.com/video/\(bvid)", isAutoClipboard: !manual)
                return
            }
        }

        status = .analyzing(label: target.matchedSite)
        var acquiredFrameKey: String?
        do {
            let jpeg = try await WindowCapturer.captureWindowJPEG(windowID: target.windowID)
            let frameHash = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
            let frameKey = "frame:\(frameHash)"

            if let dedupe {
                let acquired = await dedupe.beginIfNew(canonicalKey: frameKey)
                guard acquired else {
                    status = activeTarget.map { .watching(target: $0.matchedSite) } ?? .idle
                    return
                }
                acquiredFrameKey = frameKey
            }

            let sourceLabel = target.isPiliPlus ? "PiliPlus伴随同看" : "伴随同看(\(target.matchedSite))"
            let url = target.bvid.map { "https://www.bilibili.com/video/\($0)" } ?? ""
            let entry = try await GeminiClient.extractKnowledge(
                apiKey: settings.apiKey,
                model: settings.modelName,
                source: sourceLabel,
                titleHint: target.title,
                url: url,
                textContent: "当前前台窗口：\(target.appName) - \(target.title)。请深度提炼画面中的具体技法、参数、步骤，并结合学习目标给出可反哺项目的优化手段。",
                imageJPEG: jpeg,
                focusGoal: settings.currentFocusGoal
            )
            let saved = try ObsidianWriter.saveEntry(
                entry,
                vaultDir: settings.vaultURL,
                dataDir: settings.dataURL
            )
            await dedupe?.markCommitted(canonicalKey: frameKey, kind: "frame", entryID: saved.id)
            refreshEntries()
            status = activeTarget.map { .watching(target: $0.matchedSite) } ?? .idle
        } catch {
            if let key = acquiredFrameKey {
                await dedupe?.releaseInFlight(canonicalKey: key)
            }
            status = .error(message: error.localizedDescription)
        }
    }

    private static func countToday(_ entries: [KnowledgeEntry]) -> Int {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let prefix = fmt.string(from: Date())
        return entries.filter { $0.createdAt.hasPrefix(prefix) }.count
    }
}
