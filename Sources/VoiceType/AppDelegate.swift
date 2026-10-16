import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var indicator: StatusIndicator!
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let injector = TextInjector()
    private var hotkey: HotkeyManager!

    private enum State { case loading, idle, recording, transcribing }
    private var state: State = .loading
    private var isPaused = false
    private var lastTranscript: String?

    private let maxRecordingDuration: TimeInterval = 300  // safety net; longest real dictation: 158 s
    private var recordingTimeout: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.rotateIfNeeded()
        recorder.cleanupStaleTempFiles()

        indicator = StatusIndicator()
        indicator.menuProvider = { [weak self] in self?.buildMenu() ?? NSMenu() }
        recorder.onLevel = { [weak self] level in self?.indicator.setLevel(level) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ready = self.transcriber.loadModel()
            DispatchQueue.main.async {
                self.state = .idle
                if !ready { self.indicator.flash("Whisper introuvable", isError: true) }
            }
        }

        hotkey = HotkeyManager(
            onPress: { [weak self] in self?.startRecording() },
            onRelease: { [weak self] in self?.stopRecording() },
            onCancel: { [weak self] in self?.cancelRecording() }
        )
        hotkey.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey?.stop()
        _ = recorder.stop()
    }

    // MARK: - Pipeline

    private func startRecording() {
        guard state == .idle else { return }
        if isPaused {
            indicator.flash("En pause", isError: false)
            return
        }

        recorder.start()
        guard recorder.isCapturing else {
            indicator.flash("Micro indisponible", isError: true)
            return
        }
        Log.write("Recording")
        state = .recording
        indicator.show(.recording)

        // Safety net: auto-stop if the release event is missed
        let timeout = DispatchWorkItem { [weak self] in
            Log.write("Recording timeout — forcing stop")
            self?.stopRecording()
        }
        recordingTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + maxRecordingDuration, execute: timeout)
    }

    /// Fn was part of a shortcut (Fn + arrow, Fn + delete…): discard silently.
    private func cancelRecording() {
        guard state == .recording else { return }
        recordingTimeout?.cancel()
        _ = recorder.stop()
        finish()
    }

    private func stopRecording() {
        guard state == .recording else { return }
        recordingTimeout?.cancel()

        let audio = recorder.stop() ?? []
        let duration = Double(audio.count) / 16000
        // A short tap is not a dictation: collapse without flashing the transcribing state
        guard duration >= Transcriber.minDuration else {
            finish()
            return
        }

        Log.write("Captured \(String(format: "%.1f", duration))s")
        state = .transcribing
        indicator.show(.transcribing)

        let started = Date()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.transcriber.transcribe(samples: audio)
            let elapsed = Date().timeIntervalSince(started)
            DispatchQueue.main.async { self.handle(result, elapsed: elapsed) }
        }
    }

    private func handle(_ result: Transcriber.TranscriptionResult, elapsed: TimeInterval) {
        switch result {
        case .success(let text):
            Log.write("Result (\(String(format: "%.1f", elapsed))s): '\(text)'")
            lastTranscript = text
            indicator.show(indicator.resting)  // the text appearing is the feedback
            injector.inject(text: text) {
                DispatchQueue.main.async { self.state = .idle }
            }
        case .empty:
            Log.write("Empty transcription")
            finish()
        case .error(let reason):
            Log.write("Transcription error: \(reason)")
            state = .idle
            indicator.flash("Transcription échouée", isError: true)
        }
    }

    private func finish() {
        state = .idle
        indicator.show(indicator.resting)
    }

    // MARK: - Menu (click on the capsule)

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let copy = item("Copier la dernière dictée", #selector(copyLast))
        copy.isEnabled = lastTranscript != nil
        menu.addItem(copy)
        menu.addItem(item(isPaused ? "Reprendre la dictée" : "Mettre en pause", #selector(togglePause)))
        menu.addItem(.separator())

        let autoLanguage = item("Détecter la langue automatiquement", #selector(toggleLanguage))
        autoLanguage.state = Settings.language == "auto" ? .on : .off
        menu.addItem(autoLanguage)
        menu.addItem(item("Modifier le vocabulaire…", #selector(openVocabulary)))
        menu.addItem(item("Ouvrir le journal", #selector(openLog)))
        menu.addItem(.separator())
        menu.addItem(item("Quitter VoiceType", #selector(quit)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func copyLast() {
        guard let lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
        indicator.flash("Copié", isError: false)
    }

    @objc private func togglePause() {
        isPaused.toggle()
        indicator.resting = isPaused ? .paused : .idle
        indicator.show(indicator.resting)
    }

    @objc private func toggleLanguage() {
        Settings.language = Settings.language == "auto" ? "fr" : "auto"
        indicator.flash(Settings.language == "auto" ? "Langue : auto" : "Langue : français", isError: false)
    }

    @objc private func openVocabulary() {
        let url = Transcriber.vocabularyURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "# Un mot ou une expression par ligne\n".write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.fileURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
