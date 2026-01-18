import SwiftUI
import Carbon
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var silenceDuration: Double = 1.5
    @State private var silenceThreshold: Double = 0.008
    @State private var alwaysOnTop: Bool = false

    var body: some View {
        TabView {
            GeneralSettingsView(
                silenceDuration: $silenceDuration,
                silenceThreshold: $silenceThreshold,
                alwaysOnTop: $alwaysOnTop
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            HotkeySettingsView()
                .tabItem {
                    Label("Hotkey", systemImage: "keyboard")
                }

            StorageSettingsView()
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }
        }
        .frame(width: 450, height: 300)
        .onAppear {
            silenceDuration = appState.silenceDuration
            silenceThreshold = appState.silenceThreshold
            alwaysOnTop = appState.alwaysOnTop
        }
        .onChange(of: silenceDuration) { _, newValue in
            appState.silenceDuration = newValue
        }
        .onChange(of: silenceThreshold) { _, newValue in
            appState.silenceThreshold = newValue
        }
        .onChange(of: alwaysOnTop) { _, newValue in
            appState.alwaysOnTop = newValue
        }
    }
}

struct GeneralSettingsView: View {
    @Binding var silenceDuration: Double
    @Binding var silenceThreshold: Double
    @Binding var alwaysOnTop: Bool

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Silence Duration")
                        Spacer()
                        Text(String(format: "%.1fs", silenceDuration))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: $silenceDuration, in: 0.5...3.0, step: 0.5)

                    Text("How long to wait after speech ends before starting a new line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Silence Threshold")
                        Spacer()
                        Text(String(format: "%.3f", silenceThreshold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: $silenceThreshold, in: 0.002...0.02, step: 0.001)

                    Text("Audio level below which is considered silence. Lower = more sensitive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Always on Top", isOn: $alwaysOnTop)
            }

            Section("Speech Model") {
                LabeledContent("Model", value: "Parakeet TDT v3")
                LabeledContent("Size", value: "~650 MB")
                LabeledContent("Provider", value: "FluidAudio")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct HotkeySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var hotkeyText: String = "Not set"
    @State private var isRecordingHotkey: Bool = false
    @State private var bringToFront: Bool = true

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Global Hotkey")
                    Spacer()
                    Button(isRecordingHotkey ? "Press keys..." : hotkeyText) {
                        startRecordingHotkey()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])
                }

                Text("Press the shortcut you want to use to toggle recording from anywhere")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Clear Hotkey") {
                    clearHotkey()
                }
                .disabled(hotkeyText == "Not set")
            }

            Section {
                Toggle("Bring window to front", isOn: $bringToFront)

                Text("When the hotkey is pressed, bring the VibeScribe window to the front")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadHotkeySettings()
        }
        .onChange(of: bringToFront) { _, newValue in
            appState.bringToFrontOnHotkey = newValue
        }
    }

    private func loadHotkeySettings() {
        let settings = SettingsManager.shared
        if settings.hasHotkeyConfigured {
            hotkeyText = HotkeyManager.shared.formatHotkey(
                keyCode: settings.globalHotkeyCode,
                modifiers: settings.globalHotkeyModifiers
            )
        } else {
            hotkeyText = "Not set"
        }
        bringToFront = settings.bringToFrontOnHotkey
    }

    private func startRecordingHotkey() {
        isRecordingHotkey = true
        // In a full implementation, we would use NSEvent.addLocalMonitorForEvents
        // to capture the next key press. For now, we'll use a simpler approach.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingHotkey else { return event }

            let keyCode = UInt32(event.keyCode)
            var modifiers: UInt32 = 0

            if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }

            // Require at least one modifier
            if modifiers == 0 {
                return nil
            }

            // Save and register the hotkey
            SettingsManager.shared.globalHotkeyCode = keyCode
            SettingsManager.shared.globalHotkeyModifiers = modifiers

            let registered = HotkeyManager.shared.registerHotkey(keyCode: keyCode, modifiers: modifiers)
            if registered {
                HotkeyManager.shared.onHotkeyPressed = {
                    Task { @MainActor in
                        if appState.bringToFrontOnHotkey {
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        await appState.handleHotkeyToggle()
                    }
                }
                hotkeyText = HotkeyManager.shared.formatHotkey(keyCode: keyCode, modifiers: modifiers)
            }

            isRecordingHotkey = false
            return nil
        }
    }

    private func clearHotkey() {
        HotkeyManager.shared.unregisterHotkey()
        SettingsManager.shared.globalHotkeyCode = 0
        SettingsManager.shared.globalHotkeyModifiers = 0
        hotkeyText = "Not set"
    }
}

struct StorageSettingsView: View {
    @State private var databaseSize: String = "Calculating..."
    @State private var logSize: String = "Calculating..."
    @State private var sessionCount: Int = 0
    @State private var showingStorageWarning: Bool = false

    private let storageWarningThreshold: Int64 = 1_000_000_000 // 1 GB

    var body: some View {
        Form {
            Section {
                LabeledContent("Database Size", value: databaseSize)
                LabeledContent("Log Size", value: logSize)
                LabeledContent("Sessions", value: "\(sessionCount)")

                if showingStorageWarning {
                    Label("Storage exceeds 1 GB", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Section {
                Button("Clear Model Cache") {
                    Task {
                        try? await TranscriptionService.shared.clearCache()
                    }
                }

                Text("This will delete the downloaded speech model (~650 MB). It will be re-downloaded on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Clear Event Logs") {
                    EventLogger.shared.clearLogs()
                    Task {
                        await calculateStorageSize()
                    }
                }

                Text("Clear diagnostic event logs. This does not affect your transcription sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Open Storage Folder") {
                    if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                        let vibescribeUrl = url.appendingPathComponent("VibeScribe")
                        NSWorkspace.shared.open(vibescribeUrl)
                    }
                }

                Button("Export Logs") {
                    if let logUrl = EventLogger.shared.exportLogs() {
                        NSWorkspace.shared.activateFileViewerSelecting([logUrl])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await calculateStorageSize()
        }
    }

    private func calculateStorageSize() async {
        let dbSize = DatabaseManager.shared.getDatabaseSize()
        let eventLogSize = EventLogger.shared.getLogFileSize()
        let totalSize = dbSize + eventLogSize

        databaseSize = formatBytes(dbSize)
        logSize = formatBytes(eventLogSize)
        sessionCount = DatabaseManager.shared.getSessionCount()
        showingStorageWarning = totalSize >= storageWarningThreshold
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
