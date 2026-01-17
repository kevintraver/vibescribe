import Foundation
import os.log

/// Simple logger for debugging
enum Log {
    private static let subsystem = "com.vibescribe"

    private static let general = Logger(subsystem: subsystem, category: "general")
    private static let permissions = Logger(subsystem: subsystem, category: "permissions")
    private static let audio = Logger(subsystem: subsystem, category: "audio")
    private static let transcription = Logger(subsystem: subsystem, category: "transcription")
    private static let ui = Logger(subsystem: subsystem, category: "ui")
    private static let db = Logger(subsystem: subsystem, category: "database")

    private static let logFile: FileHandle? = {
        let path = "/tmp/vibescribe.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    private static func log(_ message: String) {
        let timestamped = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        fputs(timestamped, stderr)
        fflush(stderr)
        // Also write to file
        if let data = timestamped.data(using: .utf8) {
            logFile?.write(data)
            try? logFile?.synchronize()
        }
    }

    static func info(_ message: String, category: Category = .general) {
        logger(for: category).info("✅ \(message)")
        log("[INFO] [\(category.rawValue)] \(message)")
    }

    static func debug(_ message: String, category: Category = .general) {
        logger(for: category).debug("🔍 \(message)")
        log("[DEBUG] [\(category.rawValue)] \(message)")
    }

    static func warning(_ message: String, category: Category = .general) {
        logger(for: category).warning("⚠️ \(message)")
        log("[WARN] [\(category.rawValue)] \(message)")
    }

    static func error(_ message: String, category: Category = .general) {
        logger(for: category).error("❌ \(message)")
        log("[ERROR] [\(category.rawValue)] \(message)")
    }

    enum Category: String {
        case general
        case permissions
        case audio
        case transcription
        case ui
        case database
    }

    private static func logger(for category: Category) -> Logger {
        switch category {
        case .general: return general
        case .permissions: return permissions
        case .audio: return audio
        case .transcription: return transcription
        case .ui: return ui
        case .database: return db
        }
    }
}
