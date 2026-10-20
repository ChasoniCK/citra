import SwiftUI

@main
struct CitraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppSettings.Key.enabled) private var enabled = true

    var body: some Scene {
        MenuBarExtra {
            Toggle("Enabled", isOn: $enabled)
            SettingsButton()
            Divider()
            TaskMenu(tasks: appDelegate.coordinator.tasks)
            Divider()
            Button("Open Log") { NSWorkspace.shared.open(PocLog.fileURL) }
            Button("Quit Citra") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: !enabled ? "circle.slash" : appDelegate.coordinator.tasks.jobs.isEmpty ? "circle.circle" : "circle.dashed")
        }
        Settings { SettingsView() }
    }
}

/// Opens Settings in front: an accessory app's windows otherwise appear behind the active app.
private struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
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
        AppSettings.registerDefaults()
        Task.detached(priority: .utility) { _ = FFmpeg.current } // probe ffmpeg off the drag path
        coordinator.start()
    }
}
