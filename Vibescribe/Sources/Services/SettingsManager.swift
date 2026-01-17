import Foundation

/// Keys for UserDefaults storage
enum SettingsKey {
    static let lastMicUID = "lastMicUID"
    static let lastAppBundleId = "lastAppBundleId"
    static let globalHotkeyCode = "globalHotkeyCode"
    static let globalHotkeyModifiers = "globalHotkeyModifiers"
    static let alwaysOnTop = "alwaysOnTop"
    static let silenceDuration = "silenceDuration"
    static let silenceThreshold = "silenceThreshold"
    static let windowFrame = "windowFrame"
    static let bringToFrontOnHotkey = "bringToFrontOnHotkey"
}

/// Manages persistent settings using UserDefaults
final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private init() {
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            SettingsKey.silenceDuration: 1.5,
            SettingsKey.silenceThreshold: 0.008,
            SettingsKey.alwaysOnTop: false,
            SettingsKey.bringToFrontOnHotkey: true
        ])
    }

    // MARK: - Audio Sources

    var lastMicUID: String? {
        get { defaults.string(forKey: SettingsKey.lastMicUID) }
        set { defaults.set(newValue, forKey: SettingsKey.lastMicUID) }
    }

    var lastAppBundleId: String? {
        get { defaults.string(forKey: SettingsKey.lastAppBundleId) }
        set { defaults.set(newValue, forKey: SettingsKey.lastAppBundleId) }
    }

    // MARK: - Hotkey

    var globalHotkeyCode: UInt32 {
        get { UInt32(defaults.integer(forKey: SettingsKey.globalHotkeyCode)) }
        set { defaults.set(Int(newValue), forKey: SettingsKey.globalHotkeyCode) }
    }

    var globalHotkeyModifiers: UInt32 {
        get { UInt32(defaults.integer(forKey: SettingsKey.globalHotkeyModifiers)) }
        set { defaults.set(Int(newValue), forKey: SettingsKey.globalHotkeyModifiers) }
    }

    var hasHotkeyConfigured: Bool {
        globalHotkeyCode != 0
    }

    // MARK: - Window

    var alwaysOnTop: Bool {
        get { defaults.bool(forKey: SettingsKey.alwaysOnTop) }
        set { defaults.set(newValue, forKey: SettingsKey.alwaysOnTop) }
    }

    var windowFrame: NSRect? {
        get {
            guard let data = defaults.data(forKey: SettingsKey.windowFrame) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data)?.rectValue
        }
        set {
            if let rect = newValue {
                let value = NSValue(rect: rect)
                let data = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
                defaults.set(data, forKey: SettingsKey.windowFrame)
            } else {
                defaults.removeObject(forKey: SettingsKey.windowFrame)
            }
        }
    }

    var bringToFrontOnHotkey: Bool {
        get { defaults.bool(forKey: SettingsKey.bringToFrontOnHotkey) }
        set { defaults.set(newValue, forKey: SettingsKey.bringToFrontOnHotkey) }
    }

    // MARK: - Transcription

    var silenceDuration: Double {
        get { defaults.double(forKey: SettingsKey.silenceDuration) }
        set { defaults.set(newValue, forKey: SettingsKey.silenceDuration) }
    }

    var silenceThreshold: Double {
        get { defaults.double(forKey: SettingsKey.silenceThreshold) }
        set { defaults.set(newValue, forKey: SettingsKey.silenceThreshold) }
    }

    // MARK: - Reset

    func resetAll() {
        let domain = Bundle.main.bundleIdentifier ?? "com.vibescribe.app"
        defaults.removePersistentDomain(forName: domain)
        registerDefaults()
    }
}
