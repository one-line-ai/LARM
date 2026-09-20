import Foundation

/// TOML 부분집합 파서.
/// 그 밖의 문법(멀티라인 문자열, 복잡한 이스케이프, 날짜 연산)은 unsupported로 던진다.
public enum MiniTOML {
    public static func parse(_ data: Data) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8) else { throw ParseError.invalid("UTF-8 아님") }
        var p = Parser(text)
        return try p.parseDocument()
    }

    struct Parser {
        let chars: [Character]
        var i = 0
        var root: [String: Any] = [:]
        var currentPath: [String] = []
        var definedTables = Set<String>()
        var arrayTables = Set<String>()

        init(_ s: String) { chars = Array(s) }

        var atEnd: Bool { i >= chars.count }
        func peek(_ k: Int = 0) -> Character? { i + k < chars.count ? chars[i + k] : nil }
        mutating func advance() { i += 1 }

        mutating func skipInlineWS() { while let c = peek(), c == " " || c == "\t" { advance() } }
        mutating func skipComment() { if peek() == "#" { while let c = peek(), c != "\n" { advance() } } }
        mutating func skipWSAndNewlines() {
            while true {
                skipInlineWS(); skipComment()
                if let c = peek(), c == "\n" || c == "\r" { advance() } else { break }
            }
        }
        mutating func expectLineEnd() throws {
            skipInlineWS(); skipComment()
            if atEnd { return }
            guard let c = peek(), c == "\n" || c == "\r" else { throw ParseError.invalid("줄 끝 기대, 위치 \(i)") }
            advance()
        }

        mutating func parseDocument() throws -> [String: Any] {
            while true {
                skipWSAndNewlines()
                guard !atEnd else { break }
                if peek() == "[" {
                    try parseTableHeader()
                } else {
                    let (keys, value) = try parseKeyValue()
                    try insert(path: currentPath + keys, value: value)
                    try expectLineEnd()
                }
            }
            return root
        }

        mutating func parseTableHeader() throws {
            advance()
            var isArray = false
            if peek() == "[" { isArray = true; advance() }
            skipInlineWS()
            let keys = try parseDottedKey()
            skipInlineWS()
            guard peek() == "]" else { throw ParseError.invalid("] 기대") }
            advance()
            if isArray { guard peek() == "]" else { throw ParseError.invalid("]] 기대") }; advance() }
            try expectLineEnd()
            let joined = keys.joined(separator: "\u{1F}")
            if isArray {
                arrayTables.insert(joined)
                appendArrayTable(path: keys)
                currentPath = keys
            } else {
                if definedTables.contains(joined) { throw ParseError.duplicateKey(keys.joined(separator: ".")) }
                definedTables.insert(joined)
                currentPath = keys
                try ensureTable(path: keys)
            }
        }

        mutating func parseDottedKey() throws -> [String] {
            var keys: [String] = []
            while true {
                skipInlineWS()
                keys.append(try parseSimpleKey())
                skipInlineWS()
                if peek() == "." { advance(); continue }
                return keys
            }
        }

        mutating func parseSimpleKey() throws -> String {
            guard let c = peek() else { throw ParseError.invalid("키 기대") }
            if c == "\"" { return try parseBasicString() }
            if c == "'" { return try parseLiteralString() }
            var out = ""
            while let ch = peek(), ch.isLetter || ch.isNumber || ch == "_" || ch == "-" { out.append(ch); advance() }
            guard !out.isEmpty else { throw ParseError.invalid("키 기대, 위치 \(i)") }
            return out
        }

        mutating func parseKeyValue() throws -> ([String], Any) {
            let keys = try parseDottedKey()
            skipInlineWS()
            guard peek() == "=" else { throw ParseError.invalid("= 기대, 키 \(keys.joined(separator: "."))") }
            advance(); skipInlineWS()
            let v = try parseValue()
            return (keys, v)
        }

        mutating func parseValue() throws -> Any {
            guard let c = peek() else { throw ParseError.invalid("값 기대") }
            switch c {
            case "\"":
                if peek(1) == "\"", peek(2) == "\"" { throw ParseError.unsupported("멀티라인 문자열") }
                return try parseBasicString()
            case "'":
                if peek(1) == "'", peek(2) == "'" { throw ParseError.unsupported("멀티라인 리터럴 문자열") }
                return try parseLiteralString()
            case "[": return try parseArray()
            case "{": return try parseInlineTable()
            case "t", "f":
                if matchWord("true") { return true }
                if matchWord("false") { return false }
                throw ParseError.invalid("불 값 기대")
            default:
                return try parseNumberOrDate()
            }
        }

        mutating func matchWord(_ w: String) -> Bool {
            let wc = Array(w)
            guard i + wc.count <= chars.count, Array(chars[i..<i+wc.count]) == wc else { return false }
            if i + wc.count < chars.count, let n = peek(wc.count), n.isLetter || n.isNumber { return false }
            i += wc.count; return true
        }

        mutating func parseBasicString() throws -> String {
            advance(); var out = ""
            while let c = peek() {
                if c == "\"" { advance(); return out }
                if c == "\n" { throw ParseError.invalid("문자열 안 줄바꿈") }
                if c == "\\" {
                    advance()
                    guard let e = peek() else { throw ParseError.invalid("이스케이프") }
                    switch e {
                    case "n": out.append("\n"); case "t": out.append("\t"); case "r": out.append("\r")
                    case "\"": out.append("\""); case "\\": out.append("\\"); case "b": out.append("\u{8}"); case "f": out.append("\u{C}")
                    case "u", "U":
                        let n = e == "u" ? 4 : 8
                        advance()
                        guard i + n <= chars.count, let code = UInt32(String(chars[i..<i+n]), radix: 16), let sc = Unicode.Scalar(code) else { throw ParseError.unsupported("유니코드 이스케이프") }
                        out.append(Character(sc)); i += n; continue
                    default: throw ParseError.unsupported("이스케이프 \\\(e)")
                    }
                    advance(); continue
                }
                out.append(c); advance()
            }
            throw ParseError.invalid("닫히지 않은 문자열")
        }

        mutating func parseLiteralString() throws -> String {
            advance(); var out = ""
            while let c = peek() {
                if c == "'" { advance(); return out }
                if c == "\n" { throw ParseError.invalid("문자열 안 줄바꿈") }
                out.append(c); advance()
            }
            throw ParseError.invalid("닫히지 않은 문자열")
        }

        mutating func parseArray() throws -> [Any] {
            advance(); var out: [Any] = []
            while true {
                skipWSAndNewlines()
                if peek() == "]" { advance(); return out }
                out.append(try parseValue())
                skipWSAndNewlines()
                if peek() == "," { advance(); continue }
                if peek() == "]" { advance(); return out }
                throw ParseError.invalid("배열 구분자 기대")
            }
        }

        mutating func parseInlineTable() throws -> [String: Any] {
            advance(); var out: [String: Any] = [:]
            skipInlineWS()
            if peek() == "}" { advance(); return out }
            while true {
                skipInlineWS()
                let (keys, v) = try parseKeyValue()
                try insertInto(&out, path: keys, value: v)
                skipInlineWS()
                if peek() == "," { advance(); continue }
                if peek() == "}" { advance(); return out }
                throw ParseError.invalid("인라인 테이블 구분자 기대")
            }
        }

        mutating func parseNumberOrDate() throws -> Any {
            var out = ""
            while let c = peek(), c.isNumber || c.isLetter || c == "." || c == "_" || c == "-" || c == "+" || c == ":" {
                out.append(c); advance()
            }
            if out.contains("T") || out.contains(":") || out.filter({ $0 == "-" }).count >= 2 { return out }
            let clean = out.replacingOccurrences(of: "_", with: "")
            if let iv = Int64(clean) { return iv }
            if let dv = Double(clean) { return dv }
            if clean == "inf" || clean == "+inf" || clean == "-inf" || clean == "nan" { return clean }
            throw ParseError.invalid("값 해석 불가: \(out.prefix(20))")
        }

        mutating func ensureTable(path: [String]) throws {
            try insert(path: path, value: [String: Any](), merge: true)
        }

        mutating func appendArrayTable(path: [String]) {
            var container = root
            func rec(_ dict: inout [String: Any], _ p: ArraySlice<String>) {
                guard let head = p.first else { return }
                if p.count == 1 {
                    var arr = dict[head] as? [[String: Any]] ?? []
                    arr.append([:]); dict[head] = arr
                } else {
                    var child = dict[head] as? [String: Any] ?? [:]
                    if var arr = dict[head] as? [[String: Any]], !arr.isEmpty {
                        var last = arr.removeLast(); rec(&last, p.dropFirst()); arr.append(last); dict[head] = arr; return
                    }
                    rec(&child, p.dropFirst()); dict[head] = child
                }
            }
            rec(&container, path[...])
            root = container
        }

        mutating func insert(path: [String], value: Any, merge: Bool = false) throws {
            var r = root
            try Parser.insertRec(&r, path[...], value, merge: merge)
            root = r
        }

        func insertInto(_ dict: inout [String: Any], path: [String], value: Any) throws {
            try Parser.insertRec(&dict, path[...], value, merge: false)
        }

        static func insertRec(_ dict: inout [String: Any], _ p: ArraySlice<String>, _ value: Any, merge: Bool) throws {
            guard let head = p.first else { return }
            if p.count == 1 {
                if let existing = dict[head] {
                    if merge, existing is [String: Any] { return }
                    throw ParseError.duplicateKey(head)
                }
                dict[head] = value; return
            }
            if var arr = dict[head] as? [[String: Any]], !arr.isEmpty {
                var last = arr.removeLast()
                try insertRec(&last, p.dropFirst(), value, merge: merge)
                arr.append(last); dict[head] = arr; return
            }
            var child = dict[head] as? [String: Any] ?? [:]
            if dict[head] != nil, !(dict[head] is [String: Any]) { throw ParseError.duplicateKey(head) }
            try insertRec(&child, p.dropFirst(), value, merge: merge)
            dict[head] = child
        }
    }
}
