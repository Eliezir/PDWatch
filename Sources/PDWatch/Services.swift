import Foundation

/// Side effects the models need, injected so they can run against
/// fake data without touching real settings or posting notifications.
struct Services {
    var defaults: UserDefaults
    var notify: (_ title: String, _ body: String) -> Void
    var requestNotificationPermission: () -> Void

    static let live = Services(
        defaults: .standard,
        notify: Notifier.post,
        requestNotificationPermission: Notifier.requestPermission
    )
}
