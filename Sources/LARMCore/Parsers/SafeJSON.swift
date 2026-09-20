import Foundation

public enum ParseError: Error, CustomStringConvertible, Sendable {
    case duplicateKey(String)
    case invalid(String)
    case unsupported(String)
    case tooDeep
    public var description: String {
        switch self {
        case .duplicateKey(let k): return "중복 키: \(k)"
        case .invalid(let s): return "구문 오류: \(s)"
        case .unsupported(let s): return "미지원 문법: \(s)"
        case .tooDeep: return "중첩 깊이 초과"
        }
    }
}

/// 안전한 JSON 파싱.
public enum SafeJSON {
    public static func parse(_ data: Data, maxDepth: Int = 32) throws -> Any {
        guard let text = String(data: data, encoding: .utf8) else { throw ParseError.invalid("UTF-8 아님") }
        try scanDuplicates(text, maxDepth: maxDepth)
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ParseError.invalid((error as NSError).localizedDescription)
        }
    }

    /// 단순 스캐너: 객체마다 키 집합을 추적해 중복을 찾는다.
    static func scanDuplicates(_ s: String, maxDepth: Int) throws {
        var stack: [Set<String>?] = []   // nil = array
        var i = s.startIndex
        var expectKey = false
        func skipWS() { while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) } }
        func readString() throws -> String {
            var out = ""; i = s.index(after: i)
            while i < s.endIndex {
                let c = s[i]
                if c == "\\" { i = s.index(after: i); if i < s.endIndex { out.append(s[i]); i = s.index(after: i) }; continue }
                if c == "\"" { i = s.index(after: i); return out }
                out.append(c); i = s.index(after: i)
            }
            throw ParseError.invalid("닫히지 않은 문자열")
        }
        while i < s.endIndex {
            skipWS(); guard i < s.endIndex else { break }
            let c = s[i]
            switch c {
            case "{":
                stack.append(Set()); expectKey = true; i = s.index(after: i)
                if stack.count > maxDepth { throw ParseError.tooDeep }
            case "[":
                stack.append(nil); expectKey = false; i = s.index(after: i)
                if stack.count > maxDepth { throw ParseError.tooDeep }
            case "}", "]":
                _ = stack.popLast(); i = s.index(after: i); expectKey = false
            case ",":
                i = s.index(after: i); expectKey = (stack.last ?? nil) != nil
            case ":":
                i = s.index(after: i); expectKey = false
            case "\"":
                let str = try readString()
                if expectKey, let top = stack.indices.last, stack[top] != nil {
                    if stack[top]!.contains(str) { throw ParseError.duplicateKey(str) }
                    stack[top]!.insert(str)
                    expectKey = false
                }
            default:
                i = s.index(after: i)
            }
        }
    }
}
