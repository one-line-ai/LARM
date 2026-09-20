import Foundation

/// 절제된 알림 정책.
public struct NotificationRequest: Sendable, Equatable {
    public enum Kind: String, Sendable { case newHigh = "new_high", escalated, newGap = "new_gap", recovered, watchFailed = "watch_failed" }
    public let kind: Kind
    public let dedupeKey: String
    public let title: String
    public let body: String
    public init(kind: Kind, dedupeKey: String, title: String, body: String) { self.kind = kind; self.dedupeKey = dedupeKey; self.title = title; self.body = body }
}

public struct QuietHours: Sendable, Equatable {
    public var enabled: Bool
    public var startHour: Int   // 0-23
    public var endHour: Int     // 0-23, start > end 이면 자정 넘김
    public init(enabled: Bool, startHour: Int, endHour: Int) { self.enabled = enabled; self.startHour = startHour; self.endHour = endHour }
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let h = calendar.component(.hour, from: date)
        return startHour <= endHour ? (h >= startHour && h < endHour) : (h >= startHour || h < endHour)
    }
}

public enum NotificationPolicy {
    public static let window: TimeInterval = 24 * 3600

    public enum Decision: Equatable, Sendable { case send, suppressedDuplicate, quietHours }

    /// 결정과 함께 notification_log를 갱신한다 (발생 건수 보존).
    public static func decide(_ db: SQLiteDB, _ req: NotificationRequest, quiet: QuietHours, now: Date = Date()) throws -> Decision {
        let nowS = Clock.utc(now)
        if let r = try db.query("SELECT last_sent_at FROM notification_log WHERE dedupe_key=?", [.text(req.dedupeKey)]).first,
           let last = r["last_sent_at"]?.string, let lastD = Clock.parse(last), now.timeIntervalSince(lastD) < window {
            try db.run("UPDATE notification_log SET suppressed_count=suppressed_count+1, source_count=source_count+1 WHERE dedupe_key=?", [.text(req.dedupeKey)])
            return .suppressedDuplicate
        }
        if quiet.contains(now) {
            try db.run("INSERT INTO notification_log(dedupe_key, first_at, last_sent_at, suppressed_count, source_count) VALUES(?,?,?,0,1) ON CONFLICT(dedupe_key) DO UPDATE SET source_count=source_count+1",
                       [.text(req.dedupeKey), .text(nowS), .text("1970-01-01T00:00:00.000Z")])
            return .quietHours
        }
        try db.run("INSERT INTO notification_log(dedupe_key, first_at, last_sent_at, suppressed_count, source_count) VALUES(?,?,?,0,1) ON CONFLICT(dedupe_key) DO UPDATE SET last_sent_at=excluded.last_sent_at, source_count=source_count+1",
                   [.text(req.dedupeKey), .text(nowS), .text(nowS)])
        return .send
    }

    /// 알림 본문 규칙: 파일 원문·사용자명·토큰·프로젝트 이름을 넣지 않는다.
    public static func forNewHigh(ruleID: String, count: Int) -> NotificationRequest {
        NotificationRequest(kind: .newHigh, dedupeKey: "new_high|\(ruleID)", title: "LARM: 높은 위험 발견",
                            body: "\(ruleID) 규칙에서 높은 위험 \(count)건이 새로 발견되었습니다. 앱에서 근거를 확인하세요.")
    }
    public static func forGap(reason: String, surface: String) -> NotificationRequest {
        NotificationRequest(kind: .newGap, dedupeKey: "gap|\(surface)|\(reason)", title: "LARM: 감시 공백",
                            body: "\(surface == "config_watch" ? "설정 감시" : surface) 범위에 공백이 생겼습니다 (\(reason)). 앱에서 복구 행동을 확인하세요.")
    }
    public static func forRecovery(surface: String) -> NotificationRequest {
        NotificationRequest(kind: .recovered, dedupeKey: "recovered|\(surface)|\(Int(Date().timeIntervalSince1970 / 3600))", title: "LARM: 감시 복구",
                            body: "\(surface == "config_watch" ? "설정 감시" : surface) 범위가 복구되었습니다. 공백 구간은 기록에 남습니다.")
    }
}
