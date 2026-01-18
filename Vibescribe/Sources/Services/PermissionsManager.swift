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
/// Uses ScreenCaptureKit for audio permission (supports "System Audio Recording Only" in macOS 15+)
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
        self.hasScreenPermission = false  // Will be checked asynchronously
        self.micPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        setupNotificationObservers()

        // Check screen permission asynchronously using ScreenCaptureKit
        Task {
            await checkScreenPermissionAsync()
        }
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

        if currentMic && !hasMicPermission {
            Log.info("Mic permission granted (detected on app activation)", category: .permissions)
            hasMicPermission = true
            micPermissionStatus = .authorized
        }

        // Check screen permission asynchronously
        Task {
            let currentScreen = await checkScreenPermissionStatus()
            if currentScreen && !hasScreenPermission {
                Log.info("Screen permission granted (detected on app activation)", category: .permissions)
                hasScreenPermission = true
            }
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

    /// Check screen permission status using ScreenCaptureKit (respects "System Audio Recording Only")
    private func checkScreenPermissionStatus() async -> Bool {
        do {
            // SCShareableContent.excludingDesktopWindows triggers permission check
            // and respects both full screen recording AND audio-only permissions
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            // Error means no permission
            return false
        }
    }

    /// Check screen recording permission asynchronously
    func checkScreenPermissionAsync() async {
        let granted = await checkScreenPermissionStatus()
        hasScreenPermission = granted
        Log.debug("Screen permission check (ScreenCaptureKit): \(granted)", category: .permissions)
    }

    /// Synchronous check - for backward compatibility (uses cached value)
    func checkScreenPermission() {
        // Trigger async check but don't wait
        Task {
            await checkScreenPermissionAsync()
        }
    }

    /// Request screen recording permission using ScreenCaptureKit
    /// This triggers the appropriate permission dialog (audio-only or full screen)
    func requestScreenPermission() async -> PermissionStatus {
        // Check if already granted
        let alreadyGranted = await checkScreenPermissionStatus()
        if alreadyGranted {
            hasScreenPermission = true
            return .granted
        }

        // It has not been requested before, so we will request it
        if !hasRequestedScreenRecording {
            // First time: SCShareableContent request triggers the system prompt
            Log.info("First time requesting screen capture permission (via ScreenCaptureKit)", category: .permissions)
            hasRequestedScreenRecording = true

            // The check above already triggered the permission dialog if needed
            // Check again after a small delay to see if granted
            try? await Task.sleep(for: .milliseconds(100))
            let granted = await checkScreenPermissionStatus()
            hasScreenPermission = granted

            if granted {
                return .granted
            }
            return .notDetermained
        }

        return .denied
    }

    /// Synchronous version for backward compatibility
    func requestScreenPermissionSync() -> PermissionStatus {
        // For code that can't be async, trigger permission check
        Task {
            _ = await requestScreenPermission()
        }

        if hasScreenPermission {
            return .granted
        }
        if hasRequestedScreenRecording {
            return .denied
        }
        return .notDetermained
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

            Task { @MainActor in
                // Check mic permission
                let currentMicStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                let currentMicGranted = currentMicStatus == .authorized
                if !currentMicGranted && self.lastMicGranted {
                    onRevoked(.microphone)
                }
                self.lastMicGranted = currentMicGranted
                self.micPermissionStatus = currentMicStatus
                self.hasMicPermission = currentMicGranted

                // Check screen permission using ScreenCaptureKit
                let currentScreenGranted = await self.checkScreenPermissionStatus()
                if !currentScreenGranted && self.lastScreenGranted {
                    onRevoked(.screenRecording)
                }
                self.lastScreenGranted = currentScreenGranted
                self.hasScreenPermission = currentScreenGranted
            }
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
