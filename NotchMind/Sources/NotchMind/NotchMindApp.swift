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

    func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)

        if let existing = settingsWindow {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            existing.orderFrontRegardless()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
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
            Button("打开 Obsidian") {
                appDelegate.engine.openInObsidian()
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
