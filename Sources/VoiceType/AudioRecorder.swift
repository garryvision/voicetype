import AVFoundation
import Foundation

final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var samples: [Float] = []
    private let lock = NSLock()
    private let targetSampleRate: Double = 16000

    /// Clean up stale temp files from previous crashes
    func cleanupStaleTempFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        ) else { return }

        let stale = files.filter { $0.lastPathComponent.hasPrefix("vt_rec_") }
        for file in stale {
            try? FileManager.default.removeItem(at: file)
        }
        if !stale.isEmpty {
            NSLog("VoiceType: Cleaned up %d stale temp files", stale.count)
        }
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        // Always create a fresh engine (reusing after stop causes issues)
        stopLocked()
        samples = []

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        NSLog("VoiceType: Input device: %@ (%.0f Hz, %d ch)",
              inputNode.description, inputFormat.sampleRate, inputFormat.channelCount)

        // Target format: 16kHz mono Float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            NSLog("VoiceType: Failed to create target format")
            return
        }

        // Converter from input format to 16kHz mono
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            NSLog("VoiceType: Failed to create audio converter")
            return
        }

        let ratio = targetSampleRate / inputFormat.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if let error {
                NSLog("VoiceType: Convert error: %@", error.localizedDescription)
                return
            }

            guard let channelData = outputBuffer.floatChannelData else { return }
            let count = Int(outputBuffer.frameLength)

            self.lock.lock()
            self.samples.append(contentsOf: UnsafeBufferPointer(
                start: channelData[0], count: count
            ))
            self.lock.unlock()
        }

        do {
            try engine.start()
            self.engine = engine
            NSLog("VoiceType: Recording via AVAudioEngine")
        } catch {
            NSLog("VoiceType: Engine start failed: %@", error.localizedDescription)
        }
    }

    func stop() -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        return stopLocked()
    }

    @discardableResult
    private func stopLocked() -> [Float]? {
        guard let engine else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil

        let captured = samples
        samples = []

        NSLog("VoiceType: Captured %d samples (%.1fs)",
              captured.count, Double(captured.count) / targetSampleRate)
        return captured.isEmpty ? nil : captured
    }
}
