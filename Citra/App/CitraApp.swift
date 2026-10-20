import SwiftUI

@main
struct CitraApp: App {
    var body: some Scene {
        MenuBarExtra("Citra", systemImage: "circle.circle") {
            Button("Quit Citra") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
