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
    var showingPermissionAlert: Bool = false
    var permissionAlertMessage: String?

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
    var selectedAppName: String?

    /// Track unique remote speakers seen in current session (for display logic)
    var seenRemoteSpeakers: Set<Int> = []

    /// Track which lines are currently being transcribed (for visual indicator)
    var activeLineIds: Set<UUID> = []

    /// Get display label for a speaker, considering app name and multi-speaker context
    func speakerDisplayLabel(for speaker: SpeakerID) -> String {
        switch speaker {
        case .you:
            return "You"
        case .remote(let speakerIndex):
            // Get app name, falling back to bundle ID or extracting name from it
            let appName: String
            if let name = selectedAppName, !name.isEmpty {
                appName = name
            } else if let bundleId = selectedAppBundleId {
                // Extract app name from bundle ID (e.g., "com.apple.Music" -> "Music")
                appName = bundleId.components(separatedBy: ".").last ?? bundleId
            } else {
                appName = "App"
            }

            // If we've seen multiple speakers, show speaker number
            if seenRemoteSpeakers.count > 1 {
                return "\(appName) (Speaker \(speakerIndex + 1))"
            } else {
                return appName
            }
        }
    }

    /// Record that we've seen a remote speaker (call when transcription comes in)
    func recordRemoteSpeaker(_ speakerIndex: Int) {
        seenRemoteSpeakers.insert(speakerIndex)
    }

    // MARK: - Settings

    var silenceDuration: Double = 1.5 {
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
    private var nextSessionWarningThreshold: TimeInterval = 3600

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
        isModelReady && recordingState.canStart
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

        // Reset speaker tracking for new session
        seenRemoteSpeakers.removeAll()
        activeLineIds.removeAll()

        // Persist session immediately
        DatabaseManager.shared.saveSession(session)
        EventLogger.shared.log(.recordingStart, sessionId: session.id)

        // Start session duration timer
        nextSessionWarningThreshold = sessionWarningThreshold
        startSessionTimer()
    }

    func pauseRecording() {
        guard recordingState.canPause else { return }
        recordingState = .paused
        currentSession?.pause()
        if let session = currentSession {
            EventLogger.shared.log(.recordingPause, sessionId: session.id)
        }
    }

    func resumeRecording() {
        guard recordingState.canResume else { return }
        recordingState = .recording
        currentSession?.resume()
        if let session = currentSession {
            EventLogger.shared.log(.recordingResume, sessionId: session.id)
        }
    }

    func beginStopping() {
        guard recordingState.canStop else { return }
        recordingState = .stopping

        // Stop session timer
        stopSessionTimer()
        showingSessionWarning = false
    }

    func finalizeStopRecording() {
        guard recordingState == .stopping else { return }

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

    func showPermissionAlert(_ message: String) {
        permissionAlertMessage = message
        showingPermissionAlert = true
    }

    func dismissPermissionAlert() {
        showingPermissionAlert = false
        permissionAlertMessage = nil
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
        if session.duration >= nextSessionWarningThreshold && !showingSessionWarning {
            showingSessionWarning = true
            nextSessionWarningThreshold += sessionWarningThreshold
        }
    }

    func dismissSessionWarning() {
        showingSessionWarning = false
    }

    // MARK: - Hotkey

    func handleHotkeyToggle() async {
        switch recordingState {
        case .idle:
            let lastAppBundleId = selectedAppBundleId
            if lastAppBundleId != nil {
                PermissionsManager.shared.checkScreenPermission()
                hasScreenPermission = PermissionsManager.shared.hasScreenPermission
            }

            if !hasMicPermission && lastAppBundleId == nil {
                showingStartRecordingDialog = true
                return
            }

            if let bundleId = lastAppBundleId {
                let isRunning = await AppListManager.shared.isAppRunning(bundleId: bundleId)
                if !isRunning || !hasScreenPermission {
                    showingStartRecordingDialog = true
                    return
                }
            }

            startNewSession()
            await TranscriptionService.shared.startRecording(
                micId: selectedMicId,
                appBundleId: lastAppBundleId
            )

        case .recording:
            pauseRecording()
            TranscriptionService.shared.pauseRecording()

        case .paused:
            resumeRecording()
            TranscriptionService.shared.resumeRecording()

        case .stopping:
            break
        }
    }
}
