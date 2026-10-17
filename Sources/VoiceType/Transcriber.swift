import Foundation

final class Transcriber {
    private let modelDir: URL
    private let modelName = "ggml-large-v3-turbo.bin"
    private let vadModelName = "ggml-silero-v5.1.2.bin"
    private var vadModelPath: URL?
    private var whisperBinary: String?
    private var modelPath: URL?
    private var isReady = false

    private let parakeet = ParakeetEngine()
    private var parakeetReady = false
    /// Background whisper runs (Parakeet warm-up, comparisons): never on the dictation path.
    private let backgroundQueue = DispatchQueue(label: "com.clement.voicetype.background", qos: .utility)
    /// Engine that produced the last result, for logs and comparison.
    private(set) var lastEngine = "whisper"

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
        warmUpParakeet()
        return isReady || parakeet.isAvailable
    }

    private func warmUpParakeet() {
        guard parakeet.isAvailable else { return }
        backgroundQueue.async { [self] in
            let silence = modelDir.deletingLastPathComponent().appendingPathComponent("warmup.wav")
            let started = Date()
            _ = writeWAV(samples: [Float](repeating: 0, count: 16000), sampleRate: 16000, to: silence)
            let ok = parakeet.warmUp(silentWav: silence)
            try? FileManager.default.removeItem(at: silence)
            DispatchQueue.main.async { self.parakeetReady = ok }
            Log.write(ok ? "Parakeet ready (\(String(format: "%.1f", Date().timeIntervalSince(started)))s)"
                         : "Parakeet warm-up failed — whisper only")
        }
    }

    /// Returns transcribed text, or nil on error (timeout, crash, etc.)
    func transcribe(samples: [Float]) -> TranscriptionResult {
        let duration = Double(samples.count) / 16000.0
        if duration < Self.minDuration {
            return .empty
        }

        let wav = Self.lastRecordingURL
        guard writeWAV(samples: samples, sampleRate: 16000, to: wav) else {
            return .error("Failed to write WAV")
        }

        if Settings.engine == "parakeet", parakeetReady {
            let result = clean(parakeet.transcribe(wav: wav))
            if case .success = result {
                lastEngine = "parakeet"
                return result
            }
            Log.write("Parakeet gave no text — falling back to whisper")
        }
        lastEngine = "whisper"
        return transcribeWithWhisper(wav: wav)
    }

    private func transcribeWithWhisper(wav: URL) -> TranscriptionResult {
        guard isReady, let binary = whisperBinary, let model = modelPath else {
            return .error("Whisper not ready")
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

    /// Whisper on a copy of the last recording, after Parakeet already pasted its text.
    /// Logs both versions side by side to decide on evidence which engine to keep.
    func compareWithWhisper() {
        guard isReady else { return }
        guard let comparisonURL = try? ComparisonAudio.makeCopy(of: Self.lastRecordingURL) else {
            Log.write("Compare skipped: recording copy failed")
            return
        }
        backgroundQueue.async { [self] in
            defer { try? FileManager.default.removeItem(at: comparisonURL) }
            let started = Date()
            let result = transcribeWithWhisper(wav: comparisonURL)
            let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
            Log.write("Compare whisper (\(elapsed)s): '\(result.text ?? "")'")
        }
    }

    private func transcribe(wav: URL, binary: String, model: URL, vad: Bool) -> TranscriptionResult {
        clean(ProcessRunner.run(binary, arguments(model: model, wav: wav, vad: vad), timeout: transcriptionTimeout))
    }

    private func clean(_ outcome: ProcessRunner.Outcome) -> TranscriptionResult {
        switch outcome {
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
