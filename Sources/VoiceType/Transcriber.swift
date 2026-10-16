import Foundation

final class Transcriber {
    private let modelDir: URL
    private let modelName = "ggml-large-v3-turbo.bin"
    private let vadModelName = "ggml-silero-v5.1.2.bin"
    private var vadModelPath: URL?
    private var whisperBinary: String?
    private var modelPath: URL?
    private var isReady = false

    /// Shorter captures are accidental taps, not dictations.
    static let minDuration: TimeInterval = 0.8
    /// Last capture, kept to diagnose a failed dictation (overwritten each time).
    static let lastRecordingURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voicetype/last-recording.wav")
    static let vocabularyURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voicetype/vocabulary.txt")

    private let transcriptionTimeout: TimeInterval = 60  // 60s max for whisper-cli
    var translate = false  // --translate: output in English regardless of input language

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        modelDir = home.appendingPathComponent(".voicetype/models")
    }

    /// Locates whisper-cli and the models, downloading missing ones. Returns readiness.
    @discardableResult
    func loadModel() -> Bool {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
        ]
        whisperBinary = candidates.first { FileManager.default.fileExists(atPath: $0) }

        guard whisperBinary != nil else {
            Log.write("whisper-cli not found. Install: brew install whisper-cpp")
            return false
        }

        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let model = modelDir.appendingPathComponent(modelName)
        if !FileManager.default.fileExists(atPath: model.path) {
            Log.write("Downloading \(modelName)...")
            download(repo: "ggerganov/whisper.cpp", file: modelName, to: model)
        }

        let vad = modelDir.appendingPathComponent(vadModelName)
        if !FileManager.default.fileExists(atPath: vad.path) {
            download(repo: "ggml-org/whisper-vad", file: vadModelName, to: vad)
        }
        vadModelPath = FileManager.default.fileExists(atPath: vad.path) ? vad : nil

        if FileManager.default.fileExists(atPath: model.path) {
            modelPath = model
            isReady = true
            Log.write("Ready (language: \(Settings.language), VAD: \(vadModelPath != nil && Settings.vadEnabled))")
        }
        return isReady
    }

    /// Returns transcribed text, or nil on error (timeout, crash, etc.)
    func transcribe(samples: [Float]) -> TranscriptionResult {
        guard isReady, let binary = whisperBinary, let model = modelPath else {
            return .error("Whisper not ready")
        }

        let duration = Double(samples.count) / 16000.0
        if duration < Self.minDuration {
            return .empty
        }

        let wav = Self.lastRecordingURL
        guard writeWAV(samples: samples, sampleRate: 16000, to: wav) else {
            return .error("Failed to write WAV")
        }

        let useVAD = Settings.vadEnabled && vadModelPath != nil
        let result = transcribe(wav: wav, binary: binary, model: model, vad: useVAD)
        // VAD can reject quiet speech (whispering, noisy train): never let it cost a dictation
        if useVAD, case .empty = result {
            Log.write("Empty with VAD — retrying without")
            return transcribe(wav: wav, binary: binary, model: model, vad: false)
        }
        return result
    }

    private func transcribe(wav: URL, binary: String, model: URL, vad: Bool) -> TranscriptionResult {
        switch run(binary: binary, arguments: arguments(model: model, wav: wav, vad: vad)) {
        case .failure(let reason):
            return .error(reason)
        case .success(let raw):
            let text = TranscriptCleaner.clean(raw)
            if text != raw.trimmingCharacters(in: .whitespacesAndNewlines) {
                Log.write("Cleaned hallucination from: '\(raw)'")
            }
            return text.isEmpty ? .empty : .success(text)
        }
    }

    private func arguments(model: URL, wav: URL, vad: Bool) -> [String] {
        var args = [
            "-m", model.path,
            "-f", wav.path,
            "--no-timestamps",
            "--language", Settings.language,
            "--threads", "6",
            "--beam-size", "1",
            "--best-of", "1",
            "--flash-attn",
            "--no-prints",
        ]

        if vad, let vadModel = vadModelPath {
            args += ["--vad", "--vad-model", vadModel.path]
        }

        // Custom vocabulary via --prompt, carried to every 30 s window (not only the first)
        let vocab = loadVocabulary()
        if !vocab.isEmpty {
            args += ["--prompt", vocab, "--carry-initial-prompt"]
        }

        if translate {
            args.append("--translate")
        }
        return args
    }

    private enum RunOutcome { case success(String), failure(String) }

    private func run(binary: String, arguments: [String]) -> RunOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice  // Prevent pipe deadlock

        do {
            try process.run()
        } catch {
            return .failure("whisper-cli failed: \(error.localizedDescription)")
        }

        // Read stdout before waiting (prevents pipe buffer deadlock)
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

        guard waitForExit(process, timeout: transcriptionTimeout) else {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            return .failure("Transcription timeout")
        }
        guard process.terminationStatus == 0 else {
            return .failure("whisper-cli exit \(process.terminationStatus)")
        }
        return .success(String(data: outputData, encoding: .utf8) ?? "")
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
        guard let content = try? String(contentsOf: Self.vocabularyURL, encoding: .utf8) else { return "" }
        // Join lines into a single prompt string
        let words = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return words.joined(separator: ", ")
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

    private func download(repo: String, file: String, to destination: URL) {
        let urlString = "https://huggingface.co/\(repo)/resolve/main/\(file)"
        guard let url = URL(string: urlString) else { return }

        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            defer { semaphore.signal() }
            if let error { Log.write("Download failed (\(file)): \(error.localizedDescription)"); return }
            guard let tempURL else { return }
            try? FileManager.default.moveItem(at: tempURL, to: destination)
            Log.write("Downloaded \(file)")
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

        let pcm = samples.map { Int16(max(-1.0, min(1.0, $0)) * 32767.0).littleEndian }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }

        do {
            try data.write(to: url)
            return true
        } catch {
            Log.write("Failed to write WAV: \(error.localizedDescription)")
            return false
        }
    }
}
