import Foundation

/// Runs a command-line engine (whisper-cli, fluidaudiocli) and returns its stdout.
enum ProcessRunner {
    enum Outcome { case success(String), failure(String) }

    static func run(_ binary: String, _ arguments: [String], timeout: TimeInterval) -> Outcome {
        let name = URL(fileURLWithPath: binary).lastPathComponent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments

        // A pipe can fill while waiting, and reading it first makes the timeout ineffective
        // for a silent process. A temporary file avoids both failure modes.
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt_process_\(UUID().uuidString).out")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let outputHandle = FileHandle(forWritingAtPath: outputURL.path) else {
            return .failure("\(name) output unavailable")
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return .failure("\(name) failed: \(error.localizedDescription)")
        }

        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            if exited.wait(timeout: .now() + 2) != .success, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
            return .failure("\(name) timeout")
        }
        guard process.terminationStatus == 0 else {
            return .failure("\(name) exit \(process.terminationStatus)")
        }
        try? outputHandle.close()
        let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
        return .success(String(data: outputData, encoding: .utf8) ?? "")
    }
}
