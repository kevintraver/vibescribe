import SwiftUI
import AppKit

@main
struct VibeScribeApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 400, minHeight: 300)
                .onAppear {
                    setupHotkey()
                    checkCrashRecovery()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 600, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Transcript") {
                    appState.showingStartRecordingDialog = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!appState.canStartRecording)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    private func setupHotkey() {
        // Restore saved hotkey if configured
        let settings = SettingsManager.shared
        if settings.hasHotkeyConfigured {
            let registered = HotkeyManager.shared.registerHotkey(
                keyCode: settings.globalHotkeyCode,
                modifiers: settings.globalHotkeyModifiers
            )
            if registered {
                HotkeyManager.shared.onHotkeyPressed = { [appState] in
                    Task { @MainActor in
                        if appState.bringToFrontOnHotkey {
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        await appState.handleHotkeyToggle()
                    }
                }
            }
        }
    }

    private func checkCrashRecovery() {
        Task { @MainActor in
            appState.checkForCrashRecovery()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("=== VibeScribe Launch ===", category: .general)
        Log.info("macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)", category: .general)
        Log.info("App bundle: \(Bundle.main.bundleIdentifier ?? "none")", category: .general)

        EventLogger.shared.log(.appLaunch)

        // Activate the app and bring window to front
        Log.debug("Setting activation policy to .regular", category: .general)
        NSApp.setActivationPolicy(.regular)

        Log.debug("Activating app", category: .general)
        NSApp.activate(ignoringOtherApps: true)

        Log.info("App launch complete", category: .general)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("App terminating", category: .general)
        EventLogger.shared.log(.appTerminate)
        HotkeyManager.shared.unregisterHotkey()

        // Clean up any unclosed sessions
        DatabaseManager.shared.closeAllUnclosedSessions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
