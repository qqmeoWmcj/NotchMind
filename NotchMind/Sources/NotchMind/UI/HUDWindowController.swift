import AppKit
import Combine
import SwiftUI

public struct ScreenNotchMetrics: Equatable, Sendable {
    public let hasNotch: Bool
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    public let screenFrame: CGRect

    public static func detect(for screen: NSScreen) -> ScreenNotchMetrics {
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea
        {
            let gap = max(right.minX - left.maxX, 160)
            return ScreenNotchMetrics(
                hasNotch: true,
                notchWidth: gap,
                notchHeight: topInset,
                screenFrame: screen.frame
            )
        }
        return ScreenNotchMetrics(
            hasNotch: false,
            notchWidth: 180,
            notchHeight: 34,
            screenFrame: screen.frame
        )
    }
}

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class HUDHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        // Pass through mouse clicks landing on transparent spacer / empty background
        return hitView === self ? nil : hitView
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Crucial for Full-Screen mode: ensures the first click on buttons or controls
        // is delivered immediately rather than swallowed by inactive window activation.
        return true
    }
}

@MainActor
public final class HUDWindowController: NSObject {
    private var panel: HUDPanel?
    private let engine: CompanionEngine
    private let openSettingsAction: @MainActor () -> Void
    private var screenObserver: NSObjectProtocol?
    private var screenChangeObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var isUpdatingFrame: Bool = false
    private var recordingCancellable: AnyCancellable?
    private var placementCancellable: AnyCancellable?

    public static let panelWidth: CGFloat = 444
    public static let panelHeight: CGFloat = 560

    public init(engine: CompanionEngine, openSettings: @escaping @MainActor () -> Void) {
        self.engine = engine
        self.openSettingsAction = openSettings
        super.init()
    }

    public func show() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let metrics = screen.map(ScreenNotchMetrics.detect) ?? ScreenNotchMetrics(
            hasNotch: false, notchWidth: 180, notchHeight: 34,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        let rootView = NotchHUDView(
            engine: engine,
            metrics: metrics,
            onOpenSettings: openSettingsAction
        )

        let hosting = HUDHostingView(rootView: rootView)
        hosting.sizingOptions = []

        let frame = computePanelFrame(metrics: metrics)
        let panel = HUDPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.worksWhenModal = true
        panel.isMovableByWindowBackground = !metrics.hasNotch
        panel.sharingType = engine.settings.allowScreenRecording ? .readOnly : .none
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel

        setupWindowMoveObserver(for: panel)

        recordingCancellable = engine.settings.$allowScreenRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] allow in
                self?.panel?.sharingType = allow ? .readOnly : .none
            }

        placementCancellable = engine.settings.$externalDisplayPlacement
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reposition()
            }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reposition()
            }
        }

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reposition()
            }
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.bringToFront()
            }
        }
    }

    public func bringToFront() {
        panel?.orderFrontRegardless()
    }

    public func reposition() {
        guard let panel, let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let metrics = ScreenNotchMetrics.detect(for: screen)
        isUpdatingFrame = true
        panel.setFrame(computePanelFrame(metrics: metrics), display: true)
        isUpdatingFrame = false
        panel.isMovableByWindowBackground = !metrics.hasNotch
        if let hosting = panel.contentView as? HUDHostingView<NotchHUDView> {
            hosting.rootView = NotchHUDView(
                engine: engine,
                metrics: metrics,
                onOpenSettings: openSettingsAction
            )
        }
    }

    private func setupWindowMoveObserver(for panel: HUDPanel) {
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard let self, let panel, !self.isUpdatingFrame else { return }
                guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
                let m = ScreenNotchMetrics.detect(for: screen)
                guard !m.hasNotch else { return }

                let sf = m.screenFrame
                let origin = panel.frame.origin
                let usableWidth = max(sf.width - Self.panelWidth, 1.0)
                let ratio = (origin.x - sf.minX) / usableWidth
                let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
                let topY = sf.maxY - menuBarHeight - 6
                let offset = max(0, topY - (origin.y + Self.panelHeight))

                self.engine.settings.externalDisplayCustomXRatio = min(max(ratio, 0.0), 1.0)
                self.engine.settings.externalDisplayCustomYOffset = offset
                self.engine.settings.externalDisplayPlacement = .custom
            }
        }
    }

    private func computePanelFrame(metrics: ScreenNotchMetrics) -> CGRect {
        let sf = metrics.screenFrame
        if metrics.hasNotch {
            let x = sf.midX - Self.panelWidth / 2
            let y = sf.maxY - Self.panelHeight
            return CGRect(x: x, y: y, width: Self.panelWidth, height: Self.panelHeight)
        }

        let screen = NSScreen.screens.first(where: { $0.frame == sf }) ?? NSScreen.main ?? NSScreen.screens.first
        let menuBarHeight = screen.map { max(0, $0.frame.maxY - $0.visibleFrame.maxY) } ?? 0
        let topY = sf.maxY - menuBarHeight - 6

        let placement = engine.settings.externalDisplayPlacement
        let x: CGFloat
        let y: CGFloat

        switch placement {
        case .topCenter:
            x = sf.midX - Self.panelWidth / 2
            y = topY - Self.panelHeight
        case .topLeading:
            x = sf.minX + 80
            y = topY - Self.panelHeight
        case .topTrailingSafe:
            x = max(sf.minX, sf.maxX - Self.panelWidth - 220)
            y = topY - Self.panelHeight
        case .custom:
            let ratio = engine.settings.externalDisplayCustomXRatio
            let offset = engine.settings.externalDisplayCustomYOffset
            let maxX = max(sf.minX, sf.maxX - Self.panelWidth)
            x = min(maxX, max(sf.minX, sf.minX + (sf.width - Self.panelWidth) * ratio))
            let defaultY = topY - Self.panelHeight
            y = min(defaultY, max(sf.minY, defaultY - offset))
        }

        return CGRect(x: x, y: y, width: Self.panelWidth, height: Self.panelHeight)
    }
}
