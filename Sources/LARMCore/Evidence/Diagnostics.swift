import Foundation

/// 진단 파일.
public enum Diagnostics {
    public static func build(db: SQLiteDB, appVersion: String, osBuild: String, rulesVersion: String, extra: [String: String] = [:]) -> String {
        var lines = ["LARM 진단 (자동 전송 없음)", "generated_at=\(Clock.nowUTC()) tz=\(Clock.localTimeZoneID)",
                     "app=\(appVersion) os=\(osBuild) rules=\(rulesVersion) schema_db=\(db.userVersion) evidence=\(Exporter.schema) ontology=\(Ontology.version)"]
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { lines.append("\(k)=\(Redactor.scrub(v))") }
        if let scans = try? ScanRepo.list(db, limit: 5) {
            for s in scans { lines.append("scan seq=\(s.sequence) kind=\(s.kind) status=\(s.status.rawValue) ended=\(s.endedAt) rules=\(s.rulesVersion) gaps=\(s.counts["gaps"] ?? 0)") }
        }
        if let cov = try? ScanRepo.latestCompletedOrPartial(db).flatMap({ try ScanRepo.coverage(db, scanID: $0.scanID) }) {
            let byStatus = Dictionary(grouping: cov, by: { $0.status.rawValue }).mapValues { $0.count }
            lines.append("coverage=" + byStatus.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))
            for c in cov where c.status != .success && c.status != .absent { lines.append("gap adapter=\(c.adapter) status=\(c.status.rawValue) reason=\(Redactor.scrub(c.reason))") }
        }
        if let gaps = try? CoverageGapRepo.recent(db, limit: 10) {
            for g in gaps { lines.append("watch_gap surface=\(g.surface) reason=\(g.reason) start=\(g.startedAt) end=\(g.endedAt ?? "open")") }
        }
        if let audits = try? db.query("SELECT at, kind FROM audit ORDER BY seq DESC LIMIT 20") {
            for a in audits { lines.append("audit \(a["at"]?.string ?? "") \(a["kind"]?.string ?? "")") }
        }
        let text = lines.joined(separator: "\n") + "\n"
        return text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
