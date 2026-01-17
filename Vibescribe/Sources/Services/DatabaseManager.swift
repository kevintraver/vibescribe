import Foundation
import SQLite3

/// Manages SQLite database for session and transcript persistence
final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.vibescribe.database", qos: .userInitiated)

    private init() {
        setupDatabase()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Setup

    private func setupDatabase() {
        let fileManager = FileManager.default

        // Create app support directory if needed
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("Failed to get Application Support directory")
            return
        }

        let vibescribeDir = appSupport.appendingPathComponent("Vibescribe")

        do {
            try fileManager.createDirectory(at: vibescribeDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create Vibescribe directory: \(error)")
            return
        }

        let dbPath = vibescribeDir.appendingPathComponent("vibescribe.db").path

        // Open database
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
            return
        }

        // Enable WAL mode for better concurrent access
        execute("PRAGMA journal_mode = WAL")

        // Create tables
        createTables()
    }

    private func createTables() {
        // Sessions table
        execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL,
                created_at REAL NOT NULL
            )
        """)

        // Transcript lines table
        execute("""
            CREATE TABLE IF NOT EXISTS transcript_lines (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                text TEXT NOT NULL,
                source TEXT NOT NULL,
                timestamp REAL NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
        """)

        // Create indexes
        execute("CREATE INDEX IF NOT EXISTS idx_lines_session ON transcript_lines(session_id)")
        execute("CREATE INDEX IF NOT EXISTS idx_lines_timestamp ON transcript_lines(timestamp)")
        execute("CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start_time DESC)")
    }

    // MARK: - Session Operations

    func saveSession(_ session: Session) {
        dbQueue.async { [weak self] in
            guard let self, let db = self.db else { return }

            let sql = """
                INSERT OR REPLACE INTO sessions (id, name, start_time, end_time, created_at)
                VALUES (?, ?, ?, ?, ?)
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, session.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, session.name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(statement, 3, session.startTime.timeIntervalSince1970)

                if let endTime = session.endTime {
                    sqlite3_bind_double(statement, 4, endTime.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(statement, 4)
                }

                sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)

                if sqlite3_step(statement) != SQLITE_DONE {
                    print("Failed to save session: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(statement)
        }
    }

    func saveLine(_ line: TranscriptLine) {
        dbQueue.async { [weak self] in
            guard let self, let db = self.db else { return }

            let sql = """
                INSERT OR REPLACE INTO transcript_lines (id, session_id, text, source, timestamp, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, line.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, line.sessionId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, line.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, line.source.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(statement, 5, line.timestamp.timeIntervalSince1970)
                sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)

                if sqlite3_step(statement) != SQLITE_DONE {
                    print("Failed to save line: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(statement)
        }
    }

    func updateLine(_ line: TranscriptLine) {
        dbQueue.async { [weak self] in
            guard let self, let db = self.db else { return }

            let sql = "UPDATE transcript_lines SET text = ? WHERE id = ?"

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, line.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, line.id.uuidString, -1, SQLITE_TRANSIENT)

                if sqlite3_step(statement) != SQLITE_DONE {
                    print("Failed to update line: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(statement)
        }
    }

    func loadSessions(limit: Int = 50, offset: Int = 0) -> [Session] {
        var sessions: [Session] = []

        dbQueue.sync { [weak self] in
            guard let self, let db = self.db else { return }

            let sql = """
                SELECT id, name, start_time, end_time
                FROM sessions
                ORDER BY start_time DESC
                LIMIT ? OFFSET ?
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(limit))
                sqlite3_bind_int(statement, 2, Int32(offset))

                while sqlite3_step(statement) == SQLITE_ROW {
                    if let session = self.sessionFromRow(statement) {
                        sessions.append(session)
                    }
                }
            }
            sqlite3_finalize(statement)
        }

        // Load lines for each session
        for session in sessions {
            let lines = loadLines(forSessionId: session.id)
            for line in lines {
                session.lines.append(line)
            }
        }

        return sessions
    }

    func loadLines(forSessionId sessionId: UUID) -> [TranscriptLine] {
        var lines: [TranscriptLine] = []

        dbQueue.sync { [weak self] in
            guard let self, let db = self.db else { return }

            let sql = """
                SELECT id, session_id, text, source, timestamp
                FROM transcript_lines
                WHERE session_id = ?
                ORDER BY timestamp ASC
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)

                while sqlite3_step(statement) == SQLITE_ROW {
                    if let line = self.lineFromRow(statement) {
                        lines.append(line)
                    }
                }
            }
            sqlite3_finalize(statement)
        }

        return lines
    }

    func deleteSession(_ sessionId: UUID) {
        dbQueue.async { [weak self] in
            guard let self, let db = self.db else { return }

            // Delete lines first (cascade should handle this, but be explicit)
            var sql = "DELETE FROM transcript_lines WHERE session_id = ?"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)

            // Delete session
            sql = "DELETE FROM sessions WHERE id = ?"
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    func getSessionCount() -> Int {
        var count = 0

        dbQueue.sync { [weak self] in
            guard let self, let db = self.db else { return }

            let sql = "SELECT COUNT(*) FROM sessions"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(statement, 0))
                }
            }
            sqlite3_finalize(statement)
        }

        return count
    }

    func getDatabaseSize() -> Int64 {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return 0
        }

        let dbPath = appSupport.appendingPathComponent("Vibescribe/vibescribe.db")

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: dbPath.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    // MARK: - Crash Recovery

    func findUnclosedSession() -> Session? {
        var session: Session?

        dbQueue.sync { [weak self] in
            guard let self, let db = self.db else { return }

            // Only return sessions that have at least one transcript line
            let sql = """
                SELECT s.id, s.name, s.start_time, s.end_time
                FROM sessions s
                WHERE s.end_time IS NULL
                  AND EXISTS (SELECT 1 FROM transcript_lines WHERE session_id = s.id)
                ORDER BY s.start_time DESC
                LIMIT 1
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    session = self.sessionFromRow(statement)
                }
            }
            sqlite3_finalize(statement)
        }

        if let session {
            let lines = loadLines(forSessionId: session.id)
            for line in lines {
                session.lines.append(line)
            }
        }

        return session
    }

    /// Close all unclosed sessions (used on app termination)
    func closeAllUnclosedSessions() {
        dbQueue.sync { [weak self] in
            guard let self, let db = self.db else { return }

            let now = Date().timeIntervalSince1970

            // Close sessions with content
            let closeSql = """
                UPDATE sessions SET end_time = ?
                WHERE end_time IS NULL
                  AND EXISTS (SELECT 1 FROM transcript_lines WHERE session_id = sessions.id)
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, closeSql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_double(statement, 1, now)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)

            // Delete empty sessions
            let deleteSql = """
                DELETE FROM sessions
                WHERE end_time IS NULL
                  AND NOT EXISTS (SELECT 1 FROM transcript_lines WHERE session_id = sessions.id)
            """

            var deleteStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStatement, nil) == SQLITE_OK {
                sqlite3_step(deleteStatement)
            }
            sqlite3_finalize(deleteStatement)
        }
    }

    func closeSession(_ sessionId: UUID, endTime: Date) {
        dbQueue.async { [weak self] in
            guard let self, let db = self.db else { return }

            let sql = "UPDATE sessions SET end_time = ? WHERE id = ?"

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_double(statement, 1, endTime.timeIntervalSince1970)
                sqlite3_bind_text(statement, 2, sessionId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Helpers

    private func sessionFromRow(_ statement: OpaquePointer?) -> Session? {
        guard let statement else { return nil }

        guard let idStr = sqlite3_column_text(statement, 0),
              let nameStr = sqlite3_column_text(statement, 1) else {
            return nil
        }

        guard let id = UUID(uuidString: String(cString: idStr)) else {
            return nil
        }

        let name = String(cString: nameStr)
        let startTime = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))

        var endTime: Date?
        if sqlite3_column_type(statement, 3) != SQLITE_NULL {
            endTime = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        }

        return Session(
            id: id,
            name: name,
            startTime: startTime,
            endTime: endTime,
            lines: []
        )
    }

    private func lineFromRow(_ statement: OpaquePointer?) -> TranscriptLine? {
        guard let statement else { return nil }

        guard let idStr = sqlite3_column_text(statement, 0),
              let sessionIdStr = sqlite3_column_text(statement, 1),
              let textStr = sqlite3_column_text(statement, 2),
              let sourceStr = sqlite3_column_text(statement, 3) else {
            return nil
        }

        guard let id = UUID(uuidString: String(cString: idStr)),
              let sessionId = UUID(uuidString: String(cString: sessionIdStr)),
              let source = TranscriptSource(rawValue: String(cString: sourceStr)) else {
            return nil
        }

        let text = String(cString: textStr)
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))

        return TranscriptLine(
            id: id,
            text: text,
            source: source,
            timestamp: timestamp,
            sessionId: sessionId
        )
    }

    private func execute(_ sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let result = sqlite3_step(statement)
            // SQLITE_DONE = statement completed, SQLITE_ROW = returned data (e.g., PRAGMA)
            if result != SQLITE_DONE && result != SQLITE_ROW {
                print("SQL execution failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        sqlite3_finalize(statement)
    }
}

// MARK: - SQLITE_TRANSIENT

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
