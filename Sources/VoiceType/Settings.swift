import Foundation

/// User settings, stored in `defaults` (domain com.clement.voicetype).
/// Change without rebuilding, e.g. `defaults write com.clement.voicetype audioBackend ffmpeg`.
enum Settings {
    private static let store = UserDefaults.standard

    /// Whisper language code. "fr" skips the auto-detect encoder pass (~0.8 s saved per dictation).
    static var language: String {
        get { store.string(forKey: "language") ?? "fr" }
        set { store.set(newValue, forKey: "language") }
    }

    /// "engine" (AVAudioEngine, starts instantly) or "ffmpeg" (former backend, kept as fallback).
    static var audioBackend: String {
        store.string(forKey: "audioBackend") ?? "engine"
    }

    /// "parakeet" (Neural Engine, ~8x faster, used when installed) or "whisper" (more accurate).
    static var engine: String {
        get { store.string(forKey: "engine") ?? "parakeet" }
        set { store.set(newValue, forKey: "engine") }
    }

    /// Diagnostic opt-in: re-run Whisper after Parakeet and log both texts.
    static var compareEngines: Bool {
        store.bool(forKey: "compareEngines")
    }

    /// Record from the Mac's built-in mic when the default input is a Bluetooth headset,
    /// so music in AirPods keeps its quality. Disable: `defaults write ... avoidBluetoothMic -bool false`.
    static var avoidBluetoothMic: Bool {
        store.object(forKey: "avoidBluetoothMic") as? Bool ?? true
    }

    /// Silero voice activity detection: trims silences, which cause most whisper hallucinations.
    static var vadEnabled: Bool {
        store.object(forKey: "vad") as? Bool ?? true
    }
}
