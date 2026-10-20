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
        var stdout = Data()
        var partialLine = Data()

        /// Appends a stdout chunk and returns the lines it completed.
        func appendOutput(_ chunk: Data) -> [String] {
            lock.withLock {
                stdout.append(chunk)
                partialLine.append(chunk)
                var lines: [String] = []
                while let newline = partialLine.firstIndex(of: 0x0A) {
                    lines.append(String(decoding: partialLine[partialLine.startIndex..<newline], as: UTF8.self))
                    partialLine.removeSubrange(partialLine.startIndex...newline)
                }
                return lines
            }
        }
    }

    /// Returns stdout; `onOutputLine` sees each stdout line as it arrives (ffmpeg `-progress pipe:1`).
    @discardableResult
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String] = [:],
                    onOutputLine: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let box = Box()
        box.process.executableURL = executable
        box.process.arguments = arguments
        box.process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let output = Pipe(), errors = Pipe()
        box.process.standardOutput = output
        box.process.standardError = errors
        // Both pipes are drained continuously, so a chatty tool never blocks on a full pipe.
        output.fileHandleForReading.readabilityHandler = { handle in
            box.appendOutput(handle.availableData).forEach { onOutputLine?($0) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            box.lock.withLock { box.stderr.append(chunk) }
        }

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                    box.process.terminationHandler = { process in
                        output.fileHandleForReading.readabilityHandler = nil
                        errors.fileHandleForReading.readabilityHandler = nil
                        box.appendOutput(output.fileHandleForReading.readDataToEndOfFile()).forEach { onOutputLine?($0) }
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
        return box.lock.withLock { String(decoding: box.stdout, as: UTF8.self) }
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
