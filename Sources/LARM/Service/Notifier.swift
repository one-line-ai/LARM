import Foundation
import UserNotifications
import LARMCore

/// macOS 알림.
@MainActor
final class Notifier {
    private(set) var available = AppInfo.isBundled
    private(set) var authorized = false
    var reason: String { available ? (authorized ? "허용됨" : "알림 권한 미허용 (감시와 앱 이력은 유지)") : "앱 번들 밖에서는 알림을 보낼 수 없음" }

    func refreshAuthorization() async {
        guard available else { return }
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    func requestAuthorization() async -> Bool {
        guard available else { return false }
        do {
            authorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch { authorized = false }
        return authorized
    }

    /// 정책(24시간 묶음·조용한 시간)을 거쳐 보낸다.
    @discardableResult
    func send(_ req: NotificationRequest, db: SQLiteDB, quiet: QuietHours, enabled: Bool) -> NotificationPolicy.Decision? {
        guard let d = try? NotificationPolicy.decide(db, req, quiet: quiet) else { return nil }
        guard d == .send, enabled, available, authorized else { return d }
        let c = UNMutableNotificationContent()
        c.title = req.title; c.body = req.body; c.sound = .default
        c.threadIdentifier = req.kind.rawValue
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        return d
    }
}
