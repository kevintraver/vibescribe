import Foundation

/// Represents the source of audio for transcription
/// Named TranscriptSource to avoid conflict with FluidAudio.AudioSource
enum TranscriptSource: String, Codable, Sendable {
    case you = "you"       // Microphone input
    case remote = "remote" // System audio from selected app

    var displayLabel: String {
        switch self {
        case .you: return "You"
        case .remote: return "Remote"
        }
    }
}
