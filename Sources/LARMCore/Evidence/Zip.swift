import Foundation

/// 최소 ZIP 구현 (저장 방식만, 압축 없음).
public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
    public static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}

public enum ZipError: Error, CustomStringConvertible {
    case invalid(String), unsupported(String), tooLarge
    public var description: String {
        switch self { case .invalid(let s): return "ZIP 형식 오류: \(s)"; case .unsupported(let s): return "미지원 ZIP 기능: \(s)"; case .tooLarge: return "ZIP이 너무 큽니다" }
    }
}

public struct ZipEntry: Sendable, Equatable {
    public let path: String
    public let data: Data
    public init(path: String, data: Data) { self.path = path; self.data = data }
}

public enum ZipWriter {
    public static func write(_ entries: [ZipEntry]) throws -> Data {
        var out = Data()
        var central = Data()
        let dosTime: UInt16 = 0, dosDate: UInt16 = 0x21
        for e in entries {
            guard let name = e.path.data(using: .utf8), !e.path.hasPrefix("/"), !e.path.contains("..") else { throw ZipError.invalid("경로 \(e.path)") }
            guard e.data.count < 0xFFFF_FFFF, out.count < 0xFFFF_FFF0 else { throw ZipError.tooLarge }
            let crc = CRC32.checksum(e.data)
            let offset = UInt32(out.count)
            var lh = Data()
            lh.append(le32(0x04034b50)); lh.append(le16(20)); lh.append(le16(0x0800)); lh.append(le16(0))
            lh.append(le16(dosTime)); lh.append(le16(dosDate)); lh.append(le32(crc))
            lh.append(le32(UInt32(e.data.count))); lh.append(le32(UInt32(e.data.count)))
            lh.append(le16(UInt16(name.count))); lh.append(le16(0)); lh.append(name)
            out.append(lh); out.append(e.data)
            var ch = Data()
            ch.append(le32(0x02014b50)); ch.append(le16(0x0314)); ch.append(le16(20)); ch.append(le16(0x0800)); ch.append(le16(0))
            ch.append(le16(dosTime)); ch.append(le16(dosDate)); ch.append(le32(crc))
            ch.append(le32(UInt32(e.data.count))); ch.append(le32(UInt32(e.data.count)))
            ch.append(le16(UInt16(name.count))); ch.append(le16(0)); ch.append(le16(0)); ch.append(le16(0)); ch.append(le16(0))
            ch.append(le32(UInt32(0o100600) << 16)); ch.append(le32(offset)); ch.append(name)
            central.append(ch)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        var eocd = Data()
        eocd.append(le32(0x06054b50)); eocd.append(le16(0)); eocd.append(le16(0))
        eocd.append(le16(UInt16(entries.count))); eocd.append(le16(UInt16(entries.count)))
        eocd.append(le32(UInt32(central.count))); eocd.append(le32(cdOffset)); eocd.append(le16(0))
        out.append(eocd)
        return out
    }

    static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}

/// 검증기용 리더.
public enum ZipReader {
    public struct Header: Sendable {
        public let path: String
        public let method: UInt16
        public let crc: UInt32
        public let compressedSize: UInt32
        public let size: UInt32
        public let localOffset: UInt32
        public let externalAttrs: UInt32
        public let flags: UInt16
    }

    public static func centralDirectory(_ d: Data) throws -> [Header] {
        guard d.count >= 22 else { throw ZipError.invalid("너무 작음") }
        var eocd = -1
        var i = d.count - 22
        while i >= max(0, d.count - 22 - 0xFFFF) {
            if u32(d, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.invalid("EOCD 없음") }
        let count = Int(u16(d, eocd + 10))
        let cdSize = Int(u32(d, eocd + 12)), cdOff = Int(u32(d, eocd + 16))
        guard u16(d, eocd + 8) == UInt16(count), u16(d, eocd + 4) == 0 else { throw ZipError.unsupported("다중 디스크") }
        if count == 0xFFFF || cdOff == 0xFFFF_FFFF { throw ZipError.unsupported("ZIP64") }
        guard cdOff + cdSize <= eocd else { throw ZipError.invalid("중앙 디렉터리 범위") }
        var headers: [Header] = []
        var p = cdOff
        for _ in 0..<count {
            guard p + 46 <= d.count, u32(d, p) == 0x02014b50 else { throw ZipError.invalid("중앙 디렉터리 항목") }
            let flags = u16(d, p + 8), method = u16(d, p + 10), crc = u32(d, p + 16)
            let csize = u32(d, p + 20), size = u32(d, p + 24)
            let nlen = Int(u16(d, p + 28)), xlen = Int(u16(d, p + 30)), clen = Int(u16(d, p + 32))
            let ext = u32(d, p + 38), off = u32(d, p + 42)
            guard p + 46 + nlen <= d.count else { throw ZipError.invalid("이름 길이") }
            guard let name = String(data: d[(p + 46)..<(p + 46 + nlen)], encoding: .utf8) else { throw ZipError.invalid("이름 인코딩") }
            headers.append(Header(path: name, method: method, crc: crc, compressedSize: csize, size: size, localOffset: off, externalAttrs: ext, flags: flags))
            p += 46 + nlen + xlen + clen
        }
        return headers
    }

    public static func extract(_ d: Data, _ h: Header) throws -> Data {
        guard h.method == 0 else { throw ZipError.unsupported("압축 방식 \(h.method) (저장 방식만 허용)") }
        guard h.flags & 0x0008 == 0 else { throw ZipError.unsupported("data descriptor") }
        let p = Int(h.localOffset)
        guard p + 30 <= d.count, u32(d, p) == 0x04034b50 else { throw ZipError.invalid("로컬 헤더") }
        let nlen = Int(u16(d, p + 26)), xlen = Int(u16(d, p + 28))
        let start = p + 30 + nlen + xlen
        let end = start + Int(h.size)
        guard end <= d.count, h.size == h.compressedSize else { throw ZipError.invalid("데이터 범위 \(h.path)") }
        let body = d[start..<end]
        guard CRC32.checksum(Data(body)) == h.crc else { throw ZipError.invalid("CRC 불일치 \(h.path)") }
        return Data(body)
    }

    static func u16(_ d: Data, _ i: Int) -> UInt16 { UInt16(d[d.startIndex + i]) | (UInt16(d[d.startIndex + i + 1]) << 8) }
    static func u32(_ d: Data, _ i: Int) -> UInt32 {
        UInt32(d[d.startIndex + i]) | (UInt32(d[d.startIndex + i + 1]) << 8) | (UInt32(d[d.startIndex + i + 2]) << 16) | (UInt32(d[d.startIndex + i + 3]) << 24)
    }
}

/// 안정된 JSON 직렬화: 키 정렬, UTF-8, 슬래시 비이스케이프, 실수 금지.
public enum StableJSON {
    public static func data(_ obj: Any) throws -> Data {
        try validate(obj)
        return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }
    static func validate(_ v: Any) throws {
        switch v {
        case is String, is Int, is Int64, is Bool, is NSNull: return
        case let n as NSNumber:
            if CFNumberIsFloatType(n) { throw ZipError.invalid("실수 값은 증빙에 넣지 않습니다") }
        case let a as [Any]: for x in a { try validate(x) }
        case let d as [String: Any]: for (_, x) in d { try validate(x) }
        default: throw ZipError.invalid("직렬화 불가 타입 \(type(of: v))")
        }
    }
}
