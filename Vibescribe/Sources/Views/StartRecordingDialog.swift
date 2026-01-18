import SwiftUI
import AVFoundation
import ScreenCaptureKit

struct StartRecordingDialog: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var permissions = PermissionsManager.shared

    @State private var availableMics: [AudioDevice] = []
    @State private var selectedMicUid: String?
    @State private var runningApps: [RunningApp] = []
    @State private var selectedAppBundleId: String?
    @State private var isLoadingApps = false
    @State private var showAppPicker = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Start Recording")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            // Microphone Selection
            VStack(alignment: .leading, spacing: 8) {
                Label("Microphone", systemImage: "mic.fill")
                    .font(.headline)

                Picker("Microphone", selection: $selectedMicUid) {
                    Text("System Default").tag(nil as String?)
                    if !availableMics.isEmpty {
                        Divider()
                        ForEach(availableMics) { mic in
                            Text(mic.name + (mic.isDefault ? " (Default)" : ""))
                                .tag(mic.uid as String?)
                        }
                    }
                }
                .labelsHidden()
            }

            // App Selection (for system audio) - optional
            VStack(alignment: .leading, spacing: 8) {
                Label("Capture app audio (optional)", systemImage: "speaker.wave.2.fill")
                    .font(.headline)

                if !showAppPicker {
                    Button("Add app audio source...") {
                        showAppPicker = true
                        Task {
                            await loadRunningApps()
                        }
                    }
                    .buttonStyle(.bordered)
                } else if isLoadingApps {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading apps...")
                            .foregroundStyle(.secondary)
                    }
                } else if !permissions.hasScreenPermission {
                    // Permission not granted
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Screen recording permission required", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("To capture app audio:")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("1. Click \"Open Settings\" below")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("2. Enable Vibescribe in the list")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("3. Quit and reopen Vibescribe (⌘Q, then relaunch)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Open Screen Recording Settings") {
                            permissions.openScreenRecordingSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else if runningApps.isEmpty {
                    // Permission granted but no apps loaded yet
                    HStack {
                        Text("No audio-capable apps found")
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await loadRunningApps() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    Picker("Application", selection: $selectedAppBundleId) {
                        Text("None (mic only)").tag(nil as String?)
                        Divider()
                        ForEach(runningApps) { app in
                            Label {
                                Text(app.name)
                            } icon: {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                            }
                            .tag(app.bundleId as String?)
                        }
                    }
                    .labelsHidden()
                }
            }

            Divider()

            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Start Recording") {
                    startRecording()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!canStart)
            }
        }
        .padding(24)
        .frame(width: 360)
        .task {
            await loadAudioDevices()
            restoreLastUsedSources()
        }
    }

    private var canStart: Bool {
        appState.hasMicPermission || (selectedAppBundleId != nil && permissions.hasScreenPermission)
    }

    private func loadAudioDevices() async {
        availableMics = AudioDeviceManager.shared.getInputDevices()
    }

    private func loadRunningApps() async {
        Log.info("loadRunningApps() called", category: .ui)
        isLoadingApps = true

        // Request permission (prompts on first use) - uses ScreenCaptureKit which respects audio-only permission
        let status = await permissions.requestScreenPermission()
        appState.hasScreenPermission = permissions.hasScreenPermission

        if status == .granted {
            let apps = await AppListManager.shared.getRunningApps()
            Log.info("Loaded \(apps.count) running apps", category: .ui)
            runningApps = apps
        } else {
            Log.warning("No screen permission, cannot list apps (status: \(status))", category: .permissions)
            runningApps = []
        }

        isLoadingApps = false
    }

    private func restoreLastUsedSources() {
        selectedMicUid = appState.selectedMicId
        selectedAppBundleId = appState.selectedAppBundleId
    }

    private func startRecording() {
        // Save selections for next time
        appState.selectedMicId = selectedMicUid
        appState.selectedAppBundleId = selectedAppBundleId

        // Set the app name for display in transcripts
        if let bundleId = selectedAppBundleId,
           let app = runningApps.first(where: { $0.bundleId == bundleId }) {
            appState.selectedAppName = app.name
        } else {
            appState.selectedAppName = nil
        }

        // Start the recording
        appState.startNewSession()

        // Notify TranscriptionService to start capture
        Task {
            await TranscriptionService.shared.startRecording(
                micId: selectedMicUid,
                appBundleId: selectedAppBundleId
            )
        }

        dismiss()
    }
}

#Preview {
    StartRecordingDialog()
        .environment(AppState())
}
