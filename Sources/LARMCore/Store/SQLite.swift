import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "sqlite(\(code)): \(message)" }
}

/// 얇은 SQLite 래퍼.
public final class SQLiteDB {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.onelineai.larm.sqlite")
    public let url: URL

    public init(url: URL) throws {
        self.url = url
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let h = handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            throw SQLiteError(code: -1, message: msg)
        }
        db = h
        Paths.restrict(url)
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA foreign_keys=ON")
        try exec("PRAGMA busy_timeout=5000")
        Paths.restrict(url.appendingPathExtension("wal").deletingPathExtension().appendingPathExtension("sqlite-wal"))
    }

    deinit { if let db { sqlite3_close(db) } }

    public enum Value: Equatable {
        case null, int(Int64), real(Double), text(String), blob(Data)
        public var string: String? { if case .text(let s) = self { return s }; return nil }
        public var int: Int64? { if case .int(let i) = self { return i }; return nil }
        public var double: Double? { if case .real(let d) = self { return d }; if case .int(let i) = self { return Double(i) }; return nil }
        public var data: Data? { if case .blob(let d) = self { return d }; return nil }
    }

    public typealias Row = [String: Value]

    public func exec(_ sql: String) throws {
        try queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                let m = err.map { String(cString: $0) } ?? "exec failed"
                sqlite3_free(err)
                throw SQLiteError(code: sqlite3_errcode(db), message: m)
            }
        }
    }

    @discardableResult
    public func run(_ sql: String, _ params: [Value] = []) throws -> Int {
        try queue.sync {
            let stmt = try prepare(sql, params)
            defer { sqlite3_finalize(stmt) }
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw lastError() }
            return Int(sqlite3_changes(db))
        }
    }

    public func query(_ sql: String, _ params: [Value] = []) throws -> [Row] {
        try queue.sync {
            let stmt = try prepare(sql, params)
            defer { sqlite3_finalize(stmt) }
            var rows: [Row] = []
            let n = sqlite3_column_count(stmt)
            let names = (0..<n).map { String(cString: sqlite3_column_name(stmt, $0)) }
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW {
                    var row: Row = [:]
                    for i in 0..<n {
                        switch sqlite3_column_type(stmt, i) {
                        case SQLITE_INTEGER: row[names[Int(i)]] = .int(sqlite3_column_int64(stmt, i))
                        case SQLITE_FLOAT: row[names[Int(i)]] = .real(sqlite3_column_double(stmt, i))
                        case SQLITE_TEXT: row[names[Int(i)]] = .text(String(cString: sqlite3_column_text(stmt, i)))
                        case SQLITE_BLOB:
                            let len = Int(sqlite3_column_bytes(stmt, i))
                            row[names[Int(i)]] = .blob(len > 0 ? Data(bytes: sqlite3_column_blob(stmt, i), count: len) : Data())
                        default: row[names[Int(i)]] = .null
                        }
                    }
                    rows.append(row)
                } else if rc == SQLITE_DONE { break } else { throw lastError() }
            }
            return rows
        }
    }

    public func scalar(_ sql: String, _ params: [Value] = []) throws -> Value {
        let rows = try query(sql, params)
        guard let r = rows.first, let v = r.values.first, r.count == 1 else { return .null }
        return v
    }

    /// 트랜잭션.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let v = try body()
            try exec("COMMIT")
            return v
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    public var userVersion: Int {
        get { (try? scalar("PRAGMA user_version").int).map(Int.init) ?? 0 }
    }
    public func setUserVersion(_ v: Int) throws { try exec("PRAGMA user_version=\(v)") }

    private func prepare(_ sql: String, _ params: [Value]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else { throw lastError() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .null: sqlite3_bind_null(s, idx)
            case .int(let v): sqlite3_bind_int64(s, idx, v)
            case .real(let v): sqlite3_bind_double(s, idx, v)
            case .text(let v): sqlite3_bind_text(s, idx, v, -1, transient)
            case .blob(let d): _ = d.withUnsafeBytes { sqlite3_bind_blob(s, idx, $0.baseAddress, Int32(d.count), transient) }
            }
        }
        return s
    }

    private func lastError() -> SQLiteError {
        SQLiteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
    }
}

extension SQLiteDB.Value: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    public init(stringLiteral value: String) { self = .text(value) }
    public init(integerLiteral value: Int) { self = .int(Int64(value)) }
}
public extension SQLiteDB.Value {
    static func from(_ s: String?) -> SQLiteDB.Value { s.map { .text($0) } ?? .null }
    static func from(_ i: Int?) -> SQLiteDB.Value { i.map { .int(Int64($0)) } ?? .null }
    static func from(_ b: Bool) -> SQLiteDB.Value { .int(b ? 1 : 0) }
}
