import Carbon
import Foundation

@MainActor
public final class HotkeyManager {
    private var captureHotKeyRef: EventHotKeyRef?
    private var toggleHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static var onCaptureTrigger: (@MainActor () -> Void)?
    private static var onToggleTrigger: (@MainActor () -> Void)?

    public init() {}

    /// Registers global hotkeys:
    /// - ⌘⇧S (Command + Shift + S): capture foreground window
    /// - ⌘⌃N (Command + Control + N): toggle HUD expanded / collapsed
    public func registerShortcuts(
        onCapture: @escaping @MainActor () -> Void,
        onToggle: @escaping @MainActor () -> Void
    ) {
        unregister()
        Self.onCaptureTrigger = onCapture
        Self.onToggleTrigger = onToggle

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, inEvent, _ in
            guard let inEvent else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                inEvent,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return noErr }

            Task { @MainActor in
                if hotKeyID.id == 1 {
                    HotkeyManager.onCaptureTrigger?()
                } else if hotKeyID.id == 2 {
                    HotkeyManager.onToggleTrigger?()
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        // 1. ⌘⇧S (Capture)
        let captureID = EventHotKeyID(signature: OSType(0x4E4D4831), id: 1) // 'NMH1'
        let err1 = RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(cmdKey | shiftKey),
            captureID,
            GetApplicationEventTarget(),
            0,
            &captureHotKeyRef
        )
        if err1 != noErr {
            NSLog("[HotkeyManager] Warning: failed to register ⌘⇧S shortcut (OSStatus: %d)", err1)
        }

        // 2. ⌘⌃N (Toggle HUD)
        let toggleID = EventHotKeyID(signature: OSType(0x4E4D4832), id: 2) // 'NMH2'
        let err2 = RegisterEventHotKey(
            UInt32(kVK_ANSI_N),
            UInt32(cmdKey | controlKey),
            toggleID,
            GetApplicationEventTarget(),
            0,
            &toggleHotKeyRef
        )
        if err2 != noErr {
            NSLog("[HotkeyManager] Warning: failed to register ⌘⌃N shortcut (OSStatus: %d)", err2)
        }
    }

    public func unregister() {
        if let ref = captureHotKeyRef {
            UnregisterEventHotKey(ref)
            captureHotKeyRef = nil
        }
        if let ref = toggleHotKeyRef {
            UnregisterEventHotKey(ref)
            toggleHotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
