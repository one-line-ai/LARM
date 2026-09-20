import Foundation

public struct Installation {
    public let installationID: String
    public let keyID: String
    public let appVersion: String
    public let osBuild: String
    public let createdAt: String
}

public enum InstallationStore {
    public static func loadOrCreate(db: SQLiteDB, keyID: String, appVersion: String, osBuild: String) throws -> Installation {
        if let r = try db.query("SELECT * FROM installation LIMIT 1").first {
            let stored = r["key_id"]?.string ?? ""
            if stored != keyID {
                try db.run("UPDATE installation SET key_id=?", [.text(keyID)])
                try Audit.record(db, kind: "key_rotated", detail: ["old_key_id": stored, "new_key_id": keyID])
            }
            return Installation(installationID: r["installation_id"]?.string ?? "", keyID: keyID,
                                appVersion: r["app_version"]?.string ?? "", osBuild: r["os_build"]?.string ?? "",
                                createdAt: r["created_at"]?.string ?? "")
        }
        let inst = Installation(installationID: Ids.new("inst"), keyID: keyID, appVersion: appVersion,
                                osBuild: osBuild, createdAt: Clock.nowUTC())
        try db.run("INSERT INTO installation VALUES(?,?,?,?,?)",
                   [.text(inst.installationID), .text(keyID), .text(appVersion), .text(osBuild), .text(inst.createdAt)])
        try Audit.record(db, kind: "installation_created", detail: ["installation_id": inst.installationID])
        return inst
    }
}

public enum Audit {
    public static func record(_ db: SQLiteDB, kind: String, detail: [String: String]) throws {
        let json = try JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys])
        try db.run("INSERT INTO audit(at, tz, kind, detail_json) VALUES(?,?,?,?)",
                   [.text(Clock.nowUTC()), .text(Clock.localTimeZoneID), .text(kind), .text(String(decoding: json, as: UTF8.self))])
    }
}
