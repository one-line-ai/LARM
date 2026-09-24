import Foundation

/// 스키마 마이그레이션.
public enum Schema {
    public static let current = 5

    static let v1: [String] = [
        """
        CREATE TABLE IF NOT EXISTS installation(
          installation_id TEXT PRIMARY KEY,
          key_id TEXT NOT NULL,
          app_version TEXT NOT NULL,
          os_build TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS audit(
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          at TEXT NOT NULL,
          tz TEXT NOT NULL,
          kind TEXT NOT NULL,
          detail_json TEXT NOT NULL
        )
        """,
    ]


    static let v2: [String] = [
        """
        CREATE TABLE IF NOT EXISTS scope(
          scope_id TEXT PRIMARY KEY, alias TEXT NOT NULL, real_path TEXT NOT NULL, kind TEXT NOT NULL,
          excluded INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS scan(
          scan_id TEXT PRIMARY KEY, sequence INTEGER NOT NULL UNIQUE, scope_digest TEXT NOT NULL, kind TEXT NOT NULL,
          status TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT NOT NULL, tz TEXT NOT NULL,
          adapter_versions_json TEXT NOT NULL, rule_version TEXT NOT NULL, notes_json TEXT NOT NULL,
          counts_json TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS coverage(
          scan_id TEXT NOT NULL REFERENCES scan(scan_id) ON DELETE CASCADE, adapter TEXT NOT NULL, adapter_version TEXT NOT NULL,
          scope_id TEXT NOT NULL, item_alias TEXT NOT NULL, status TEXT NOT NULL, reason TEXT NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_coverage_scan ON coverage(scan_id)",
        """
        CREATE TABLE IF NOT EXISTS observation(
          observation_id TEXT NOT NULL, scan_id TEXT NOT NULL REFERENCES scan(scan_id) ON DELETE CASCADE,
          object_id TEXT NOT NULL, object_type TEXT NOT NULL, field TEXT NOT NULL, safe_value TEXT NOT NULL,
          value_kind TEXT NOT NULL, provenance_json TEXT NOT NULL, secret_fp TEXT
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_observation_scan ON observation(scan_id, object_id)",
        """
        CREATE TABLE IF NOT EXISTS finding(
          finding_id TEXT PRIMARY KEY, rule_id TEXT NOT NULL, rule_version TEXT NOT NULL, object_id TEXT NOT NULL,
          object_type TEXT NOT NULL, target_fp TEXT NOT NULL, severity TEXT NOT NULL, confidence TEXT NOT NULL,
          title TEXT NOT NULL, summary TEXT NOT NULL, evidence_json TEXT NOT NULL, limits_text TEXT NOT NULL,
          next_action_text TEXT NOT NULL, scope_id TEXT NOT NULL, location_alias TEXT NOT NULL,
          state TEXT NOT NULL, first_scan_id TEXT NOT NULL, last_scan_id TEXT NOT NULL, seen_count INTEGER NOT NULL,
          opened_at TEXT NOT NULL, updated_at TEXT NOT NULL, verify_status TEXT NOT NULL DEFAULT 'verified',
          UNIQUE(rule_id, target_fp)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_finding_state ON finding(state, severity)",
        """
        CREATE TABLE IF NOT EXISTS finding_event(
          seq INTEGER PRIMARY KEY AUTOINCREMENT, finding_id TEXT NOT NULL, at TEXT NOT NULL, kind TEXT NOT NULL,
          from_state TEXT, to_state TEXT, scan_id TEXT, actor TEXT NOT NULL, note TEXT NOT NULL
        )
        """,
    ]


    static let v3: [String] = [
        """
        CREATE TABLE IF NOT EXISTS snapshot(
          snapshot_id TEXT PRIMARY KEY, scan_id TEXT NOT NULL UNIQUE REFERENCES scan(scan_id) ON DELETE CASCADE,
          content_digest TEXT NOT NULL, secret_digest TEXT NOT NULL, scope_digest TEXT NOT NULL, key_id TEXT NOT NULL, created_at TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS decision(
          decision_id TEXT PRIMARY KEY, kind TEXT NOT NULL, finding_id TEXT, target_fp TEXT, scan_id TEXT, object_id TEXT,
          actor_alias TEXT NOT NULL, reason TEXT NOT NULL, created_at TEXT NOT NULL, expires_at TEXT, rule_version TEXT NOT NULL,
          evidence_digest TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_decision_kind ON decision(kind, active)",
        """
        CREATE TABLE IF NOT EXISTS export(
          export_id TEXT PRIMARY KEY, created_at TEXT NOT NULL, scan_ids_json TEXT NOT NULL, filters_json TEXT NOT NULL,
          schema TEXT NOT NULL, manifest_sha256 TEXT NOT NULL, file_count INTEGER NOT NULL, out_alias TEXT NOT NULL
        )
        """,
        "CREATE TABLE IF NOT EXISTS setting(key TEXT PRIMARY KEY, value TEXT NOT NULL)",
    ]


    static let v4: [String] = [
        """
        CREATE TABLE IF NOT EXISTS coverage_gap(
          gap_id TEXT PRIMARY KEY, surface TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT, reason TEXT NOT NULL,
          lost_count INTEGER NOT NULL DEFAULT 0, recovery_evidence TEXT NOT NULL DEFAULT '', tz TEXT NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_gap_open ON coverage_gap(ended_at)",
        """
        CREATE TABLE IF NOT EXISTS notification_log(
          dedupe_key TEXT PRIMARY KEY, first_at TEXT NOT NULL, last_sent_at TEXT NOT NULL, suppressed_count INTEGER NOT NULL DEFAULT 0, source_count INTEGER NOT NULL DEFAULT 1
        )
        """,
    ]


    static let v5: [String] = [
        """
        CREATE TABLE IF NOT EXISTS runtime_event(
          event_id TEXT PRIMARY KEY, source_event_id TEXT NOT NULL, dedupe_key TEXT NOT NULL UNIQUE, source_kind TEXT NOT NULL,
          phase TEXT NOT NULL, hook_event_name TEXT NOT NULL, tool_name TEXT NOT NULL, target_kind TEXT NOT NULL, target_alias TEXT NOT NULL,
          scope_id TEXT, outside_scope INTEGER NOT NULL DEFAULT 0, command_basename TEXT, argc INTEGER NOT NULL, arg_fp TEXT NOT NULL,
          flags_json TEXT NOT NULL, session_ref TEXT NOT NULL, process_ref TEXT NOT NULL, observed_at TEXT NOT NULL, received_at TEXT NOT NULL,
          seq INTEGER NOT NULL, delivery TEXT NOT NULL, result_present INTEGER NOT NULL DEFAULT 0,
          risk_rule TEXT, risk_version TEXT, risk_outcome TEXT, risk_severity TEXT, risk_summary TEXT, risk_limits TEXT, risk_next TEXT,
          ack_state TEXT NOT NULL DEFAULT 'observed', duplicate_count INTEGER NOT NULL DEFAULT 0
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_event_seq ON runtime_event(seq DESC)",
        "CREATE INDEX IF NOT EXISTS idx_event_source ON runtime_event(source_event_id)",
    ]

    public static func migrate(_ db: SQLiteDB) throws {
        let v = db.userVersion
        if v < 1 {
            try db.transaction {
                for s in v1 { try db.exec(s) }
                try db.setUserVersion(1)
            }
        }
        if db.userVersion < 2 {
            try db.transaction {
                for s in v2 { try db.exec(s) }
                try db.setUserVersion(2)
            }
        }
        if db.userVersion < 3 {
            try db.transaction {
                for s in v3 { try db.exec(s) }
                try db.setUserVersion(3)
            }
        }
        if db.userVersion < 4 {
            try db.transaction {
                for s in v4 { try db.exec(s) }
                try db.setUserVersion(4)
            }
        }
        if db.userVersion < 5 {
            try db.transaction {
                for s in v5 { try db.exec(s) }
                try db.setUserVersion(5)
            }
        }
        if db.userVersion > current {
            throw NSError(domain: "LARM", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "데이터베이스 형식(v\(db.userVersion))가 이 앱(v\(current))보다 최신임. 최신 앱으로 여기"])
        }
    }
}
