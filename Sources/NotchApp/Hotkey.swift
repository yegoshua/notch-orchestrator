import AppKit
import Carbon.HIToolbox

/// A system-wide key combination. Registered through Carbon, which needs no permission from the
/// user, unlike watching the keyboard.
@MainActor
final class GlobalHotkey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var isDispatcherInstalled = false

    private let id: UInt32
    private var reference: EventHotKeyRef?

    /// Nil when the system refuses the combination, for instance because another app holds it.
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.installDispatcher()
        id = Self.nextID
        Self.nextID += 1
        let status = RegisterEventHotKey(
            keyCode, modifiers, EventHotKeyID(signature: 0x4E_4F_54_43, id: id),
            GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, reference != nil else { return nil }
        Self.handlers[id] = handler
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        let id = id
        Task { @MainActor in Self.handlers[id] = nil }
    }

    private static func installDispatcher() {
        guard !isDispatcherInstalled else { return }
        isDispatcherInstalled = true
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotkey = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            let id = hotkey.id
            Task { @MainActor in GlobalHotkey.handlers[id]?() }
            return noErr
        }, 1, &pressed, nil, nil)
    }
}

/// The user's choice of the combination that expands the session list.
struct HotkeySetting: Equatable {
    static let changed = Notification.Name("HotkeySettingChanged")
    static let escapeKeyCode = UInt32(kVK_Escape)

    var title: String
    var keyCode: UInt32
    /// Carbon modifier flags. Zero together with a zero key code means "no hotkey".
    var modifiers: UInt32

    static let none = HotkeySetting(title: "None", keyCode: 0, modifiers: 0)
    static let presets = [
        HotkeySetting(title: "⌃⌥N", keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey)),
        HotkeySetting(title: "⌃⌥Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
        HotkeySetting(title: "⌥⌘J", keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(optionKey | cmdKey)),
        HotkeySetting(title: "⌃⌥⌘S", keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey | cmdKey)),
        none,
    ]

    var isNone: Bool { modifiers == 0 }

    /// The stored choice, the first preset by default. Any combination can be stored by hand:
    /// `defaults write <bundle id> hotkeyKeyCode -int …` and `hotkeyModifiers -int …`.
    static var current: HotkeySetting {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: "hotkeyModifiers") != nil else { return presets[0] }
            let keyCode = UInt32(clamping: defaults.integer(forKey: "hotkeyKeyCode"))
            let modifiers = UInt32(clamping: defaults.integer(forKey: "hotkeyModifiers"))
            return presets.first { $0.keyCode == keyCode && $0.modifiers == modifiers }
                ?? HotkeySetting(title: "Custom", keyCode: keyCode, modifiers: modifiers)
        }
        set {
            UserDefaults.standard.set(Int(newValue.keyCode), forKey: "hotkeyKeyCode")
            UserDefaults.standard.set(Int(newValue.modifiers), forKey: "hotkeyModifiers")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}

/// The "Expand Hotkey" submenu of the status menu.
@MainActor
final class HotkeyMenu: NSObject {
    static let shared = HotkeyMenu()

    func add(to menu: NSMenu) {
        let item = NSMenuItem(title: "Expand Hotkey", action: nil, keyEquivalent: "")
        item.submenu = NSMenu()
        let current = HotkeySetting.current
        var choices = HotkeySetting.presets
        if !choices.contains(current) { choices.insert(current, at: 0) }
        for (index, choice) in choices.enumerated() {
            let entry = item.submenu!.addItem(withTitle: choice.title, action: #selector(choose(_:)), keyEquivalent: "")
            entry.target = self
            entry.state = choice == current ? .on : .off
            entry.tag = choices.count == HotkeySetting.presets.count ? index : index - 1
        }
        menu.addItem(item)
    }

    @objc private func choose(_ sender: NSMenuItem) {
        // A negative tag is the custom combination already in effect.
        guard HotkeySetting.presets.indices.contains(sender.tag) else { return }
        HotkeySetting.current = HotkeySetting.presets[sender.tag]
    }
}
