import AppKit
import Carbon
import Foundation

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    static let defaultHistory = Shortcut(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey), label: "⌘⇧V")
    static let defaultCapture = Shortcut(keyCode: 1, modifiers: UInt32(controlKey | shiftKey | cmdKey), label: "⌃⇧⌘S")

    static func from(_ event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return nil }
        guard let character = event.charactersIgnoringModifiers?.uppercased(), character.count == 1,
              character.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        var carbonFlags: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey); symbols += "⌘" }
        return Shortcut(keyCode: UInt32(event.keyCode), modifiers: carbonFlags, label: symbols + character)
    }
}

enum HotKeyAction: UInt32 {
    case openHistory = 1
    case captureArea = 2

    var storageKey: String {
        switch self {
        case .openHistory: return "globalShortcut"
        case .captureArea: return "captureShortcut"
        }
    }
}

final class HotKeyManager: ObservableObject {
    @Published private(set) var shortcut: Shortcut
    @Published private(set) var captureShortcut: Shortcut
    @Published private(set) var statusMessage: String?
    @Published private(set) var captureStatusMessage: String?
    var onOpenHistory: (() -> Void)?
    var onCaptureArea: (() -> Void)?

    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x43504945

    init() {
        shortcut = Self.savedShortcut(for: .openHistory) ?? .defaultHistory
        captureShortcut = Self.savedShortcut(for: .captureArea) ?? .defaultCapture
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            var receivedID = EventHotKeyID(signature: 0, id: 0)
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &receivedID)
            guard status == noErr, receivedID.signature == manager.signature,
                  let action = HotKeyAction(rawValue: receivedID.id) else { return OSStatus(eventNotHandledErr) }
            switch action {
            case .openHistory: manager.onOpenHistory?()
            case .captureArea: manager.onCaptureArea?()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if register(shortcut, for: .openHistory) != noErr { statusMessage = conflictMessage(for: shortcut) }
        if register(captureShortcut, for: .captureArea) != noErr { captureStatusMessage = conflictMessage(for: captureShortcut) }
    }

    deinit {
        for key in hotKeys.values { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }

    func change(to newShortcut: Shortcut, for action: HotKeyAction) {
        let previous = action == .openHistory ? shortcut : captureShortcut
        guard newShortcut != previous else { return }
        if let oldKey = hotKeys.removeValue(forKey: action.rawValue) { UnregisterEventHotKey(oldKey) }
        if register(newShortcut, for: action) == noErr {
            if action == .openHistory {
                shortcut = newShortcut
                statusMessage = nil
            } else {
                captureShortcut = newShortcut
                captureStatusMessage = nil
            }
            UserDefaults.standard.set(try? JSONEncoder().encode(newShortcut), forKey: action.storageKey)
        } else {
            _ = register(previous, for: action)
            if action == .openHistory { statusMessage = conflictMessage(for: newShortcut) }
            else { captureStatusMessage = conflictMessage(for: newShortcut) }
        }
    }

    private func register(_ value: Shortcut, for action: HotKeyAction) -> OSStatus {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: action.rawValue)
        let result = RegisterEventHotKey(value.keyCode, value.modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        if result == noErr, let reference { hotKeys[action.rawValue] = reference }
        return result
    }

    private func conflictMessage(for shortcut: Shortcut) -> String {
        "\(shortcut.label) could not be registered. It may already be in use."
    }

    private static func savedShortcut(for action: HotKeyAction) -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: action.storageKey) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }
}
