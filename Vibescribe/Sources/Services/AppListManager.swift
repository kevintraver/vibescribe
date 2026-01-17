import Foundation
import ScreenCaptureKit
import AppKit

/// Represents a running application that can be captured
struct RunningApp: Identifiable, Hashable {
    let bundleId: String
    let name: String
    let icon: NSImage?

    var id: String { bundleId }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleId)
    }

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.bundleId == rhs.bundleId
    }
}

/// Manages listing of running applications for audio capture
final class AppListManager: @unchecked Sendable {
    static let shared = AppListManager()

    private init() {}

    /// Get list of running applications that can have their audio captured
    func getRunningApps() async -> [RunningApp] {
        Log.debug("getRunningApps() called", category: .audio)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            Log.debug("SCShareableContent returned \(content.applications.count) applications", category: .audio)

            // Filter out system apps and the current app
            let currentBundleId = Bundle.main.bundleIdentifier ?? ""
            Log.debug("Current bundle ID: \(currentBundleId)", category: .audio)

            var apps: [RunningApp] = []
            var seenBundleIds = Set<String>()

            for scApp in content.applications {
                let bundleId = scApp.bundleIdentifier
                guard !bundleId.isEmpty,
                      bundleId != currentBundleId,
                      !seenBundleIds.contains(bundleId) else {
                    continue
                }

                seenBundleIds.insert(bundleId)

                // Get app icon
                let icon = getAppIcon(bundleId: bundleId)

                let app = RunningApp(
                    bundleId: bundleId,
                    name: scApp.applicationName,
                    icon: icon
                )
                apps.append(app)
            }

            // Sort by name
            Log.info("Returning \(apps.count) filtered apps", category: .audio)
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        } catch {
            Log.error("Failed to get running apps: \(error)", category: .audio)
            return []
        }
    }

    /// Get the app icon for a bundle ID
    private func getAppIcon(bundleId: String) -> NSImage? {
        guard let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: appUrl.path)
    }

    /// Check if an app is currently running
    func isAppRunning(bundleId: String) async -> Bool {
        let apps = await getRunningApps()
        return apps.contains { $0.bundleId == bundleId }
    }

    /// Get SCRunningApplication for a bundle ID
    func getSCApplication(bundleId: String) async -> SCRunningApplication? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return content.applications.first { $0.bundleIdentifier == bundleId }
        } catch {
            return nil
        }
    }
}
