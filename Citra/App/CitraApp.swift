import SwiftUI

@main
struct CitraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            TaskMenu(tasks: appDelegate.coordinator.tasks)
            Divider()
            Button("Open Log") { NSWorkspace.shared.open(PocLog.fileURL) }
            Button("Quit Citra") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: appDelegate.coordinator.tasks.jobs.isEmpty ? "circle.circle" : "circle.dashed")
        }
    }
}

/// Running tasks with their progress; choosing one cancels it.
private struct TaskMenu: View {
    let tasks: TaskManager

    var body: some View {
        if tasks.jobs.isEmpty {
            Text("No tasks running")
        } else {
            ForEach(tasks.jobs) { job in
                Button("Cancel \(job.title) — \(Int(job.progress.fractionCompleted * 100))%") { tasks.cancel(job.id) }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }
}
