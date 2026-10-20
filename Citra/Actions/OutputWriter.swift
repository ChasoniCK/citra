import Foundation

/// The one way results reach the disk: `body` writes a hidden temp item in the target folder, which is
/// then moved to the first free Finder-style name. On any error or cancellation the temp item is removed,
/// so a failed or cancelled operation leaves nothing half-written.
enum OutputWriter {
    enum Failure: LocalizedError {
        case notWritable(URL)

        var errorDescription: String? {
            switch self {
            case .notWritable(let dir): "No permission to write into “\(dir.lastPathComponent)”."
            }
        }
    }

    static func write(into directory: URL, baseName: String, pathExtension: String,
                      _ body: (URL) async throws -> Void) async throws -> URL {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: directory.path) else { throw Failure.notWritable(directory) }
        let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        let temp = directory.appending(path: ".citra-\(UUID().uuidString)\(suffix)")
        do {
            try await body(temp)
            try Task.checkCancellation()
            let target = FileNaming.uniqueURL(directory: directory, baseName: baseName, pathExtension: pathExtension) {
                fm.fileExists(atPath: $0.path)
            }
            try fm.moveItem(at: temp, to: target) // refuses to overwrite if the name was taken meanwhile
            return target
        } catch {
            try? fm.removeItem(at: temp) // best effort; the original error is what matters
            throw error
        }
    }
}
