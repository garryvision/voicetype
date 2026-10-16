import Accelerate
import AVFoundation
import Foundation

/// Microphone capture to 16 kHz mono Float32. AVAudioEngine first, ffmpeg as automatic fallback.
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var samples: [Float] = []
    private let lock = NSLock()         // start/stop state
    private let samplesLock = NSLock()  // tap callback only: removeTap() may wait for it
    private let targetSampleRate: Double = 16000
    private let ffmpeg = FFmpegRecorder()
    private var usingFFmpeg = false
    private var engineFailed = false  // once the engine fails, stay on ffmpeg until relaunch

    /// Input level 0…1 for the live waveform, delivered on the main thread (engine backend only).
    var onLevel: ((Float) -> Void)?
    private let silenceFloorDB: Float = -50
    private let loudCeilingDB: Float = -12

    /// False when no backend could start (the UI shows "Micro indisponible").
    private(set) var isCapturing = false

    /// Clean up stale temp files from previous crashes
    func cleanupStaleTempFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        ) else { return }

        // Recorder (vt_rec_*) and transcriber (vt_*) temp WAVs only: TMPDIR is shared with other apps
        for file in files where file.lastPathComponent.hasPrefix("vt_") && file.pathExtension == "wav" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        stopLocked()
        samplesLock.lock()
        samples = []
        samplesLock.unlock()

        if Settings.audioBackend != "ffmpeg", !engineFailed, startEngine() {
            isCapturing = true
            return
        }

        usingFFmpeg = ffmpeg.isAvailable && ffmpeg.start()
        isCapturing = usingFFmpeg
        Log.write(usingFFmpeg ? "Recording via ffmpeg (fallback)" : "No audio backend available")
    }

    func stop() -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        return stopLocked()
    }

    // MARK: - AVAudioEngine

    private func startEngine() -> Bool {
        // Always a fresh engine: reusing one after stop() is unreliable
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate,
                  channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            Log.write("AVAudioEngine: invalid input format \(inputFormat)")
            engineFailed = true
            return false
        }

        let ratio = targetSampleRate / inputFormat.sampleRate
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, converter: converter, targetFormat: targetFormat, ratio: ratio)
        }

        do {
            try engine.start()
            self.engine = engine
            usingFFmpeg = false
            return true
        } catch {
            Log.write("AVAudioEngine start failed: \(error.localizedDescription) — switching to ffmpeg")
            inputNode.removeTap(onBus: 0)
            engine.reset()
            engineFailed = true
            return false
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter,
                        targetFormat: AVAudioFormat, ratio: Double) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        // Hand the input buffer over exactly once: returning it on every callback
        // would let the resampler consume the same audio twice
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil, let channel = output.floatChannelData else { return }
        let count = Int(output.frameLength)
        samplesLock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: count))
        samplesLock.unlock()
        publishLevel(channel[0], count: count)
    }

    private func publishLevel(_ data: UnsafePointer<Float>, count: Int) {
        guard let onLevel, count > 0 else { return }
        var rms: Float = 0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(count))
        let db = 20 * log10(max(rms, 1e-7))
        let level = min(1, max(0, (db - silenceFloorDB) / (loudCeilingDB - silenceFloorDB)))
        DispatchQueue.main.async { onLevel(level) }
    }

    @discardableResult
    private func stopLocked() -> [Float]? {
        isCapturing = false
        if usingFFmpeg {
            usingFFmpeg = false
            return ffmpeg.stop()
        }
        guard let engine else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // reset() releases the input HAL so the orange mic indicator turns off
        engine.reset()
        self.engine = nil

        samplesLock.lock()
        let captured = samples
        samples = []
        samplesLock.unlock()
        return captured.isEmpty ? nil : captured
    }
}
