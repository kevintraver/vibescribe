import Foundation
import SwiftUI

/// Represents the speaker identity for a transcript line
/// - `.you`: Microphone input - always the local user
/// - `.remote(speakerIndex)`: App audio with speaker diarization (0-3 from Sortformer)
enum SpeakerID: Codable, Hashable, Sendable {
    case you                           // Mic - always single speaker
    case remote(speakerIndex: Int)     // App audio - 0, 1, 2, 3 from Sortformer

    var displayLabel: String {
        switch self {
        case .you:
            return "You"
        case .remote(let idx):
            return "Remote \(idx + 1)"
        }
    }

    /// Color for UI display
    var color: Color {
        switch self {
        case .you:
            return .blue
        case .remote(let idx):
            let colors: [Color] = [.green, .orange, .purple, .pink]
            return colors[idx % colors.count]
        }
    }

    /// Check if this is the local user
    var isYou: Bool {
        if case .you = self { return true }
        return false
    }

    /// Check if this is remote audio
    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }
}

/// Legacy source type for audio pipeline (not for transcript storage)
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

    /// Convert to SpeakerID (remote defaults to speaker 0)
    func toSpeakerID(speakerIndex: Int = 0) -> SpeakerID {
        switch self {
        case .you: return .you
        case .remote: return .remote(speakerIndex: speakerIndex)
        }
    }
}
