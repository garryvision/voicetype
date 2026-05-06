import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var dot: NSView!
    private var pulseTimer: Timer?

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let injector = TextInjector()
    private var hotkey: HotkeyManager!

    private enum State { case loading, idle, recording, transcribing, error }
    private var state: State = .loading {
        didSet { updateUI() }
    }

    // MARK: - Design tokens (Apple HIG)
    private let dotSize: CGFloat = 12
    private let windowPadding: CGFloat = 6
    private let cornerRadius: CGFloat = 14
    private let idleOpacity: Float = 0.4
    private let activeOpacity: Float = 1.0

    private let maxRecordingDuration: TimeInterval = 180  // 3 min safety net
    private var recordingTimeout: DispatchWorkItem?

    private let maxLogSize = 1_048_576  // 1 MB

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        rotateLogIfNeeded()
        recorder.cleanupStaleTempFiles()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.transcriber.loadModel()
            DispatchQueue.main.async {
                self?.state = .idle
            }
        }

        hotkey = HotkeyManager(
            onPress: { [weak self] in self?.startRecording() },
            onRelease: { [weak self] in self?.stopRecording() }
        )
        hotkey.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey?.stop()
        _ = recorder.stop()
    }

    // MARK: - Window (Apple-minimal pill)

    private func setupWindow() {
        let pillW = dotSize + windowPadding * 2
        let pillH = pillW

        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.maxX - pillW - 8
        let y = frame.maxY - pillH - 8

        window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: pillW, height: pillH),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = false

        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: pillW, height: pillH))
        container.material = .hudWindow
        container.state = .active
        container.blendingMode = .behindWindow
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        window.contentView = container

        let dotX = (pillW - dotSize) / 2
        let dotY = (pillH - dotSize) / 2
        dot = NSView(frame: NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = dotSize / 2
        dot.layer?.backgroundColor = NSColor.systemGray.cgColor
        dot.alphaValue = CGFloat(idleOpacity)
        container.addSubview(dot)

        window.orderFront(nil)
    }

    // MARK: - UI updates

    private func updateUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopPulse()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

                switch self.state {
                case .loading:
                    self.dot.animator().alphaValue = CGFloat(self.idleOpacity)
                    self.dot.layer?.backgroundColor = NSColor.systemGray.cgColor

                case .idle:
                    self.dot.animator().alphaValue = CGFloat(self.idleOpacity)
                    self.dot.layer?.backgroundColor = NSColor.systemGreen.cgColor

                case .recording:
                    self.dot.animator().alphaValue = CGFloat(self.activeOpacity)
                    self.dot.layer?.backgroundColor = NSColor.systemRed.cgColor
                    self.startPulse()

                case .transcribing:
                    self.dot.animator().alphaValue = CGFloat(self.activeOpacity)
                    self.dot.layer?.backgroundColor = NSColor.systemOrange.cgColor

                case .error:
                    self.dot.animator().alphaValue = CGFloat(self.activeOpacity)
                    self.dot.layer?.backgroundColor = NSColor.systemPurple.cgColor
                }
            }
        }
    }

    // MARK: - Pulse animation (recording)

    private func startPulse() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self, self.state == .recording else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                self.dot.animator().alphaValue = 0.3
            }) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.4
                    self.dot.animator().alphaValue = 1.0
                }
            }
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    // MARK: - Accessibility

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Logging

    private var logFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voicetype/voicetype.log")
    }

    private func log(_ msg: String) {
        NSLog("VoiceType: %@", msg)
        let line = "\(Date()): \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }

        if let fh = try? FileHandle(forWritingTo: logFileURL) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            try? FileManager.default.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: logFileURL)
        }
    }

    private func rotateLogIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? Int, size > maxLogSize else { return }

        let backup = logFileURL.deletingLastPathComponent()
            .appendingPathComponent("voicetype.log.old")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: logFileURL, to: backup)
        NSLog("VoiceType: Log rotated (%d bytes)", size)
    }

    // MARK: - Pipeline

    private func startRecording() {
        guard state == .idle else { return }
        log("Recording")
        state = .recording
        recorder.start()

        // Safety net: auto-stop if release event is missed
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state == .recording else { return }
            self.log("Recording timeout — forcing stop")
            self.stopRecording()
        }
        recordingTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + maxRecordingDuration, execute: timeout)
    }

    private func stopRecording() {
        guard state == .recording else { return }
        recordingTimeout?.cancel()
        recordingTimeout = nil
        state = .transcribing

        guard let audio = recorder.stop(), !audio.isEmpty else {
            log("No audio")
            state = .idle
            return
        }

        log("Captured \(String(format: "%.1f", Double(audio.count) / 16000))s")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.transcriber.transcribe(samples: audio)

            switch result {
            case .success(let text):
                self.log("Result: '\(text)'")
                self.injector.inject(text: text) {
                    DispatchQueue.main.async { self.state = .idle }
                }

            case .empty:
                self.log("Empty transcription")
                DispatchQueue.main.async { self.state = .idle }

            case .error(let reason):
                self.log("Transcription error: \(reason)")
                DispatchQueue.main.async {
                    self.state = .error
                    // Show error for 3s then reset
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.state == .error { self.state = .idle }
                    }
                }
            }
        }
    }
}
