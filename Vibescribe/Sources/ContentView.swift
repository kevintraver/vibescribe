import SwiftUI
import AVFoundation
import AppKit

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var isCheckingSetup = true
    @State private var windowObserver: WindowObserver?
    @State private var window: NSWindow?

    var body: some View {
        Group {
            if isCheckingSetup {
                // Brief loading state while checking permissions and model
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.needsSetup {
                SetupView()
            } else {
                MainView()
            }
        }
        .background(
            WindowAccessor { window in
                if self.window !== window {
                    self.window = window
                    configureWindow(window)
                    windowObserver = WindowObserver(window: window)
                }
            }
        )
        .onChange(of: appState.alwaysOnTop) { _, newValue in
            updateWindowLevel(alwaysOnTop: newValue)
        }
        .task {
            // Connect AppState to TranscriptionService
            TranscriptionService.shared.setAppState(appState)

            // Check permissions and model before deciding which view to show
            await checkInitialState()
            isCheckingSetup = false
        }
    }

    private func checkInitialState() async {
        Log.debug("checkInitialState() START", category: .general)

        // Check mic permission (quick synchronous check)
        Log.debug("Checking mic permission...", category: .permissions)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let hasMic = status == .authorized
        appState.hasMicPermission = hasMic
        Log.info("Mic permission: \(hasMic) (status: \(status.rawValue))", category: .permissions)

        // Check if model is ready or can be loaded from disk
        Log.debug("Checking TranscriptionService.shared.isReady...", category: .transcription)
        let isReady = TranscriptionService.shared.isReady
        Log.debug("TranscriptionService.shared.isReady = \(isReady)", category: .transcription)

        if isReady {
            Log.info("Model already ready", category: .transcription)
            appState.isModelReady = true
        } else {
            // Check if model files exist on disk
            Log.debug("Checking if model files exist on disk...", category: .transcription)
            let modelPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml")

            if let path = modelPath {
                let exists = FileManager.default.fileExists(atPath: path.path)
                Log.debug("Model path: \(path.path), exists: \(exists)", category: .transcription)

                if exists {
                    Log.info("Model found on disk, calling prepare()...", category: .transcription)
                    do {
                        // Call prepare directly - it's already async
                        try await TranscriptionService.shared.prepare(progressHandler: nil)
                        appState.isModelReady = true
                        Log.info("Model loaded successfully!", category: .transcription)
                    } catch {
                        Log.error("Failed to load model: \(error)", category: .transcription)
                    }
                } else {
                    Log.debug("Model not found on disk", category: .transcription)
                }
            } else {
                Log.error("Could not get Application Support directory", category: .transcription)
            }
        }

        Log.info("checkInitialState() END - needsSetup: \(appState.needsSetup)", category: .general)
    }

    private func configureWindow(_ window: NSWindow) {
        if let frame = SettingsManager.shared.windowFrame {
            window.setFrame(frame, display: true)
        }
        applyWindowLevel(window, alwaysOnTop: appState.alwaysOnTop)
    }

    private func updateWindowLevel(alwaysOnTop: Bool) {
        guard let window else { return }
        applyWindowLevel(window, alwaysOnTop: alwaysOnTop)
    }

    private func applyWindowLevel(_ window: NSWindow, alwaysOnTop: Bool) {
        window.level = alwaysOnTop ? .floating : .normal
    }
}

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 150, idealWidth: 150, maxWidth: 200)
        } detail: {
            DetailView()
        }
        .overlay(alignment: .bottom) {
            if let message = appState.toastMessage {
                ToastView(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.toastMessage)
        .sheet(isPresented: Binding(
            get: { appState.showingStartRecordingDialog },
            set: { appState.showingStartRecordingDialog = $0 }
        )) {
            StartRecordingDialog()
        }
        .alert("Long Recording Session", isPresented: Binding(
            get: { appState.showingSessionWarning },
            set: { _ in appState.dismissSessionWarning() }
        )) {
            Button("Continue Recording") {
                appState.dismissSessionWarning()
            }
            Button("Stop Recording", role: .destructive) {
                appState.beginStopping()
                Task {
                    await TranscriptionService.shared.stopRecording()
                    appState.finalizeStopRecording()
                }
            }
        } message: {
            Text("Your recording has been running for over 1 hour. Consider saving and starting a new session to prevent data loss.")
        }
        .alert("Permission Change Detected", isPresented: Binding(
            get: { appState.showingPermissionAlert },
            set: { _ in appState.dismissPermissionAlert() }
        )) {
            Button("OK") {
                appState.dismissPermissionAlert()
            }
        } message: {
            Text(appState.permissionAlertMessage ?? "Recording permissions changed.")
        }
        .sheet(isPresented: Binding(
            get: { appState.showingCrashRecovery },
            set: { _ in }
        )) {
            CrashRecoveryDialog()
        }
        .onExitCommand {
            guard appState.recordingState.canStop else { return }
            appState.beginStopping()
            Task {
                await TranscriptionService.shared.stopRecording()
                appState.finalizeStopRecording()
            }
        }
    }
}

struct CrashRecoveryDialog: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Session Recovered")
                .font(.title2)
                .fontWeight(.semibold)

            if let session = appState.recoveredSession {
                VStack(spacing: 8) {
                    Text("A previous recording session was not properly closed.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("\(session.lines.count) lines from \(session.formattedDate)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                Button("Discard") {
                    appState.dismissCrashRecovery()
                }
                .buttonStyle(.bordered)

                Button("Keep Session") {
                    appState.acceptCrashRecovery()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

struct DetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Prominent recording indicator at top center
            if appState.recordingState == .recording || appState.recordingState == .paused {
                RecordingBanner(state: appState.recordingState, session: appState.currentSession)
            }

            if let session = appState.selectedSession {
                TranscriptView(session: session)
            } else {
                EmptyStateView()
            }

            Divider()

            ControlsView()
                .padding()
        }
    }
}

struct RecordingBanner: View {
    let state: RecordingState
    let session: Session?
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing indicator
            Circle()
                .fill(state == .recording ? Color.red : Color.orange)
                .frame(width: 14, height: 14)
                .scaleEffect(isAnimating && state == .recording ? 1.3 : 1.0)
                .animation(
                    state == .recording
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: isAnimating
                )

            Text(state == .recording ? "Recording" : "Paused")
                .font(.headline)
                .foregroundStyle(state == .recording ? .red : .orange)

            if let session {
                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                    Text(session.formattedDuration)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 12)
        .padding(.bottom, 8)
        .onAppear {
            isAnimating = true
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Session Selected")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Start a new recording or select a past session from the sidebar.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4)
            .padding(.bottom, 20)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 600, height: 500)
}

private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}

private final class WindowObserver {
    private weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeFrame),
            name: NSWindow.didMoveNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeFrame),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidChangeFrame(_ notification: Notification) {
        guard let window else { return }
        SettingsManager.shared.windowFrame = window.frame
    }
}
