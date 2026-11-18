import AppKit
import AVFoundation
import ApplicationServices

/// One macOS permission VoiceType needs, with the exact System Settings panel that grants it.
enum Permission: CaseIterable {
    case microphone, accessibility, inputMonitoring

    var title: String {
        switch self {
        case .microphone: return "Micro"
        case .accessibility: return "Accessibilité"
        case .inputMonitoring: return "Surveillance des entrées"
        }
    }

    var detail: String {
        switch self {
        case .microphone: return "Pour entendre ta voix."
        case .accessibility: return "Pour coller le texte là où tu écris."
        case .inputMonitoring: return "Pour sentir la touche Fn."
        }
    }

    /// SF Symbols available since macOS 12, so on every supported system.
    var symbol: String {
        switch self {
        case .microphone: return "mic.fill"
        case .accessibility: return "character.cursor.ibeam"
        case .inputMonitoring: return "globe"
        }
    }

    private var pane: String {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        switch self {
        case .microphone: return base + "Privacy_Microphone"
        case .accessibility: return base + "Privacy_Accessibility"
        case .inputMonitoring: return base + "Privacy_ListenEvent"
        }
    }

    var isGranted: Bool {
        switch self {
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: return AXIsProcessTrusted()
        case .inputMonitoring: return CGPreflightListenEventAccess()
        }
    }

    /// TCC service name understood by tccutil.
    private var tccService: String? {
        switch self {
        case .microphone: return nil
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "ListenEvent"
        }
    }

    /// Clears the stale entry, lists this VoiceType in the panel (so the user only has to
    /// flip the switch), then opens it. Only called while the permission is missing.
    func request() {
        if self == .microphone, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return  // macOS shows its own Allow dialog
        }
        DispatchQueue.global(qos: .userInitiated).async {
            clearStaleEntry()
            DispatchQueue.main.async {
                register()
                if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
            }
        }
    }

    /// With an ad hoc signature every update is a new app for macOS, yet the list keeps the old
    /// entry switched on: it looks granted but applies to nothing. Removing it lets the new
    /// VoiceType take its place, so nobody has to use the - and + buttons.
    private func clearStaleEntry() {
        guard let service = tccService, let id = Bundle.main.bundleIdentifier else { return }
        switch ProcessRunner.run("/usr/bin/tccutil", ["reset", service, id], timeout: 5) {
        case .success: Log.write("Cleared stale \(service) entry")
        case .failure(let reason): Log.write("Could not clear \(service) entry: \(reason)")
        }
    }

    private func register() {
        switch self {
        case .microphone: break
        case .accessibility:
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        case .inputMonitoring:
            CGRequestListenEventAccess()
        }
    }

    static var allGranted: Bool { allCases.allSatisfy(\.isGranted) }
}
