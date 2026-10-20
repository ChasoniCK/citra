import SwiftUI

@main
struct CitraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Citra", systemImage: "circle.circle") {
            Button("Open PoC Log") { NSWorkspace.shared.open(PocLog.fileURL) }
            Divider()
            Button("Quit Citra") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }
}
