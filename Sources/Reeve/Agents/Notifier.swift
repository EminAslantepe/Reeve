import AppKit
import UserNotifications

/// macOS bildirimleri ve Dock rozeti (UI.md §5).
///
/// İki durumda bildirim: **izin bekliyor** ve **iş bitti** (`busy → idle`).
/// İkisi de yalnızca pencere önde değilken — öndeyken zaten görüyorsun.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    /// Bildirime tıklanınca o oturuma odaklanmak için.
    var onOpenSession: ((UUID) -> Void)?

    var notifyWaiting = true
    var notifyFinished = true

    private var authorized = false

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.authorized = granted
            guard let error else { return }
            // Ad-hoc imzalı uygulamada macOS bunu daima reddediyor; gerçek bir imza
            // kimliği gerekiyor (bkz. Scripts/bundle.sh). Dock rozeti bundan etkilenmiyor.
            FileHandle.standardError.write(
                Data("reeve: banner bildirimleri kapalı — \(error.localizedDescription)\n"
                     .utf8))
        }
    }

    func handle(_ transitions: [SessionStore.Transition]) {
        guard !NSApp.isActive else { return }

        for transition in transitions {
            switch (transition.from, transition.to) {
            case (_, .waiting(let what)) where notifyWaiting:
                post(title: transition.session.name,
                     body: what,
                     sessionID: transition.session.id)

            case (.busy, .idle) where notifyFinished:
                post(title: transition.session.name,
                     body: "iş bitti",
                     sessionID: transition.session.id)

            default:
                break
            }
        }
    }

    /// Dock ikonundaki sayı: dikkat bekleyen oturum sayısı.
    func updateBadge(waiting: Int) {
        NSApp.dockTile.badgeLabel = waiting > 0 ? "\(waiting)" : nil
    }

    // MARK: -

    private func post(title: String, body: String, sessionID: UUID) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["session": sessionID.uuidString]

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo["session"] as? String,
           let id = UUID(uuidString: raw) {
            DispatchQueue.main.async { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.onOpenSession?(id)
            }
        }
        completionHandler()
    }
}
