import Foundation
import UserNotifications

enum Notifier {
    /// Notifications only work from a real .app bundle (see build.sh).
    /// Under `swift run`, UNUserNotificationCenter would crash, so we skip it.
    static let isAvailable = Bundle.main.bundlePath.hasSuffix(".app")

    static func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
