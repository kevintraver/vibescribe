import Foundation
import Carbon
import AppKit

/// Manages global hotkey registration and handling
final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var lastTriggerTime: Date?

    /// Callback when hotkey is pressed
    var onHotkeyPressed: (() -> Void)?

    /// Debounce interval in seconds
    private let debounceInterval: TimeInterval = 0.5

    /// Current hotkey configuration
    private(set) var currentKeyCode: UInt32 = 0
    private(set) var currentModifiers: UInt32 = 0

    private init() {}

    deinit {
        unregisterHotkey()
    }

    // MARK: - Registration

    /// Register a global hotkey
    /// - Parameters:
    ///   - keyCode: The key code (e.g., kVK_ANSI_R for 'R')
    ///   - modifiers: The modifier flags (e.g., cmdKey | optionKey)
    /// - Returns: true if registration succeeded
    @discardableResult
    func registerHotkey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        // Unregister any existing hotkey
        unregisterHotkey()

        // Create hotkey ID
        var hotkeyID = EventHotKeyID()
        hotkeyID.signature = OSType(0x5642_5342) // "VBSB" in hex
        hotkeyID.id = 1

        // Register hotkey
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr else {
            print("Failed to register hotkey: \(status)")
            return false
        }

        // Install event handler
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                HotkeyManager.shared.handleHotkeyEvent()
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &eventHandler
        )

        if handlerStatus != noErr {
            print("Failed to install event handler: \(handlerStatus)")
            unregisterHotkey()
            return false
        }

        currentKeyCode = keyCode
        currentModifiers = modifiers

        return true
    }

    /// Unregister the current hotkey
    func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }

        currentKeyCode = 0
        currentModifiers = 0
    }

    /// Handle the hotkey event
    private func handleHotkeyEvent() {
        // Debounce check
        if let lastTime = lastTriggerTime,
           Date().timeIntervalSince(lastTime) < debounceInterval {
            return
        }

        lastTriggerTime = Date()

        // Call the callback on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onHotkeyPressed?()
        }
    }

    // MARK: - Hotkey Parsing

    /// Parse a hotkey string like "Cmd+Shift+R" into keyCode and modifiers
    func parseHotkeyString(_ string: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let components = string.uppercased().components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }

        guard !components.isEmpty else { return nil }

        var modifiers: UInt32 = 0
        var keyString: String?

        for component in components {
            switch component {
            case "CMD", "COMMAND", "":
                modifiers |= UInt32(cmdKey)
            case "CTRL", "CONTROL":
                modifiers |= UInt32(controlKey)
            case "OPT", "OPTION", "ALT":
                modifiers |= UInt32(optionKey)
            case "SHIFT":
                modifiers |= UInt32(shiftKey)
            default:
                keyString = component
            }
        }

        guard let key = keyString, let keyCode = keyCodeForString(key) else {
            return nil
        }

        return (keyCode, modifiers)
    }

    /// Get the key code for a single character or key name
    private func keyCodeForString(_ string: String) -> UInt32? {
        let keyCodes: [String: UInt32] = [
            "A": UInt32(kVK_ANSI_A),
            "B": UInt32(kVK_ANSI_B),
            "C": UInt32(kVK_ANSI_C),
            "D": UInt32(kVK_ANSI_D),
            "E": UInt32(kVK_ANSI_E),
            "F": UInt32(kVK_ANSI_F),
            "G": UInt32(kVK_ANSI_G),
            "H": UInt32(kVK_ANSI_H),
            "I": UInt32(kVK_ANSI_I),
            "J": UInt32(kVK_ANSI_J),
            "K": UInt32(kVK_ANSI_K),
            "L": UInt32(kVK_ANSI_L),
            "M": UInt32(kVK_ANSI_M),
            "N": UInt32(kVK_ANSI_N),
            "O": UInt32(kVK_ANSI_O),
            "P": UInt32(kVK_ANSI_P),
            "Q": UInt32(kVK_ANSI_Q),
            "R": UInt32(kVK_ANSI_R),
            "S": UInt32(kVK_ANSI_S),
            "T": UInt32(kVK_ANSI_T),
            "U": UInt32(kVK_ANSI_U),
            "V": UInt32(kVK_ANSI_V),
            "W": UInt32(kVK_ANSI_W),
            "X": UInt32(kVK_ANSI_X),
            "Y": UInt32(kVK_ANSI_Y),
            "Z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0),
            "1": UInt32(kVK_ANSI_1),
            "2": UInt32(kVK_ANSI_2),
            "3": UInt32(kVK_ANSI_3),
            "4": UInt32(kVK_ANSI_4),
            "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6),
            "7": UInt32(kVK_ANSI_7),
            "8": UInt32(kVK_ANSI_8),
            "9": UInt32(kVK_ANSI_9),
            "SPACE": UInt32(kVK_Space),
            "RETURN": UInt32(kVK_Return),
            "ENTER": UInt32(kVK_Return),
            "TAB": UInt32(kVK_Tab),
            "DELETE": UInt32(kVK_Delete),
            "ESCAPE": UInt32(kVK_Escape),
            "ESC": UInt32(kVK_Escape),
            "F1": UInt32(kVK_F1),
            "F2": UInt32(kVK_F2),
            "F3": UInt32(kVK_F3),
            "F4": UInt32(kVK_F4),
            "F5": UInt32(kVK_F5),
            "F6": UInt32(kVK_F6),
            "F7": UInt32(kVK_F7),
            "F8": UInt32(kVK_F8),
            "F9": UInt32(kVK_F9),
            "F10": UInt32(kVK_F10),
            "F11": UInt32(kVK_F11),
            "F12": UInt32(kVK_F12),
        ]

        return keyCodes[string.uppercased()]
    }

    /// Format a hotkey as a display string
    func formatHotkey(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 { parts.append("") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("") }

        if let keyString = stringForKeyCode(keyCode) {
            parts.append(keyString)
        }

        return parts.joined()
    }

    private func stringForKeyCode(_ keyCode: UInt32) -> String? {
        let keyStrings: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A",
            UInt32(kVK_ANSI_B): "B",
            UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E",
            UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G",
            UInt32(kVK_ANSI_H): "H",
            UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K",
            UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M",
            UInt32(kVK_ANSI_N): "N",
            UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q",
            UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W",
            UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y",
            UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0",
            UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4",
            UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "",
            UInt32(kVK_Tab): "",
            UInt32(kVK_Delete): "",
            UInt32(kVK_Escape): "",
            UInt32(kVK_F1): "F1",
            UInt32(kVK_F2): "F2",
            UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4",
            UInt32(kVK_F5): "F5",
            UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7",
            UInt32(kVK_F8): "F8",
            UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10",
            UInt32(kVK_F11): "F11",
            UInt32(kVK_F12): "F12",
        ]

        return keyStrings[keyCode]
    }
}
