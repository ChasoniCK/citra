import AppKit
import UserNotifications

/// Completion notices with "Show in Finder", and alerts for errors. Notification permission is asked
/// on the first result rather than at launch; without it results still land next to the originals.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let category = "citra.result"
    private nonisolated static let reveal = "reveal"
    private let center = UNUserNotificationCenter.current()

    func start() {
        center.delegate = self
        let show = UNNotificationAction(identifier: Self.reveal, title: "Show in Finder")
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [show], intentIdentifiers: [])])
    }

    func finished(_ title: String, result: ActionResult) {
        let outputs = result.files
        PocLog.write("done: \(title) → \(outputs.map(\.path))\(result.message.map { " — \($0)" } ?? "")")
        guard AppSettings.notificationsEnabled, !outputs.isEmpty || result.message != nil else { return }
        Task {
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = result.message ?? (outputs.count == 1 ? outputs[0].lastPathComponent : "\(outputs.count) files")
                if !outputs.isEmpty { content.categoryIdentifier = Self.category }
                content.userInfo = ["paths": outputs.map(\.path)]
                try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } catch {
                PocLog.write("notification failed: \(error.localizedDescription)")
            }
        }
    }

    func failed(_ title: String, error: Error) {
        PocLog.write("error in \(title): \(error.localizedDescription)")
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t finish \(title)"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard [Self.reveal, UNNotificationDefaultActionIdentifier].contains(response.actionIdentifier) else { return }
        let paths = response.notification.request.content.userInfo["paths"] as? [String] ?? []
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(filePath: $0) }) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
