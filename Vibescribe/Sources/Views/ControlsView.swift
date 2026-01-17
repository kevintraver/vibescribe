import SwiftUI

struct ControlsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 16) {
            // Recording State Indicator
            HStack(spacing: 8) {
                RecordingIndicator(state: appState.recordingState)

                Text(appState.recordingState.displayText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let session = appState.currentSession {
                    // Use TimelineView to update the duration every second
                    TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                        Text(session.formattedDuration)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minWidth: 120, alignment: .leading)

            Spacer()

            // Control Buttons
            HStack(spacing: 12) {
                switch appState.recordingState {
                case .idle:
                    RecordButton {
                        appState.showingStartRecordingDialog = true
                    }

                case .recording:
                    PauseButton {
                        appState.pauseRecording()
                        TranscriptionService.shared.pauseRecording()
                    }

                    StopButton {
                        appState.beginStopping()
                        Task {
                            await TranscriptionService.shared.stopRecording()
                            appState.finalizeStopRecording()
                        }
                    }

                case .paused:
                    ResumeButton {
                        appState.resumeRecording()
                        TranscriptionService.shared.resumeRecording()
                    }

                    StopButton {
                        appState.beginStopping()
                        Task {
                            await TranscriptionService.shared.stopRecording()
                            appState.finalizeStopRecording()
                        }
                    }

                case .stopping:
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .frame(height: 44)
    }
}

struct RecordingIndicator: View {
    let state: RecordingState
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 12, height: 12)
            .scaleEffect(isAnimating && state == .recording ? 1.2 : 1.0)
            .animation(
                state == .recording
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }

    private var indicatorColor: Color {
        switch state {
        case .recording: return .red
        case .paused: return .orange
        default: return .gray
        }
    }
}

struct RecordButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Record", systemImage: "record.circle")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
    }
}

struct PauseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Pause", systemImage: "pause.fill")
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .controlSize(.large)
    }
}

struct ResumeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Resume", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
    }
}

struct StopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .controlSize(.large)
    }
}

#Preview("Idle") {
    let appState = AppState()
    appState.recordingState = .idle

    return ControlsView()
        .environment(appState)
        .padding()
}

#Preview("Recording") {
    let appState = AppState()
    appState.recordingState = .recording
    appState.currentSession = Session()

    return ControlsView()
        .environment(appState)
        .padding()
}

#Preview("Paused") {
    let appState = AppState()
    appState.recordingState = .paused
    appState.currentSession = Session()

    return ControlsView()
        .environment(appState)
        .padding()
}
