import Foundation

/// Fallback capture via ffmpeg (the backend used in production from April to October 2026).
/// Slower to start (~1 s) than AVAudioEngine, which can clip the first words.
final class FFmpegRecorder {
    private var process: Process?
    private var outputFile: URL?
    private let ffmpegPath = "/opt/homebrew/bin/ffmpeg"

    var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: ffmpegPath) }

    func start() -> Bool {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt_rec_\(UUID().uuidString).wav")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpegPath)
        proc.arguments = ["-f", "avfoundation", "-i", ":0", "-ar", "16000", "-ac", "1", "-y", tempFile.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            process = proc
            outputFile = tempFile
            return true
        } catch {
            Log.write("ffmpeg start failed: \(error.localizedDescription)")
            return false
        }
    }

    func stop() -> [Float]? {
        guard let proc = process else { return nil }
        process = nil

        if proc.isRunning {
            proc.interrupt()  // SIGINT: graceful stop, ffmpeg finalizes the WAV header
            if !Self.waitForExit(proc, timeout: 5) {
                proc.terminate()
                if !Self.waitForExit(proc, timeout: 3) { kill(proc.processIdentifier, SIGKILL) }
            }
        }

        guard let file = outputFile else { return nil }
        defer {
            try? FileManager.default.removeItem(at: file)
            outputFile = nil
        }
        return Self.readWAV(from: file)
    }

    private static func waitForExit(_ proc: Process, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            proc.waitUntilExit()
            semaphore.signal()
        }
        return semaphore.wait(timeout: .now() + timeout) == .success
    }

    /// Reads 16-bit mono PCM, locating the "data" chunk instead of assuming a 44-byte header.
    private static func readWAV(from url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url), data.count > 44 else { return nil }

        let marker = Data("data".utf8)
        guard let range = data.range(of: marker, in: 12..<data.count) else { return nil }
        let start = range.upperBound + 4  // skip the 4-byte chunk size
        guard data.count > start else { return nil }

        let samples: [Float] = data[start...].withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float($0) / 32768.0 }
        }
        return samples.isEmpty ? nil : samples
    }
}
