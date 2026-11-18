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

    /// Lists VoiceType in the panel (so the user only has to flip the switch), then opens it.
    func request() {
        switch self {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
                return  // macOS shows its own Allow dialog
            }
        case .accessibility:
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: false] as CFDictionary)
        case .inputMonitoring:
            CGRequestListenEventAccess()
        }
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    static var allGranted: Bool { allCases.allSatisfy(\.isGranted) }
}
