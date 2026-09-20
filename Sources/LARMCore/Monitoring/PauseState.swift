import Foundation

/// 기한 일시중지.
public struct PauseState: Sendable, Equatable {
    public enum Mode: String, Sendable { case none, timed, manual }
    public var mode: Mode
    public var until: Date?
    public init(mode: Mode = .none, until: Date? = nil) { self.mode = mode; self.until = until }

    public var isPaused: Bool {
        switch mode { case .none: return false; case .manual: return true; case .timed: return (until ?? .distantPast) > Date() }
    }
    public var expired: Bool { mode == .timed && !(isPaused) }

    public var description: String {
        switch mode {
        case .none: return "감시 중"
        case .manual: return "일시중지 (수동 재개까지)"
        case .timed: return until.map { "일시중지 · 재개 \(Clock.utc($0))" } ?? "일시중지"
        }
    }

    public static func load(_ db: SQLiteDB) -> PauseState {
        let mode = Mode(rawValue: Settings.get(db, "pause_mode") ?? "none") ?? .none
        let until = Settings.get(db, "pause_until").flatMap { Clock.parse($0) }
        return PauseState(mode: mode, until: until)
    }
    public func save(_ db: SQLiteDB) throws {
        try Settings.set(db, "pause_mode", mode.rawValue)
        try Settings.set(db, "pause_until", until.map { Clock.utc($0) } ?? "")
    }
}
