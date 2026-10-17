import Foundation

/// NVIDIA Parakeet TDT v3 through FluidAudio's CLI, running on the Neural Engine.
/// Measured on M4: 0.3 s for a 35 s dictation, against 2.6 s for whisper large-v3-turbo.
/// Optional: when the binary is absent (friends' Macs), VoiceType stays on whisper.
struct ParakeetEngine {
    /// fluidaudiocli plus its two resource bundles, built from github.com/FluidInference/FluidAudio
    static let binaryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voicetype/bin/fluidaudiocli")

    private let timeout: TimeInterval = 30
    /// The first run downloads (~570 MB) and compiles the CoreML model.
    private let warmUpTimeout: TimeInterval = 600

    var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: Self.binaryURL.path) }

    func transcribe(wav: URL) -> ProcessRunner.Outcome {
        ProcessRunner.run(Self.binaryURL.path, arguments(wav: wav), timeout: timeout)
    }

    /// Runs once at launch so the first real dictation never waits for the model download.
    func warmUp(silentWav: URL) -> Bool {
        if case .success = ProcessRunner.run(Self.binaryURL.path, arguments(wav: silentWav), timeout: warmUpTimeout) {
            return true
        }
        return false
    }

    private func arguments(wav: URL) -> [String] {
        var args = ["transcribe", wav.path]
        // Parakeet detects the language itself; a hint only helps when one is chosen
        if Settings.language != "auto" {
            args += ["--language", Settings.language]
        }
        return args
    }
}
