import Foundation

/// A recording session containing transcript lines
@Observable
final class Session: Identifiable {
    let id: UUID
    var name: String
    let startTime: Date
    var endTime: Date?
    var lines: [TranscriptLine]

    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    var isActive: Bool {
        endTime == nil
    }

    var preview: String {
        guard let firstLine = lines.first else { return "" }
        let text = firstLine.text
        if text.count <= 50 {
            return text
        }
        return String(text.prefix(47)) + "..."
    }

    var displayName: String {
        name.isEmpty ? relativeTimeString : name
    }

    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: startTime, relativeTo: Date())
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }

    init(
        id: UUID = UUID(),
        name: String? = nil,
        startTime: Date = Date(),
        endTime: Date? = nil,
        lines: [TranscriptLine] = []
    ) {
        self.id = id
        self.name = name ?? Self.defaultName(for: startTime)
        self.startTime = startTime
        self.endTime = endTime
        self.lines = lines
    }

    private static func defaultName(for date: Date) -> String {
        ""
    }

    /// Add a line in timestamp-sorted order
    func addLine(_ line: TranscriptLine) {
        // Find the correct insertion point based on timestamp
        let insertIndex = lines.firstIndex { $0.timestamp > line.timestamp } ?? lines.endIndex
        Log.info("Session.addLine [\(line.speaker.displayLabel)] at index \(insertIndex) of \(lines.count), id:\(line.id.uuidString.prefix(8))", category: .transcription)
        lines.insert(line, at: insertIndex)
        Log.info("Session.addLine complete - now \(lines.count) lines", category: .transcription)
    }

    /// Update the most recent line for a given speaker
    func updateLastLine(with text: String, for speaker: SpeakerID) {
        guard let lastIndex = lines.lastIndex(where: { $0.speaker == speaker }) else {
            Log.warning("Session.updateLastLine - no line found for \(speaker.displayLabel)", category: .transcription)
            return
        }
        lines[lastIndex].text = text
        Log.debug("Session.updateLastLine [\(speaker.displayLabel)] at index \(lastIndex)", category: .transcription)
    }

    /// Find a line by ID
    func findLine(byId id: UUID) -> TranscriptLine? {
        let found = lines.first { $0.id == id }
        if found == nil {
            Log.debug("Session.findLine - id:\(id.uuidString.prefix(8)) NOT FOUND in \(lines.count) lines", category: .transcription)
        }
        return found
    }

    /// Update a specific line by ID
    func updateLine(id: UUID, text: String) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            Log.warning("Session.updateLine - id:\(id.uuidString.prefix(8)) NOT FOUND", category: .transcription)
            return
        }
        lines[index].text = text
        Log.debug("Session.updateLine at index \(index)", category: .transcription)
    }

    func stop() {
        endTime = Date()
    }
}

extension Session: Equatable {
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}

extension Session: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
