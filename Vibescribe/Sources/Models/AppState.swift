import SwiftUI

/// Global application state
@MainActor
@Observable
final class AppState {
    // MARK: - Recording State

    var recordingState: RecordingState = .idle
    var currentSession: Session?
    var sessions: [Session] = []

    // MARK: - Model State

    var isModelReady: Bool = false
    var isModelDownloading: Bool = false
    var modelDownloadProgress: Double = 0.0

    // MARK: - Permissions

    var hasMicPermission: Bool = false
    var hasScreenPermission: Bool = false

    // MARK: - UI State

    var selectedSessionId: UUID?
    var showingStartRecordingDialog: Bool = false
    var showingSettings: Bool = false
    var toastMessage: String?
    var showingSessionWarning: Bool = false
    var showingCrashRecovery: Bool = false
    var recoveredSession: Session?

    // MARK: - Audio Sources

    var selectedMicId: String? {
        didSet {
            SettingsManager.shared.lastMicUID = selectedMicId
        }
    }
    var selectedAppBundleId: String? {
        didSet {
            SettingsManager.shared.lastAppBundleId = selectedAppBundleId
        }
    }

    // MARK: - Settings

    var silenceDuration: Double = 0.8 {
        didSet {
            SettingsManager.shared.silenceDuration = silenceDuration
            TranscriptionService.shared.updateSilenceDuration(silenceDuration)
        }
    }
    var silenceThreshold: Double = 0.008 {
        didSet {
            SettingsManager.shared.silenceThreshold = silenceThreshold
            TranscriptionService.shared.updateSilenceThreshold(Float(silenceThreshold))
        }
    }
    var alwaysOnTop: Bool = false {
        didSet {
            SettingsManager.shared.alwaysOnTop = alwaysOnTop
        }
    }
    var bringToFrontOnHotkey: Bool = true {
        didSet {
            SettingsManager.shared.bringToFrontOnHotkey = bringToFrontOnHotkey
        }
    }

    // MARK: - Session Timer

    private var sessionTimer: Timer?
    private let sessionWarningThreshold: TimeInterval = 3600 // 1 hour

    // MARK: - Initialization

    init() {
        loadSettings()
        loadSessions()
    }

    // MARK: - Computed Properties

    var selectedSession: Session? {
        guard let id = selectedSessionId else {
            return currentSession ?? sessions.first
        }
        if currentSession?.id == id {
            return currentSession
        }
        return sessions.first { $0.id == id }
    }

    var canStartRecording: Bool {
        isModelReady && hasMicPermission && recordingState.canStart
    }

    var needsSetup: Bool {
        !isModelReady || !hasMicPermission
    }

    // MARK: - Methods

    func startNewSession() {
        let session = Session()
        currentSession = session
        recordingState = .recording
        selectedSessionId = session.id

        // Persist session immediately
        DatabaseManager.shared.saveSession(session)
        EventLogger.shared.log(.recordingStart, sessionId: session.id)

        // Start session duration timer
        startSessionTimer()
    }

    func pauseRecording() {
        guard recordingState.canPause else { return }
        recordingState = .paused
        if let session = currentSession {
            EventLogger.shared.log(.recordingPause, sessionId: session.id)
        }
    }

    func resumeRecording() {
        guard recordingState.canResume else { return }
        recordingState = .recording
        if let session = currentSession {
            EventLogger.shared.log(.recordingResume, sessionId: session.id)
        }
    }

    func stopRecording() {
        guard recordingState.canStop else { return }
        recordingState = .stopping

        // Stop session timer
        stopSessionTimer()
        showingSessionWarning = false

        if let session = currentSession {
            session.stop()
            EventLogger.shared.log(.recordingStop, sessionId: session.id)

            // Only keep sessions longer than 3 seconds
            if session.duration >= 3.0 {
                sessions.insert(session, at: 0)
                DatabaseManager.shared.saveSession(session)
            } else {
                // Delete short sessions from database
                DatabaseManager.shared.deleteSession(session.id)
            }
        }

        currentSession = nil
        recordingState = .idle
    }

    func addLine(_ line: TranscriptLine) {
        currentSession?.addLine(line)
        DatabaseManager.shared.saveLine(line)
    }

    func updateLine(_ line: TranscriptLine) {
        DatabaseManager.shared.updateLine(line)
    }

    func showToast(_ message: String) {
        toastMessage = message

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        if selectedSessionId == session.id {
            selectedSessionId = sessions.first?.id
        }
        DatabaseManager.shared.deleteSession(session.id)
    }

    // MARK: - Persistence

    private func loadSettings() {
        let settings = SettingsManager.shared
        silenceDuration = settings.silenceDuration
        silenceThreshold = settings.silenceThreshold
        alwaysOnTop = settings.alwaysOnTop
        bringToFrontOnHotkey = settings.bringToFrontOnHotkey
        selectedMicId = settings.lastMicUID
        selectedAppBundleId = settings.lastAppBundleId
    }

    private func loadSessions() {
        sessions = DatabaseManager.shared.loadSessions(limit: 50)
        selectedSessionId = sessions.first?.id
    }

    func loadMoreSessions() {
        let moreSessions = DatabaseManager.shared.loadSessions(limit: 50, offset: sessions.count)
        sessions.append(contentsOf: moreSessions)
    }

    // MARK: - Crash Recovery

    func checkForCrashRecovery() {
        if let unclosedSession = DatabaseManager.shared.findUnclosedSession() {
            recoveredSession = unclosedSession
            showingCrashRecovery = true
        }
    }

    func acceptCrashRecovery() {
        if let session = recoveredSession {
            // Close the session and add to list
            DatabaseManager.shared.closeSession(session.id, endTime: Date())
            session.stop()
            if !sessions.contains(where: { $0.id == session.id }) {
                sessions.insert(session, at: 0)
            }
            selectedSessionId = session.id
        }
        recoveredSession = nil
        showingCrashRecovery = false
    }

    func dismissCrashRecovery() {
        if let session = recoveredSession {
            // Delete the incomplete session
            DatabaseManager.shared.deleteSession(session.id)
        }
        recoveredSession = nil
        showingCrashRecovery = false
    }

    // MARK: - Session Timer

    private func startSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSessionDuration()
            }
        }
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    private func checkSessionDuration() {
        guard let session = currentSession else { return }
        if session.duration >= sessionWarningThreshold && !showingSessionWarning {
            showingSessionWarning = true
        }
    }

    func dismissSessionWarning() {
        showingSessionWarning = false
    }

    // MARK: - Hotkey

    func toggleRecording() {
        switch recordingState {
        case .idle:
            showingStartRecordingDialog = true
        case .recording:
            pauseRecording()
        case .paused:
            resumeRecording()
        case .stopping:
            break
        }
    }
}
