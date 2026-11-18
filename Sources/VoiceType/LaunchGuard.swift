import AppKit
import ApplicationServices

/// Launch checks that keep the Fn key working after an update.
enum LaunchGuard {
    private static let inputMonitoringPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    /// An older copy still running keeps its own Fn tap and its own (stale) permissions:
    /// the newest launch wins.
    static func terminateOtherInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: id)
        where other.processIdentifier != me {
            Log.write("Stopping other VoiceType (pid \(other.processIdentifier), \(other.bundleURL?.path ?? "?"))")
            if !other.terminate() { other.forceTerminate() }
        }
    }

    /// Asks macOS to list VoiceType in Accessibility (needed to paste) if it is not trusted yet.
    static func requestAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if !AXIsProcessTrustedWithOptions([key: true] as CFDictionary) {
            Log.write("Accessibility not granted: prompt shown")
        }
    }

    /// Input Monitoring is what the Fn tap needs: list the app there and open the panel.
    static func requestInputMonitoring() {
        CGRequestListenEventAccess()
        if let url = URL(string: inputMonitoringPane) { NSWorkspace.shared.open(url) }
    }
}
