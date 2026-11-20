import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

public enum WindowMonitor {
    public static let browserAppNames: Set<String> = [
        "Google Chrome", "Safari", "Arc", "Brave Browser", "Microsoft Edge", "Firefox", "Dia", "Zen",
    ]

    public static let blockedTitleTokens: [String] = [
        "127.0.0.1", "localhost", "0.0.0.0", "notchmind", "ai 热点工作台",
    ]

    /// Pure whitelist evaluation (unit-testable without Screen Recording permissions).
    public static func evaluate(
        frontApp: String,
        windowTitle: String,
        windowID: CGWindowID,
        allowedSiteKeywords: [String]
    ) -> TargetWindow? {
        let app = frontApp.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !app.isEmpty, app != "NotchMind" else { return nil }

        let lowerTitle = title.lowercased()
        for blocked in blockedTitleTokens where lowerTitle.contains(blocked) {
            return nil
        }

        if app == "PiliPlus" {
            return TargetWindow(
                windowID: windowID,
                appName: app,
                title: title.isEmpty ? "PiliPlus" : title,
                bvid: URLCanonicalizer.extractBVID(from: title),
                isPiliPlus: true,
                matchedSite: "PiliPlus"
            )
        }

        if browserAppNames.contains(app) {
            for kw in allowedSiteKeywords {
                let needle = kw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !needle.isEmpty else { continue }
                if lowerTitle.contains(needle) {
                    return TargetWindow(
                        windowID: windowID,
                        appName: app,
                        title: title,
                        bvid: URLCanonicalizer.extractBVID(from: title),
                        isPiliPlus: false,
                        matchedSite: kw
                    )
                }
            }
        }

        return nil
    }

    /// Pure intent-aware evaluation (unit-testable without Screen Recording permissions).
    /// - `.manual`: never triggers auto-capture (returns nil).
    /// - `.focused`: matches only when the foreground window title hits one of `focusKeywords`
    ///   (works across browsers, PiliPlus, and creative/docs apps like Blender, Obsidian, Preview).
    /// - `.continuous`: falls back to the strict site/app whitelist.
    public static func evaluate(
        frontApp: String,
        windowTitle: String,
        windowID: CGWindowID,
        allowedSiteKeywords: [String],
        monitoringMode: MonitoringMode,
        focusKeywords: [String]
    ) -> TargetWindow? {
        switch monitoringMode {
        case .manual:
            return nil
        case .continuous:
            return evaluate(
                frontApp: frontApp,
                windowTitle: windowTitle,
                windowID: windowID,
                allowedSiteKeywords: allowedSiteKeywords
            )
        case .focused:
            let app = frontApp.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !app.isEmpty, app != "NotchMind" else { return nil }

            let lowerTitle = title.lowercased()
            for blocked in blockedTitleTokens where lowerTitle.contains(blocked) {
                return nil
            }

            let cleanedKeywords = focusKeywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !cleanedKeywords.isEmpty else { return nil }

            let combined = "\(app) \(title)".lowercased()
            for kw in cleanedKeywords {
                if combined.contains(kw.lowercased()) {
                    return TargetWindow(
                        windowID: windowID,
                        appName: app,
                        title: title.isEmpty ? app : title,
                        bvid: URLCanonicalizer.extractBVID(from: title),
                        isPiliPlus: app == "PiliPlus",
                        matchedSite: "聚焦·\(kw)"
                    )
                }
            }
            return nil
        }
    }

    /// Detects the active foreground window using NSWorkspace + ScreenCaptureKit shareable content.
    /// Never matches background PiliPlus windows, and never falls back to full screen.
    public static func detectWhitelistedForegroundWindow(
        allowedSiteKeywords: [String],
        monitoringMode: MonitoringMode = .continuous,
        focusKeywords: [String] = []
    ) async -> TargetWindow? {
        if monitoringMode == .manual { return nil }
        guard let front = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }),
              let appName = front.localizedName,
              appName != "NotchMind"
        else { return nil }

        let pid = front.processIdentifier
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }

        let candidates = content.windows.filter { win in
            win.owningApplication?.processID == pid
                && win.isOnScreen
                && win.windowLayer == 0
                && win.frame.width >= 320
                && win.frame.height >= 200
        }

        guard let topWindow = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            return nil
        }

        return evaluate(
            frontApp: appName,
            windowTitle: topWindow.title ?? "",
            windowID: topWindow.windowID,
            allowedSiteKeywords: allowedSiteKeywords,
            monitoringMode: monitoringMode,
            focusKeywords: focusKeywords
        )
    }

    /// For explicit manual capture via global hotkey (⌘⇧S): captures the active foreground app window
    /// (still excluding NotchMind itself and blocked localhost titles).
    public static func detectManualForegroundWindow() async -> TargetWindow? {
        guard let front = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }),
              let appName = front.localizedName,
              appName != "NotchMind"
        else { return nil }

        let pid = front.processIdentifier
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }
        let candidates = content.windows.filter { win in
            win.owningApplication?.processID == pid
                && win.isOnScreen
                && win.windowLayer == 0
                && win.frame.width >= 240
                && win.frame.height >= 160
        }
        guard let topWindow = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            return nil
        }
        let title = topWindow.title ?? appName
        let lowerTitle = title.lowercased()
        for blocked in blockedTitleTokens where lowerTitle.contains(blocked) {
            return nil
        }
        return TargetWindow(
            windowID: topWindow.windowID,
            appName: appName,
            title: title,
            bvid: URLCanonicalizer.extractBVID(from: title),
            isPiliPlus: appName == "PiliPlus",
            matchedSite: appName
        )
    }
}
