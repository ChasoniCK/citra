import Foundation

/// Runs a command-line tool with an argument array (no shell, so any path is safe). Cancelling the task
/// terminates the process; a non-zero exit is an error carrying the tool's stderr.
enum ProcessRunner {
    struct Failure: LocalizedError {
        let tool: String
        let status: Int32
        let message: String

        var errorDescription: String? {
            "\(tool) failed (exit \(status))" + (message.isEmpty ? "." : ": \(message)")
        }
    }

    private final class Box: @unchecked Sendable { // touched from the cancellation handler and pipe callbacks
        let process = Process()
        let lock = NSLock()
        var stderr = Data()
    }

    static func run(_ executable: URL, _ arguments: [String], environment: [String: String] = [:]) async throws {
        let box = Box()
        box.process.executableURL = executable
        box.process.arguments = arguments
        box.process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        box.process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        box.process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { handle in // drained continuously so a chatty tool never blocks
            let chunk = handle.availableData
            box.lock.withLock { box.stderr.append(chunk) }
        }

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                    box.process.terminationHandler = { process in
                        errors.fileHandleForReading.readabilityHandler = nil
                        let rest = errors.fileHandleForReading.readDataToEndOfFile()
                        let message = box.lock.withLock { String(decoding: box.stderr + rest, as: UTF8.self) }
                        if process.terminationReason == .exit, process.terminationStatus == 0 {
                            done.resume()
                        } else {
                            done.resume(throwing: Failure(tool: executable.lastPathComponent, status: process.terminationStatus,
                                                          message: message.trimmingCharacters(in: .whitespacesAndNewlines)))
                        }
                    }
                    do { try box.process.run() } catch { done.resume(throwing: error) }
                }
            } onCancel: {
                box.process.terminate()
            }
        } catch {
            // Killed because the task was cancelled: that is a cancellation, not a tool failure.
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
    }
}

/// ZIP → TAR / TAR.GZ: a real repack. The ZIP goes through the same safe extraction into a hidden staging
/// folder next to it, `/usr/bin/tar` packs that tree, and the staging folder is removed whatever happens.
struct RepackArchive: FileAction {
    let gzip: Bool
    static let tar = URL(filePath: "/usr/bin/tar")

    var id: String { gzip ? "zip.targz" : "zip.tar" }
    var title: String { gzip ? "TAR.GZ" : "TAR" }
    var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: Self.tar.path) }

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy { !$0.isDirectory && $0.type == .zip } }
    func centerText(for items: [FileItem]) -> String? { conversionText(items, to: title) }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        let fm = FileManager.default
        var outputs: [URL] = []
        progress.totalUnitCount = Int64(items.count) * 2
        for item in items {
            try Task.checkCancellation()
            let directory = OutputWriter.destination(for: item.url) // staging lives where the result goes
            guard fm.isWritableFile(atPath: directory.path) else { throw OutputWriter.Failure.notWritable(directory) }
            let zip = try ZipReader(url: item.url)
            let staging = directory.appending(path: ".citra-staging-\(UUID().uuidString)", directoryHint: .isDirectory)
            try fm.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: staging) } // best effort cleanup of our own temp tree
            try ZipExtractor.extract(zip, into: staging, stripping: 0,
                                     progress: Progress(totalUnitCount: 1, parent: progress, pendingUnitCount: 1))
            let top = try fm.contentsOfDirectory(atPath: staging.path).sorted()
            outputs.append(try await OutputWriter.write(into: directory, baseName: item.url.deletingPathExtension().lastPathComponent,
                                                        pathExtension: gzip ? "tar.gz" : "tar") { temp in
                try await ProcessRunner.run(Self.tar, ["-c"] + (gzip ? ["-z"] : []) + ["--no-mac-metadata", "-f", temp.path,
                                                      "-C", staging.path, "--"] + top,
                                            environment: ["COPYFILE_DISABLE": "1"])
            })
            progress.completedUnitCount += 1
        }
        return ActionResult(files: outputs)
    }
}
