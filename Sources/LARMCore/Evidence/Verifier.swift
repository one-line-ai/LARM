import Foundation

/// 오프라인 증빙 검증기.
public struct VerifyReport: Sendable {
    public struct Check: Sendable { public let name: String; public let pass: Bool; public let detail: String }
    public var checks: [Check] = []
    public var ok: Bool { checks.allSatisfy { $0.pass } }
    public var exportID: String = ""
    public var schema: String = ""
    public var generatedAt: String = ""
    public var fileCount: Int = 0
    public let limitation = "검증 성공은 묶음 내부의 파일 일관성 확인입니다. 생성자 신원, 확인 사실의 진실성, 생성 시점의 공증, 악성 여부, 법규 준수를 증명하지 않습니다. manifest까지 재작성한 위조는 독립 매체에 보관한 기준 해시 없이는 검출할 수 없습니다."
}

public enum Verifier {
    public static let supportedSchemas = ["larm-evidence/1.1"]

    public static func verify(zip: Data, expectedManifestSHA256: String? = nil) -> VerifyReport {
        var r = VerifyReport()
        func check(_ name: String, _ pass: Bool, _ detail: String = "") { r.checks.append(.init(name: name, pass: pass, detail: detail)) }
        let headers: [ZipReader.Header]
        do { headers = try ZipReader.centralDirectory(zip) } catch { check("ZIP 구조", false, "\(error)"); return r }
        check("ZIP 구조", true, "\(headers.count)개 항목")
        r.fileCount = headers.count
        var seen = Set<String>()
        var dup: [String] = [], bad: [String] = [], links: [String] = [], methods: [String] = []
        for h in headers {
            if !seen.insert(h.path).inserted { dup.append(h.path) }
            if h.path.hasPrefix("/") || h.path.split(separator: "/").contains("..") || h.path.contains("\\") || h.path.hasSuffix("/") { bad.append(h.path) }
            if (h.externalAttrs >> 16) & 0o170000 == 0o120000 { links.append(h.path) }
            if h.method != 0 { methods.append(h.path) }
        }
        check("중복 ZIP 경로 없음", dup.isEmpty, dup.joined(separator: ", "))
        check("절대경로·상위 이동·디렉터리 없음", bad.isEmpty, bad.joined(separator: ", "))
        check("심볼릭 링크 없음", links.isEmpty, links.joined(separator: ", "))
        check("저장 방식만 사용", methods.isEmpty, methods.joined(separator: ", "))
        guard dup.isEmpty, bad.isEmpty, links.isEmpty, methods.isEmpty else { return r }
        guard let mh = headers.first(where: { $0.path == "manifest.json" }) else { check("manifest.json 존재", false); return r }
        let manifestData: Data
        do { manifestData = try ZipReader.extract(zip, mh) } catch { check("manifest.json 읽기", false, "\(error)"); return r }
        if let exp = expectedManifestSHA256 {
            let actual = Hashing.sha256Hex(manifestData)
            check("manifest 기준 해시 일치", actual == exp.lowercased(), actual)
        } else {
            check("manifest 기준 해시", true, "기준 해시 미제공: manifest 재작성 위조는 검출 불가")
        }
        let manifest: [String: Any]
        do {
            guard let m = try SafeJSON.parse(manifestData) as? [String: Any] else { check("manifest 구문", false, "객체 아님"); return r }
            manifest = m
        } catch { check("manifest 구문 (중복 키 금지)", false, "\(error)"); return r }
        check("manifest 구문 (중복 키 금지)", true)
        let schema = manifest["schema_version"] as? String ?? ""
        r.schema = schema; r.exportID = manifest["export_id"] as? String ?? ""; r.generatedAt = manifest["generated_at"] as? String ?? ""
        check("schema 지원", supportedSchemas.contains(schema), schema)
        guard supportedSchemas.contains(schema) else { return r }
        guard let files = manifest["files"] as? [[String: Any]] else { check("files 목록", false); return r }
        let listed = Dictionary(files.compactMap { f -> (String, (Int, String))? in
            guard let p = f["path"] as? String, let s = f["size"] as? Int, let h = f["sha256"] as? String else { return nil }
            return (p, (s, h))
        }, uniquingKeysWith: { a, _ in a })
        check("manifest 항목 형식", listed.count == files.count, "\(listed.count)/\(files.count)")
        let inZip = Set(headers.map { $0.path }).subtracting(["manifest.json"])
        let missing = Set(listed.keys).subtracting(inZip).sorted()
        let extra = inZip.subtracting(listed.keys).sorted()
        check("누락 파일 없음", missing.isEmpty, missing.joined(separator: ", "))
        check("숨은 추가 파일 없음", extra.isEmpty, extra.joined(separator: ", "))
        var mismatched: [String] = []
        for h in headers where h.path != "manifest.json" {
            guard let (size, sha) = listed[h.path] else { continue }
            do {
                let d = try ZipReader.extract(zip, h)
                if d.count != size || Hashing.sha256Hex(d) != sha.lowercased() { mismatched.append(h.path) }
                if h.path.hasSuffix(".json") { _ = try SafeJSON.parse(d) }
            } catch { mismatched.append("\(h.path) (\(error))") }
        }
        check("크기·SHA-256 일치 및 JSON 중복 키 없음", mismatched.isEmpty, mismatched.joined(separator: ", "))
        return r
    }

    public static func render(_ r: VerifyReport) -> String {
        var s = ["LARM 증빙 검증 결과: \(r.ok ? "성공 (묶음 내부의 파일 일관성을 확인했습니다)" : "실패")",
                 "export_id=\(r.exportID) schema=\(r.schema) generated_at=\(r.generatedAt) files=\(r.fileCount)"]
        for c in r.checks { s.append("  [\(c.pass ? "PASS" : "FAIL")] \(c.name)\(c.detail.isEmpty ? "" : ": \(c.detail)")") }
        s.append("한계: \(r.limitation)")
        return s.joined(separator: "\n")
    }
}
