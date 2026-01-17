import Foundation
import AVFoundation
import ScreenCaptureKit
import AppKit

/// Keys for permission-related UserDefaults
private enum PermissionKeys {
    static let hasRequestedScreenRecording = "hasRequestedScreenRecording"
}

enum RevokedPermission {
    case microphone
    case screenRecording
}

/// Manages app permissions for microphone and screen recording
/// Uses best practices from VoiceInk, Dayflow, and other production macOS apps
@MainActor
final class PermissionsManager: ObservableObject {
    public enum PermissionStatus {
        case granted
        case notDetermained
        case denied
        case restricted
    }

    static let shared = PermissionsManager()

    // MARK: - Published State

    @Published private(set) var hasMicPermission: Bool = false
    @Published private(set) var hasScreenPermission: Bool = false
    @Published private(set) var micPermissionStatus: AVAuthorizationStatus = .notDetermined

    // MARK: - Private State

    private var hasRequestedScreenRecording: Bool {
        get { UserDefaults.standard.bool(forKey: PermissionKeys.hasRequestedScreenRecording) }
        set { UserDefaults.standard.set(newValue, forKey: PermissionKeys.hasRequestedScreenRecording) }
    }
    private var monitorTimer: Timer?
    private var lastMicGranted: Bool = false
    private var lastScreenGranted: Bool = false

    // MARK: - Initialization

    private init() {
        self.hasMicPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        self.hasScreenPermission = CGPreflightScreenCaptureAccess()
        self.micPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        setupNotificationObservers()
        checkAllPermissions()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Check permissions when app becomes active (e.g., returning from System Settings)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidBecomeActive() {
        // Only transition to granted, don't auto-flip to denied
        // This prevents UI flicker and supports quit-and-reopen workflows
        let currentMic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let currentScreen = CGPreflightScreenCaptureAccess()

        if currentMic && !hasMicPermission {
            Log.info("Mic permission granted (detected on app activation)", category: .permissions)
            hasMicPermission = true
            micPermissionStatus = .authorized
        }

        if currentScreen && !hasScreenPermission {
            Log.info("Screen permission granted (detected on app activation)", category: .permissions)
            hasScreenPermission = true
        }
    }

    // MARK: - Check All Permissions

    func checkAllPermissions() {
        checkMicPermission()
        checkScreenPermission()
    }

    // MARK: - Microphone Permission

    /// Check current microphone permission status (synchronous)
    func checkMicPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        micPermissionStatus = status
        hasMicPermission = status == .authorized
        Log.debug("Mic permission status: \(status.rawValue), granted: \(hasMicPermission)", category: .permissions)
    }

    func getMicPermissionStatus() -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermained
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    /// Request microphone permission
    func requestMicPermission() async -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            hasMicPermission = true
            micPermissionStatus = .authorized
            return .granted

        case .notDetermined:
            Log.info("Requesting mic access from user...", category: .permissions)
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            hasMicPermission = granted
            micPermissionStatus = granted ? .authorized : .denied
            Log.info("Mic access request result: \(granted)", category: .permissions)
            if granted {
                return .granted
            }
            return .denied

        case .denied:
            hasMicPermission = false
            micPermissionStatus = status
            Log.warning("Mic permission \(status == .denied ? "denied" : "restricted")", category: .permissions)
            return .denied
        case .restricted:
            hasMicPermission = false
            micPermissionStatus = status
            Log.warning("Mic permission \(status == .denied ? "denied" : "restricted")", category: .permissions)
            return .restricted

        @unknown default:
            return .denied
        }
    }

    // MARK: - Screen Recording Permission

    /// Check screen recording permission using CGPreflightScreenCaptureAccess (synchronous, fast)
    func checkScreenPermission() {
        let granted = CGPreflightScreenCaptureAccess()
        hasScreenPermission = granted
        Log.debug("Screen permission check: \(granted)", category: .permissions)
    }

    /// Request screen recording permission
    /// Returns true if permission was already granted, false if user needs to grant in Settings
    func requestScreenPermission() -> PermissionStatus {
        // Check if already granted
        if CGPreflightScreenCaptureAccess() {
            hasScreenPermission = true
            return .granted
        }

        // It has not been requested before, so we will request it
        if !hasRequestedScreenRecording {
            // First time: trigger the system prompt
            Log.info("First time requesting screen recording permission", category: .permissions)
            CGRequestScreenCaptureAccess()
            hasRequestedScreenRecording = true
            return .notDetermained
        }

        return .denied
    }

    /// Reset the "has requested" flag (useful for testing)
    func resetScreenRecordingRequestFlag() {
        hasRequestedScreenRecording = false
    }

    // MARK: - Permission Monitoring

    func startMonitoringPermissions(onRevoked: @escaping (RevokedPermission) -> Void) {
        stopMonitoringPermissions()
        lastMicGranted = hasMicPermission
        lastScreenGranted = hasScreenPermission

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            let currentMicStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            let currentMicGranted = currentMicStatus == .authorized
            if !currentMicGranted && lastMicGranted {
                onRevoked(.microphone)
            }
            lastMicGranted = currentMicGranted
            micPermissionStatus = currentMicStatus
            hasMicPermission = currentMicGranted

            let currentScreenGranted = CGPreflightScreenCaptureAccess()
            if !currentScreenGranted && lastScreenGranted {
                onRevoked(.screenRecording)
            }
            lastScreenGranted = currentScreenGranted
            hasScreenPermission = currentScreenGranted
        }
    }

    func stopMonitoringPermissions() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    // MARK: - System Settings

    /// Open System Settings to Screen Recording privacy pane
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings to Microphone privacy pane
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings app (generic)
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }

}
