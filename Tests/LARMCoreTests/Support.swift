import Foundation
@testable import LARMCore

enum Fx {
    static var root: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    }
    static func path(_ rel: String) -> String { root.appendingPathComponent(rel).path }

    static let key = Data(repeating: 0x42, count: 32)
    static var redactor: Redactor { Redactor(hmacKey: key) }
    static var rules: RuleSet { try! RuleLoader.loadBundled() }

    static func scopes(home: String, projects: [String]) -> [Scope] {
        [Scope(scopeID: "scope_user", alias: "user", realPath: path(home), kind: .userRoot)] +
        projects.enumerated().map { Scope(scopeID: "scope_p\($0.offset)", alias: $0.element, realPath: path($0.element), kind: .project) }
    }

    static func scan(home: String, projects: [String] = []) -> ScanResult {
        Scanner(rules: rules, redactor: redactor).run(scopes: scopes(home: home, projects: projects))
    }

    static func tempDB() throws -> SQLiteDB {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("larm-\(UUID().uuidString).sqlite")
        let db = try SQLiteDB(url: u); try Schema.migrate(db); return db
    }

    static let copyLock = NSLock()
    /// fixture 트리를 임시 폴더로 복사 (수정 시험용).
    static func copyToTemp(_ rel: String) throws -> String {
        copyLock.lock(); defer { copyLock.unlock() }
        var lastError: Error?
        for _ in 0..<5 {
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("larm-fx-\(UUID().uuidString)")
            do { try FileManager.default.copyItem(atPath: path(rel), toPath: dst.path); return dst.path }
            catch { lastError = error; try? FileManager.default.removeItem(at: dst); usleep(50_000) }
        }
        throw lastError!
    }
}

/// 합성 비밀정보 canary. 저장소에 토큰 형태의 문자열을 두지 않으려고 실행 시점에 만든다.
enum Canary {
    struct RNG { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 } }
    static func rnd(_ n: Int, _ alphabet: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", rng: inout RNG) -> String {
        let a = Array(alphabet); return String((0..<n).map { _ in a[Int(rng.next() % UInt64(a.count))] })
    }
    static var positives: [String] {
        var g = RNG(s: 7); var out: [String] = []
        let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", digits = "0123456789"
        for _ in 0..<4 { out.append("sk-ant-api03-LARM_CANARY_" + rnd(40, rng: &g)) }
        for _ in 0..<3 { out.append("sk-proj-LARM_CANARY_" + rnd(40, rng: &g)) }
        for _ in 0..<2 { out.append("sk-LARM_CANARY_" + rnd(40, rng: &g)) }
        for _ in 0..<3 { out.append("ghp_" + rnd(36, rng: &g)) }
        for _ in 0..<2 { out.append("github_pat_" + rnd(22, rng: &g) + "_" + rnd(59, rng: &g)) }
        for _ in 0..<3 { out.append("AKIA" + rnd(16, upper, rng: &g)) }
        for _ in 0..<3 { out.append("AIza" + rnd(35, rng: &g)) }
        for _ in 0..<3 { out.append("xox" + "b-" + rnd(12, digits, rng: &g) + "-" + rnd(24, rng: &g)) }
        for _ in 0..<2 { out.append("sk_live_" + rnd(24, rng: &g)) }
        for _ in 0..<2 { out.append("rk_test_" + rnd(24, rng: &g)) }
        for _ in 0..<3 { out.append("eyJ" + rnd(20, rng: &g) + ".eyJ" + rnd(30, rng: &g) + "." + rnd(43, rng: &g)) }
        for _ in 0..<2 { out.append("-----BEGIN RSA PRIVATE KEY-----\nMIIE" + rnd(60, rng: &g) + "\n-----END RSA PRIVATE KEY-----") }
        for _ in 0..<2 { out.append("npm_" + rnd(36, rng: &g)) }
        for _ in 0..<2 { out.append("hf_" + rnd(34, rng: &g)) }
        for _ in 0..<2 { out.append("ntn_" + rnd(43, rng: &g)) }
        for _ in 0..<2 { out.append("LARM_CANARY_" + rnd(24, rng: &g)) }
        return out
    }
    static var negatives: [String] {
        var out = ["${OPENAI_API_KEY}", "$ANTHROPIC_API_KEY", "${HOME}/.config", "true", "false", "3000", "http://localhost:3000/mcp", "https://api.example.com/v1",
                   "/usr/local/bin/node", "npx", "-y", "@modelcontextprotocol/server-filesystem", "vim", "en_US.UTF-8", "claude-sonnet-5", "gpt-5", "workspace-write",
                   "on-request", "default", "acceptEdits", "Bash(git status *)", "Read(~/Documents/**)", "/Users/test/proj", "postgresql://localhost/db", "utf-8",
                   "2026-09-20T00:00:00Z", "1.2.3", "a very normal sentence with spaces in it", "README.md", "main", "origin", "--verbose", "--log-level=debug",
                   "com.onelineai.larm", "hello world", "password", "token", "secret", "apikey", "Authorization", "Bearer", "Content-Type", "application/json",
                   "x-request-id", "sha256", "deadbeef", "00000000-0000-0000-0000-000000000000", "us-east-1", "arn:aws:iam::123456789012:role/x"]
        while out.count < 100 { out.append("word\(out.count)") }
        return out
    }
}
