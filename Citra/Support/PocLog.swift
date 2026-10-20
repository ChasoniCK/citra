import Foundation
import os

/// Experiment trail for the drag PoC: unified log plus ~/Library/Logs/Citra/poc.log,
/// a plain file the user can send back after the manual checklist.
@MainActor
enum PocLog {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Citra/poc.log")

    private static let logger = Logger(subsystem: "com.chasonick.Citra", category: "poc")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    private static let handle: FileHandle? = {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: fileURL.path) { fm.createFile(atPath: fileURL.path, contents: nil) }
            let h = try FileHandle(forWritingTo: fileURL)
            try h.seekToEnd()
            return h
        } catch {
            Logger(subsystem: "com.chasonick.Citra", category: "poc").error("log file unavailable: \(error)")
            return nil
        }
    }()

    static func write(_ message: String) {
        logger.log("\(message, privacy: .public)")
        handle?.write(Data("\(formatter.string(from: .now)) \(message)\n".utf8))
    }
}
