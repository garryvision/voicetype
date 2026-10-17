import Foundation

/// Gives each background Whisper comparison its own immutable recording.
enum ComparisonAudio {
    static func makeCopy(
        of source: URL,
        in directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let destination = directory
            .appendingPathComponent("vt_compare_\(UUID().uuidString).wav")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}
