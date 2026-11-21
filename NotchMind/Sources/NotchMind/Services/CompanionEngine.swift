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
    @Published public var lastSavedSkillHubID: String?
    @Published public var lastCopiedBlenderScriptID: String?
    @Published public var captureCountToday: Int = 0
    @Published public var undoBanner: UndoAction?
    @Published public var lastRestoredEntryID: String?
    @Published public var isHUDForceExpanded: Bool = false
    @Published public var errorToastMessage: String?

    public let settings: SettingsStore
    var dedupe: DedupeStore?
    private var watchTimer: Timer?
    var undoDismissTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?
    var undoRemainingSeconds: TimeInterval = 8.0
    var undoCountdownStartedAt: Date?
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
                self.reportError(error.localizedDescription, autoRecoverTo: prevStatus)
            }
        }
    }

    public func toggleHUDExpansion() {
        isHUDForceExpanded.toggle()
    }

    public func collapseHUD() {
        isHUDForceExpanded = false
    }

    public func reportError(_ message: String, autoRecoverTo previousStatus: CompanionStatus? = nil) {
        errorDismissTask?.cancel()
        status = .error(message: message)
        errorToastMessage = message
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(3500))
            if !Task.isCancelled {
                self?.errorToastMessage = nil
            }
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled {
                guard let self = self else { return }
                if self.status.isError {
                    let fallback = previousStatus ?? (self.activeTarget.map { .watching(target: $0.matchedSite) } ?? .idle)
                    self.status = fallback
                }
            }
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

        // 1. Zero-TCC fast inspection of frontmost application via NSWorkspace
        guard let front = NSWorkspace.shared.frontmostApplication,
              let appName = front.localizedName,
              appName != "NotchMind"
        else {
            if !status.isError { status = .idle }
            activeTarget = nil
            return
        }

        // 2. If active app is not a whitelisted candidate, never touch SCShareableContent
        guard WindowMonitor.isCandidateApp(
            frontApp: appName,
            monitoringMode: mode,
            focusKeywords: settings.focusKeywords
        ) else {
            if !status.isError { status = .idle }
            activeTarget = nil
            return
        }

        // 3. Throttle SCShareableContent polling:
        // If app has not changed and capture is not yet due, keep current watching status without invoking SC
        let elapsed = Date().timeIntervalSince(lastAutoCaptureTime)
        let isCaptureDue = elapsed >= settings.captureIntervalSeconds
        if !isCaptureDue && activeTarget?.appName == appName {
            return
        }

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

        if isCaptureDue {
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
            reportError(error.localizedDescription)
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
