import Foundation

/// A single line of transcribed text
struct TranscriptLine: Identifiable, Codable, Sendable {
    let id: UUID
    var text: String
    let source: TranscriptSource
    let timestamp: Date
    let sessionId: UUID

    init(
        id: UUID = UUID(),
        text: String,
        source: TranscriptSource,
        timestamp: Date = Date(),
        sessionId: UUID
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.timestamp = timestamp
        self.sessionId = sessionId
    }
}

extension TranscriptLine: Equatable {
    static func == (lhs: TranscriptLine, rhs: TranscriptLine) -> Bool {
        lhs.id == rhs.id
    }
}

extension TranscriptLine: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
