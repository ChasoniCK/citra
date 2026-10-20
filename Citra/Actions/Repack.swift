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

/// The archive formats Citra converts between, recognized by type (ZIP) or name (TAR, TAR.GZ): before the drop
/// a `.tar.gz` and a plain `.gz` have the same type.
enum ArchiveKind: CaseIterable, Sendable {
    case zip, tar, tarGz

    static func of(_ item: FileItem) -> ArchiveKind? {
        guard !item.isDirectory else { return nil }
        let name = item.url.lastPathComponent.lowercased()
        if item.type == .zip { return .zip }
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .tarGz }
        return name.hasSuffix(".tar") ? .tar : nil
    }

    var title: String { switch self { case .zip: "ZIP"; case .tar: "TAR"; case .tarGz: "TAR.GZ" } }
    var pathExtension: String { switch self { case .zip: "zip"; case .tar: "tar"; case .tarGz: "tar.gz" } }
    var packFlags: [String] { switch self { case .zip: ["--format", "zip"]; case .tar: []; case .tarGz: ["-z"] } }

    /// `Project.tar.gz` → `Project`, not `Project.tar`.
    static func baseName(_ url: URL) -> String {
        let name = url.lastPathComponent
        let suffix = [".tar.gz", ".tgz", ".tar", ".zip"].first { name.lowercased().hasSuffix($0) }
        return suffix.map { String(name.dropLast($0.count)) } ?? url.deletingPathExtension().lastPathComponent
    }
}

/// `/usr/bin/tar` (bsdtar) reads and writes ZIP, TAR and TAR.GZ. Extracting, it refuses `..` entries, strips a
/// leading `/` and never writes through a symlink, so a hostile archive cannot reach outside the target folder.
enum Tar {
    static let tool = URL(filePath: "/usr/bin/tar")
    static let gzip = URL(filePath: "/usr/bin/gzip")

    /// The single top-level folder of a listing (macOS `._` files aside), if everything lives inside one.
    static func singleRoot(_ names: [String]) -> String? {
        let paths = names.map { $0.split(separator: "/").map(String.init) }.filter { !$0.isEmpty && !$0[0].hasPrefix("._") }
        guard let first = paths.first?.first, first != ".", first != "..", paths.allSatisfy({ $0.first == first }),
              paths.contains(where: { $0.count > 1 })
        else { return nil }
        return first
    }

    static func extract(_ archive: URL, into directory: URL) async throws -> URL {
        let root = singleRoot(try await ProcessRunner.run(tool, ["-tf", archive.path]).split(separator: "\n").map(String.init))
        return try await OutputWriter.write(into: directory, baseName: root ?? ArchiveKind.baseName(archive), pathExtension: "") { temp in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
            try await ProcessRunner.run(tool, ["-x", "-f", archive.path, "-C", temp.path] + (root == nil ? [] : ["--strip-components", "1"]))
        }
    }

    /// `log.txt.gz` → `log.txt`. gzip decompresses in place, so it works on a copy named after the temp file.
    static func gunzip(_ file: URL, into directory: URL) async throws -> URL {
        let inner = file.deletingPathExtension()
        return try await OutputWriter.write(into: directory, baseName: inner.deletingPathExtension().lastPathComponent,
                                            pathExtension: inner.pathExtension) { temp in
            let packed = temp.appendingPathExtension("gz")
            defer { try? FileManager.default.removeItem(at: packed) } // gone after success; left over after a failure
            try FileManager.default.copyItem(at: file, to: packed)
            try await ProcessRunner.run(gzip, ["-d", "-n", "-f", "--", packed.path])
        }
    }
}

/// ZIP, TAR, TAR.GZ → each other: a real repack. The source is extracted into a hidden staging folder next to
/// it (ZIP through the same safe extraction as Extract, TAR through `/usr/bin/tar`), `/usr/bin/tar` packs that
/// tree, and the staging folder is removed whatever happens.
struct RepackArchive: FileAction {
    let target: ArchiveKind

    var id: String { "archive.\(target == .tarGz ? "targz" : target.pathExtension)" }
    var title: String { target.title }
    var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: Tar.tool.path) }

    func isApplicable(to items: [FileItem]) -> Bool { items.allSatisfy { ArchiveKind.of($0).map { $0 != target } ?? false } }
    func centerText(for items: [FileItem]) -> String? { conversionText(items, to: title) }

    func perform(items: [FileItem], progress: Progress) async throws -> ActionResult {
        let fm = FileManager.default
        var outputs: [URL] = []
        progress.totalUnitCount = Int64(items.count) * 2
        for item in items {
            try Task.checkCancellation()
            let directory = OutputWriter.destination(for: item.url) // staging lives where the result goes
            guard fm.isWritableFile(atPath: directory.path) else { throw OutputWriter.Failure.notWritable(directory) }
            let zip = ArchiveKind.of(item) == .zip ? try ZipReader(url: item.url) : nil
            let staging = directory.appending(path: ".citra-staging-\(UUID().uuidString)", directoryHint: .isDirectory)
            try fm.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: staging) } // best effort cleanup of our own temp tree
            if let zip {
                try ZipExtractor.extract(zip, into: staging, stripping: 0,
                                         progress: Progress(totalUnitCount: 1, parent: progress, pendingUnitCount: 1))
            } else {
                try await ProcessRunner.run(Tar.tool, ["-x", "-f", item.url.path, "-C", staging.path])
                progress.completedUnitCount += 1
            }
            let top = try fm.contentsOfDirectory(atPath: staging.path).sorted()
            outputs.append(try await OutputWriter.write(into: directory, baseName: ArchiveKind.baseName(item.url),
                                                        pathExtension: target.pathExtension) { temp in
                try await ProcessRunner.run(Tar.tool, ["-c"] + target.packFlags + ["--no-mac-metadata", "-f", temp.path,
                                                       "-C", staging.path, "--"] + top,
                                            environment: ["COPYFILE_DISABLE": "1"])
            })
            progress.completedUnitCount += 1
        }
        return ActionResult(files: outputs)
    }
}
