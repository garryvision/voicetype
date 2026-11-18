import AppKit

/// Launch checks that keep the Fn key working after an update.
enum LaunchGuard {
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
}
