import Testing
import Foundation
@testable import LARMCore

@Suite struct ParserTests {
    @Test func tomlParsesCodexStyleConfig() throws {
        let d = try Data(contentsOf: URL(fileURLWithPath: Fx.path("home-risky/.codex/config.toml")))
        let t = try MiniTOML.parse(d)
        #expect(t["approval_policy"] as? String == "never")
        let mcp = t["mcp_servers"] as? [String: Any]
        let repl = mcp?["node_repl"] as? [String: Any]
        #expect((repl?["args"] as? [Any])?.count == 1)
        #expect((repl?["env"] as? [String: Any])?["NODE_PATH"] as? String == "/opt/node")
        #expect(repl?["startup_timeout_sec"] as? Int64 == 30)
        let plugins = t["plugins"] as? [String: Any]
        #expect((plugins?["browser@openai-bundled"] as? [String: Any])?["enabled"] as? Bool == true)
        let projects = t["projects"] as? [String: Any]
        #expect((projects?["/Users/test/proj"] as? [String: Any])?["trust_level"] as? String == "trusted")
    }

    @Test func tomlRejectsDuplicateAndUnsupported() {
        #expect(throws: ParseError.self) { try MiniTOML.parse(Data("a = 1\na = 2\n".utf8)) }
        #expect(throws: ParseError.self) { try MiniTOML.parse(Data("a = \"\"\"multi\nline\"\"\"\n".utf8)) }
        #expect(throws: ParseError.self) { try MiniTOML.parse(Data("[t]\nx=1\n[t]\ny=2\n".utf8)) }
    }

    @Test func tomlInlineTableAndArrayTable() throws {
        let t = try MiniTOML.parse(Data("it = { x = 1, y = [1, 2] }\n[[srv]]\nname = \"a\"\n[[srv]]\nname = \"b\"\n".utf8))
        #expect((t["srv"] as? [[String: Any]])?.count == 2)
        #expect(((t["it"] as? [String: Any])?["y"] as? [Any])?.count == 2)
    }

    @Test func jsonDuplicateKeyDetected() {
        #expect(throws: ParseError.self) { try SafeJSON.parse(Data("{\"a\":1,\"b\":{\"c\":1,\"c\":2}}".utf8)) }
        #expect(throws: Never.self) { try SafeJSON.parse(Data("{\"a\":{\"c\":1},\"b\":{\"c\":2}, \"s\":\"}\\\"{\"}".utf8)) }
    }
}
