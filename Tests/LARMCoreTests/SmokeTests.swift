import Testing
import Foundation
@testable import LARMCore

@Suite struct SmokeTests {
    @Test func sqliteRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("larm-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let db = try SQLiteDB(url: tmp)
        try db.exec("CREATE TABLE t(a TEXT, b INTEGER)")
        try db.run("INSERT INTO t VALUES(?, ?)", [.text("x"), .int(3)])
        let rows = try db.query("SELECT a, b FROM t")
        #expect(rows.first?["a"]?.string == "x")
        #expect(rows.first?["b"]?.int == 3)
    }

    @Test func hashing() {
        #expect(Hashing.sha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let a = Hashing.hmacHex(Data("v".utf8), key: Data(repeating: 1, count: 32))
        let b = Hashing.hmacHex(Data("v".utf8), key: Data(repeating: 2, count: 32))
        #expect(a != b)
    }
}
