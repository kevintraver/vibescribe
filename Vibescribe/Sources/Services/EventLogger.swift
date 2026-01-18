import Foundation

/// Event types for logging
enum EventType: String, Codable {
    case appLaunch = "app_launch"
    case appTerminate = "app_terminate"
    case recordingStart = "recording_start"
    case recordingPause = "recording_pause"
    case recordingResume = "recording_resume"
    case recordingStop = "recording_stop"
    case transcriptionError = "transcription_error"
    case audioError = "audio_error"
    case permissionDenied = "permission_denied"
    case modelDownload = "model_download"
    case sessionWarning = "session_warning"
}

/// A logged event
struct LogEvent: Codable {
    let timestamp: Date
    let type: EventType
    let sessionId: UUID?
    let message: String?

    init(type: EventType, sessionId: UUID? = nil, message: String? = nil) {
        self.timestamp = Date()
        self.type = type
        self.sessionId = sessionId
        self.message = message
    }
}

/// Manages structured event logging for diagnostics and crash recovery
final class EventLogger: @unchecked Sendable {
    static let shared = EventLogger()

    private let logQueue = DispatchQueue(label: "com.vibescribe.eventlogger", qos: .utility)
    private var logFileHandle: FileHandle?
    private let logFilePath: URL
    private let encoder = JSONEncoder()

    private init() {
        // Set up log file path
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Failed to get Application Support directory")
        }

        let vibescribeDir = appSupport.appendingPathComponent("VibeScribe")
        try? fileManager.createDirectory(at: vibescribeDir, withIntermediateDirectories: true)

        logFilePath = vibescribeDir.appendingPathComponent("events.jsonl")

        // Create file if needed
        if !fileManager.fileExists(atPath: logFilePath.path) {
            fileManager.createFile(atPath: logFilePath.path, contents: nil)
        }

        // Open file handle
        logFileHandle = try? FileHandle(forWritingTo: logFilePath)
        logFileHandle?.seekToEndOfFile()

        encoder.dateEncodingStrategy = .iso8601
    }

    deinit {
        try? logFileHandle?.close()
    }

    // MARK: - Logging

    func log(_ type: EventType, sessionId: UUID? = nil, message: String? = nil) {
        let event = LogEvent(type: type, sessionId: sessionId, message: message)

        logQueue.async { [weak self] in
            guard let self, let handle = self.logFileHandle else { return }

            do {
                let data = try self.encoder.encode(event)
                handle.write(data)
                handle.write("\n".data(using: .utf8)!)

                // Sync to disk for crash safety
                try handle.synchronize()
            } catch {
                print("Failed to write log event: \(error)")
            }
        }
    }

    // MARK: - Crash Detection

    /// Check if the last session was not properly closed (crash indicator)
    func checkForCrash() -> (crashed: Bool, sessionId: UUID?) {
        // Look for a recording_start without a corresponding recording_stop
        let events = readRecentEvents(count: 100)

        var lastStartSessionId: UUID?
        var lastStopSessionId: UUID?

        for event in events.reversed() {
            switch event.type {
            case .recordingStart:
                if lastStartSessionId == nil {
                    lastStartSessionId = event.sessionId
                }
            case .recordingStop:
                if lastStopSessionId == nil {
                    lastStopSessionId = event.sessionId
                }
            case .appTerminate:
                // Normal termination, no crash
                return (false, nil)
            default:
                break
            }
        }

        // If we have a start without a matching stop, it's likely a crash
        if let startId = lastStartSessionId {
            if lastStopSessionId != startId {
                return (true, startId)
            }
        }

        return (false, nil)
    }

    /// Read recent events from the log file
    func readRecentEvents(count: Int) -> [LogEvent] {
        var events: [LogEvent] = []

        logQueue.sync { [weak self] in
            guard let self else { return }

            do {
                let data = try Data(contentsOf: self.logFilePath)
                let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let recentLines = lines.suffix(count)
                for line in recentLines where !line.isEmpty {
                    if let lineData = line.data(using: .utf8),
                       let event = try? decoder.decode(LogEvent.self, from: lineData) {
                        events.append(event)
                    }
                }
            } catch {
                print("Failed to read events: \(error)")
            }
        }

        return events
    }

    /// Clear the log file
    func clearLogs() {
        logQueue.async { [weak self] in
            guard let self else { return }

            try? self.logFileHandle?.close()
            try? FileManager.default.removeItem(at: self.logFilePath)
            FileManager.default.createFile(atPath: self.logFilePath.path, contents: nil)
            self.logFileHandle = try? FileHandle(forWritingTo: self.logFilePath)
        }
    }

    /// Get log file size
    func getLogFileSize() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFilePath.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    /// Export logs for diagnostics
    func exportLogs() -> URL? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let exportPath = tempDir.appendingPathComponent("vibescribe-logs-\(Date().timeIntervalSince1970).jsonl")

        do {
            try fileManager.copyItem(at: logFilePath, to: exportPath)
            return exportPath
        } catch {
            print("Failed to export logs: \(error)")
            return nil
        }
    }
}
