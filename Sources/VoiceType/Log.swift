import Foundation

/// File log shared by every component (NSLog is invisible when launched via `open`).
enum Log {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voicetype/voicetype.log")

    private static let maxSize = 1_048_576  // 1 MB
    private static let queue = DispatchQueue(label: "com.clement.voicetype.log")

    static func write(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let fh = try? FileHandle(forWritingTo: fileURL) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            } else {
                try? FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: fileURL)
            }
        }
    }

    static func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > maxSize else { return }

        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("voicetype.log.old")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
