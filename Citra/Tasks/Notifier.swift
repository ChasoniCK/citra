import AppKit
import UserNotifications

/// Completion notices with "Show in Finder", and alerts for errors. Notification permission is asked
/// on the first result rather than at launch; without it results still land next to the originals.
/// When macOS has notifications off for Citra (it asks only once, ever), the first result of a launch
/// offers to open their settings instead of failing silently.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let category = "citra.result"
    private nonisolated static let reveal = "reveal"
    private let center = UNUserNotificationCenter.current()
    private var offeredThisLaunch = false

    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

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
                switch await center.notificationSettings().authorizationStatus {
                case .denied:
                    return offerToEnable()
                case .notDetermined:
                    guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
                default:
                    break
                }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = result.message ?? (outputs.count == 1 ? outputs[0].lastPathComponent : "\(outputs.count) files")
                if !outputs.isEmpty { content.categoryIdentifier = Self.category }
                content.userInfo = ["paths": outputs.map(\.path)]
                try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } catch {
                PocLog.write("notification failed: \(error.localizedDescription)")
                offerToEnable()
            }
        }
    }

    /// Once per launch: results are saved, but say why there was no notice and offer the fix.
    private func offerToEnable() {
        guard !offeredThisLaunch else { return }
        offeredThisLaunch = true
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Notifications are off for Citra"
        alert.informativeText = "Results are saved, but Citra can’t tell you when a task finishes. Turn on notifications for Citra in System Settings."
        alert.addButton(withTitle: "Open Notification Settings")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don’t Notify")
        switch alert.runModal() {
        case .alertFirstButtonReturn: Self.openSystemSettings()
        case .alertThirdButtonReturn: UserDefaults.standard.set(false, forKey: AppSettings.Key.notifications)
        default: break
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
