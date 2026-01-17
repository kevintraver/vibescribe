import Foundation

/// The current state of the recording
enum RecordingState: Sendable {
    case idle       // Not recording, ready to start
    case recording  // Capturing and transcribing audio
    case paused     // Capture stopped, session still open
    case stopping   // Finalizing session (brief transition)

    var isCapturing: Bool {
        self == .recording
    }

    var canStart: Bool {
        self == .idle
    }

    var canPause: Bool {
        self == .recording
    }

    var canResume: Bool {
        self == .paused
    }

    var canStop: Bool {
        self == .recording || self == .paused
    }

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .stopping: return "Stopping"
        }
    }
}
