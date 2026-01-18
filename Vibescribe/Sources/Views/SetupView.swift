import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var micPermissionStatus: PermissionsManager.PermissionStatus = .notDetermained

    var body: some View {
        VStack(spacing: 32) {
            // App Icon and Title
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("VibeScribe")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Live transcription for collaborative conversations")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(maxWidth: 300)

            // Setup Steps
            VStack(alignment: .leading, spacing: 24) {
                // Microphone Permission
                SetupStepView(
                    icon: "mic.fill",
                    title: "Microphone Access",
                    description: "Required to transcribe your voice",
                    isComplete: appState.hasMicPermission,
                    action: requestMicPermission,
                    micPermissionStatus: micPermissionStatus
                )

                // Model Download
                SetupStepView(
                    icon: "arrow.down.circle.fill",
                    title: "Download Speech Model",
                    description: "~650 MB, required for transcription",
                    isComplete: appState.isModelReady,
                    isLoading: appState.isModelDownloading,
                    progress: appState.modelDownloadProgress,
                    action: downloadModel
                )
            }
            .frame(maxWidth: 400)

            Spacer()

            if appState.hasMicPermission && appState.isModelReady {
                Button("Get Started") {
                    // Setup complete, ContentView will switch to MainView
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            Log.info("SetupView appeared, checking permissions...", category: .ui)
            await checkPermissions()
        }
        .onAppear {
            Log.info("SetupView onAppear - hasMic: \(appState.hasMicPermission), modelReady: \(appState.isModelReady)", category: .ui)
        }
    }

    private func checkPermissions() async {
        Log.debug("checkPermissions() called", category: .permissions)
        // Check mic permission (synchronous now)
        PermissionsManager.shared.checkMicPermission()
        let hasMic = PermissionsManager.shared.hasMicPermission
        micPermissionStatus = PermissionsManager.shared.getMicPermissionStatus()
        Log.info("checkPermissions result: hasMic=\(hasMic)", category: .permissions)
        appState.hasMicPermission = hasMic

        // Check if model already exists on disk and load it
        if !appState.isModelReady && !appState.isModelDownloading {
            Log.debug("Checking if model exists on disk...", category: .transcription)
            if TranscriptionService.shared.isReady {
                Log.info("Model already loaded", category: .transcription)
                appState.isModelReady = true
            } else {
                // Check if files exist and auto-load
                await checkAndLoadExistingModel()
            }
        }
    }

    private func checkAndLoadExistingModel() async {
        // Check if model files exist on disk
        let modelPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml")

        guard let path = modelPath, FileManager.default.fileExists(atPath: path.path) else {
            Log.debug("Model not found on disk", category: .transcription)
            return
        }

        Log.info("Model found on disk, loading...", category: .transcription)
        appState.isModelDownloading = true
        appState.modelDownloadProgress = 0.5 // Show as "loading" not "downloading"

        do {
            try await TranscriptionService.shared.prepare { progress in
                Task { @MainActor in
                    // Map progress to 50-100% range since we're loading, not downloading
                    appState.modelDownloadProgress = 0.5 + (progress * 0.5)
                }
            }
            Log.info("Model loaded from disk!", category: .transcription)
            appState.isModelReady = true
        } catch {
            Log.error("Failed to load model: \(error)", category: .transcription)
        }

        appState.isModelDownloading = false
    }

    private func requestMicPermission() {
        Log.info("requestMicPermission() button pressed", category: .permissions)
        Task {
            let status = await PermissionsManager.shared.requestMicPermission()
            Log.info("requestMicPermission result: \(status)", category: .permissions)
            micPermissionStatus = status
            appState.hasMicPermission = (status == .granted)
        }
    }

    private func downloadModel() {
        guard !appState.isModelDownloading else {
            Log.debug("downloadModel() called but already downloading", category: .transcription)
            return
        }

        Log.info("Starting model download...", category: .transcription)

        Task {
            appState.isModelDownloading = true
            appState.modelDownloadProgress = 0

            do {
                try await TranscriptionService.shared.prepare { progress in
                    Task { @MainActor in
                        appState.modelDownloadProgress = progress
                        if Int(progress * 100) % 10 == 0 {
                            Log.debug("Model download progress: \(Int(progress * 100))%", category: .transcription)
                        }
                    }
                }
                Log.info("Model download/load complete!", category: .transcription)
                appState.isModelReady = true
            } catch {
                Log.error("Model download failed: \(error)", category: .transcription)
            }

            appState.isModelDownloading = false
        }
    }
}

struct SetupStepView: View {
    let icon: String
    let title: String
    let description: String
    let isComplete: Bool
    var isLoading: Bool = false
    var progress: Double = 0
    let action: () -> Void
    var micPermissionStatus: PermissionsManager.PermissionStatus? = nil

    var body: some View {
        HStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(isComplete ? .green : .secondary.opacity(0.2))
                    .frame(width: 40, height: 40)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if micPermissionStatus == .denied {
                    Text("Microphone access is denied. Please grant it in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if micPermissionStatus == .restricted {
                    Text("Microphone access is restricted by your organization.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isLoading && progress > 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)

                    Text(progressText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Action Button
            if !isComplete && !isLoading {
                Button(action: {
                    if micPermissionStatus == .denied || micPermissionStatus == .restricted {
                        PermissionsManager.shared.openMicrophoneSettings()
                    } else {
                        action()
                    }
                }) {
                    Text(buttonText)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var buttonText: String {
        if icon.contains("mic") {
            if micPermissionStatus == .denied || micPermissionStatus == .restricted {
                return "Open Settings"
            }
            return "Grant Access"
        } else {
            return "Download"
        }
    }

    private var progressText: String {
        let percent = Int(progress * 100)
        if progress < 0.5 {
            return "Downloading... \(percent)%"
        } else {
            return "Loading model... \(percent)%"
        }
    }
}

#Preview {
    SetupView()
        .environment(AppState())
        .frame(width: 600, height: 500)
}
