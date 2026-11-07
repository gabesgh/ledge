import Foundation

/// An opt-in log at ~/Library/Logs/Ledge/ledge.log for diagnosing gestures
/// (Settings › About). Writes happen off the calling thread, nothing is logged
/// per frame, and the message isn't even built while the log is off.
enum DebugLog {
    private static let queue = DispatchQueue(label: "com.gshimoon.ledge.log", qos: .utility)
    private static let maxBytes: UInt64 = 1_000_000

    static let fileURL: URL = {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Ledge", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ledge.log")
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static var isEnabled: Bool { Prefs.shared.snapshot.diagnosticLog }

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        let stamp = Date()
        queue.async {
            let line = "\(formatter.string(from: stamp)) \(text)\n"
            let url = fileURL
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? UInt64, size > maxBytes {
                try? FileManager.default.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
