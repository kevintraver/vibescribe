import Foundation

/// Result from a transcription operation
struct TranscriptionResult: Sendable {
    let text: String
    let confidence: Float
    let source: TranscriptSource
    let timestamp: Date

    init(
        text: String,
        confidence: Float = 1.0,
        source: TranscriptSource,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.confidence = confidence
        self.source = source
        self.timestamp = timestamp
    }
}
