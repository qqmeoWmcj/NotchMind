import AppKit
import SwiftUI

@MainActor
final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = CompanionEngine()
    var hudController: HUDWindowController?
    private var settingsWindow: NSWindow?
    private let settingsDelegate = SettingsWindowDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hudController = HUDWindowController(engine: engine) { [weak self] in
            self?.openSettingsWindow()
        }
        hudController?.show()
        engine.start()

        settingsDelegate.onClose = { [weak self] in
            NSApp.setActivationPolicy(.accessory)
            self?.hudController?.bringToFront()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    func syncToGitHub() {
        Task.detached { [weak self] in
            guard let self else { return }
            let scriptPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("ai-hotspot-creator")
                .appendingPathComponent("sync.sh").path
            guard FileManager.default.fileExists(atPath: scriptPath) else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath, "chore: sync from NotchMind macOS HUD"]
            try? process.run()
            process.waitUntilExit()
            await MainActor.run {
                if process.terminationStatus == 0 {
                    self.engine.status = .paused(reason: "已同步到 GitHub")
                } else {
                    self.engine.status = .error(message: "GitHub 同步需先配置 origin 远端")
                }
            }
        }
    }

    func openSettingsWindow() {
        // Order matters for an LSUIElement/accessory app: activating first, then
        // switching the activation policy, keeps AppKit from flashing the HUD
        // (policy switches re-layout .canJoinAllSpaces/.stationary panels).
        NSApp.activate(ignoringOtherApps: true)

        if let existing = settingsWindow {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            NSApp.setActivationPolicy(.regular)
            existing.orderFrontRegardless()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(settings: engine.settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "NotchMind 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = settingsDelegate
        self.settingsWindow = window
        NSApp.setActivationPolicy(.regular)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

@main
struct NotchMindApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NotchMind", systemImage: appDelegate.engine.status.isActive ? "eye" : "eye.slash") {
            Text(appDelegate.engine.status.shortLabel)
            Divider()
            Button(appDelegate.engine.settings.autoCompanionEnabled ? "暂停伴随同看" : "开始伴随同看") {
                appDelegate.engine.toggleCompanion()
            }
            Button("捕获当前画面 (⌘⇧S)") {
                appDelegate.engine.triggerManualCapture()
            }
            Button("展开/收起灵动岛 (⌘⌃N)") {
                appDelegate.engine.toggleHUDExpansion()
            }
            Button("打开 Obsidian") {
                appDelegate.engine.openInObsidian()
            }
            Button("同步知识库到 GitHub") {
                appDelegate.syncToGitHub()
            }
            Divider()
            Button("设置...") {
                appDelegate.openSettingsWindow()
            }
            Button("退出 NotchMind") {
                NSApp.terminate(nil)
            }
        }
    }
}
