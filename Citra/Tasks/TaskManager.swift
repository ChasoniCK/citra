import Foundation
import Observation

/// Runs actions off the main thread, keeps their progress for the menu bar, cancels on request and
/// reports the outcome: outputs to `onFinished`, errors to `onFailed`; a cancelled job reports nothing.
@MainActor @Observable
final class TaskManager {
    struct Job: Identifiable {
        let id = UUID()
        let title: String
        let progress: Progress
    }

    private(set) var jobs: [Job] = []
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let onFinished: (String, [URL]) -> Void
    @ObservationIgnored private let onFailed: (String, Error) -> Void

    init(onFinished: @escaping (String, [URL]) -> Void, onFailed: @escaping (String, Error) -> Void) {
        self.onFinished = onFinished
        self.onFailed = onFailed
    }

    @discardableResult
    func run(_ action: any FileAction, items: [FileItem]) -> Task<Void, Never> {
        let title = items.count == 1 ? "\(action.title): \(items[0].url.lastPathComponent)" : "\(action.title): \(items.count) items"
        let job = Job(title: title, progress: Progress(totalUnitCount: 100))
        jobs.append(job)
        let task = Task {
            do {
                let outputs = try await Self.perform(action, items, job.progress)
                onFinished(job.title, outputs)
            } catch is CancellationError {
                // Cancelled by the user: nothing to report.
            } catch {
                onFailed(job.title, error)
            }
            jobs.removeAll { $0.id == job.id }
            tasks[job.id] = nil
        }
        tasks[job.id] = task
        return task
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        jobs.first { $0.id == id }?.progress.cancel()
    }

    /// `@concurrent`: the work never runs on the main actor, whatever the caller's isolation.
    @concurrent
    private nonisolated static func perform(_ action: any FileAction, _ items: [FileItem], _ progress: Progress) async throws -> [URL] {
        let outputs = try await action.perform(items: items, progress: progress)
        try Task.checkCancellation()
        return outputs
    }
}
