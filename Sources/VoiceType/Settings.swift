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

    /// Silero voice activity detection: trims silences, which cause most whisper hallucinations.
    static var vadEnabled: Bool {
        store.object(forKey: "vad") as? Bool ?? true
    }
}
