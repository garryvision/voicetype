import Foundation

final class Transcriber {
    private let modelDir: URL
    private let modelName = "ggml-large-v3-turbo.bin"
    private var whisperBinary: String?
    private var modelPath: URL?
    private var isReady = false

    private let transcriptionTimeout: TimeInterval = 60  // 60s max for whisper-cli
    var translate = false  // --translate: output in English regardless of input language

    // Filter out whisper hallucinations on silence/short audio
    private let junkPatterns: Set<String> = [
        "[BLANK_AUDIO]", "(crickets chirping)", "you", "Thank you.",
        "Thanks for watching!", "Sous-titres réalisés",
    ]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        modelDir = home.appendingPathComponent(".voicetype/models")
    }

    func loadModel() {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
        ]
        whisperBinary = candidates.first { FileManager.default.fileExists(atPath: $0) }

        guard whisperBinary != nil else {
            NSLog("VoiceType: whisper-cli not found. Install: brew install whisper-cpp")
            return
        }

        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let model = modelDir.appendingPathComponent(modelName)
        if !FileManager.default.fileExists(atPath: model.path) {
            NSLog("VoiceType: Downloading whisper base model...")
            downloadModel(to: model)
        }

        if FileManager.default.fileExists(atPath: model.path) {
            modelPath = model
            isReady = true
            NSLog("VoiceType: Ready")
        }
    }

    /// Returns transcribed text, or nil on error (timeout, crash, etc.)
    func transcribe(samples: [Float]) -> TranscriptionResult {
        guard isReady, let binary = whisperBinary, let model = modelPath else {
            return .error("Whisper not ready")
        }

        let duration = Double(samples.count) / 16000.0
        if duration < 0.8 {
            NSLog("VoiceType: Audio too short (%.1fs) — skipping", duration)
            return .empty
        }

        NSLog("VoiceType: Transcribing %.1fs audio...", duration)

        let tempWav = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempWav) }

        guard writeWAV(samples: samples, sampleRate: 16000, to: tempWav) else {
            return .error("Failed to write temp WAV")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        var args = [
            "-m", model.path,
            "-f", tempWav.path,
            "--no-timestamps",
            "--language", "auto",
            "--threads", "6",
            "--beam-size", "1",
            "--best-of", "1",
            "--flash-attn",
            "--no-prints",
        ]

        // Custom vocabulary via --prompt (biases whisper toward these words)
        let vocab = loadVocabulary()
        if !vocab.isEmpty {
            args += ["--prompt", vocab]
        }

        if translate {
            args.append("--translate")
        }

        process.arguments = args

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice  // Prevent pipe deadlock

        var outputData = Data()

        do {
            try process.run()

            // Read stdout before waiting (prevents pipe buffer deadlock)
            outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

            // Wait with timeout
            let exited = waitForExit(process, timeout: transcriptionTimeout)
            if !exited {
                NSLog("VoiceType: whisper-cli timeout after %.0fs — killing", transcriptionTimeout)
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                return .error("Transcription timeout")
            }

            if process.terminationStatus != 0 {
                NSLog("VoiceType: whisper-cli exited with status %d", process.terminationStatus)
                return .error("whisper-cli exit \(process.terminationStatus)")
            }
        } catch {
            NSLog("VoiceType: whisper-cli failed: %@", error.localizedDescription)
            return .error(error.localizedDescription)
        }

        let raw = String(data: outputData, encoding: .utf8) ?? ""
        let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter junk (case-insensitive, trimmed)
        let normalized = result.trimmingCharacters(in: .punctuationCharacters).lowercased()
        for pattern in junkPatterns {
            if normalized == pattern.lowercased()
                || result.lowercased().hasPrefix(pattern.lowercased()) {
                NSLog("VoiceType: Filtered junk: '%@'", result)
                return .empty
            }
        }

        NSLog("VoiceType: Transcribed: '%@'", result)
        return result.isEmpty ? .empty : .success(result)
    }

    // MARK: - Result type

    enum TranscriptionResult {
        case success(String)
        case empty
        case error(String)

        var text: String? {
            if case .success(let t) = self { return t }
            return nil
        }

        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    // MARK: - Vocabulary

    /// Load custom vocabulary from ~/.voicetype/vocabulary.txt
    /// Each line is a word/phrase that biases whisper recognition
    private func loadVocabulary() -> String {
        let vocabFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voicetype/vocabulary.txt")
        guard let content = try? String(contentsOf: vocabFile, encoding: .utf8) else { return "" }
        // Join lines into a single prompt string
        let words = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let prompt = words.joined(separator: ", ")
        if !prompt.isEmpty {
            NSLog("VoiceType: Vocabulary loaded (%d terms)", words.count)
        }
        return prompt
    }

    // MARK: - Process timeout

    private func waitForExit(_ proc: Process, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            proc.waitUntilExit()
            semaphore.signal()
        }
        return semaphore.wait(timeout: .now() + timeout) == .success
    }

    // MARK: - Model download

    private func downloadModel(to destination: URL) {
        let urlString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(modelName)"
        guard let url = URL(string: urlString) else { return }

        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            defer { semaphore.signal() }
            if let error { NSLog("VoiceType: Download failed: \(error)"); return }
            guard let tempURL else { return }
            try? FileManager.default.moveItem(at: tempURL, to: destination)
            NSLog("VoiceType: Model downloaded")
        }
        task.resume()
        semaphore.wait()
    }

    // MARK: - WAV writer

    private func writeWAV(samples: [Float], sampleRate: Int, to url: URL) -> Bool {
        let numSamples = samples.count
        let dataSize = numSamples * 2
        let fileSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        for sample in samples {
            let int16 = Int16(max(-1.0, min(1.0, sample)) * 32767.0)
            data.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }

        do {
            try data.write(to: url)
            return true
        } catch {
            NSLog("VoiceType: Failed to write WAV: %@", error.localizedDescription)
            return false
        }
    }
}
