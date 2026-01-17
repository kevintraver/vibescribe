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
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func addLine(_ line: TranscriptLine) {
        lines.append(line)
    }

    func updateLastLine(with text: String, for source: TranscriptSource) {
        guard let lastIndex = lines.lastIndex(where: { $0.source == source }) else { return }
        lines[lastIndex].text = text
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
