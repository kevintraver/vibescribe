import Foundation

/// Result from a transcription operation
struct TranscriptionResult: Sendable {
    let text: String
    let confidence: Float
    let speaker: SpeakerID
    let timestamp: Date

    init(
        text: String,
        confidence: Float = 1.0,
        speaker: SpeakerID,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.confidence = confidence
        self.speaker = speaker
        self.timestamp = timestamp
    }
}
