import Foundation

/// Unix 소켓 전송 + spool 대체.
public enum HookTransport {
    public static let timeoutMS: Int32 = 150

    @discardableResult
    public static func deliver(_ event: HookEvent, socketPath: String, spoolDir: String) -> String {
        guard let data = try? JSONEncoder().encode(event) else { return "lost" }
        if sendOverSocket(data + Data("\n".utf8), path: socketPath) { return "socket" }
        return spool(data, dir: spoolDir) ? "spool" : "lost"
    }

    static func sendOverSocket(_ data: Data, path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var tv = timeval(tv_sec: 0, tv_usec: Int32(timeoutMS) * 1000)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 104) { cp in
                for (i, b) in bytes.enumerated() { cp[i] = CChar(bitPattern: b) }
                cp[bytes.count] = 0
            }
        }
        let len = socklen_t(MemoryLayout<sa_family_t>.size + MemoryLayout<UInt8>.size + bytes.count + 1)
        let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) } }
        guard rc == 0 else { return false }
        var sent = 0
        let total = data.count
        let ok: Bool = data.withUnsafeBytes { buf in
            while sent < total {
                let n = write(fd, buf.baseAddress! + sent, total - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
        guard ok else { return false }
        var ack: UInt8 = 0
        return read(fd, &ack, 1) == 1 && ack == 0x06
    }

    static func spool(_ data: Data, dir: String) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) { try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).json"
        return fm.createFile(atPath: dir + "/" + name, contents: data, attributes: [.posixPermissions: 0o600])
    }
}

/// 앱 쪽 수신 서버.
public final class HookSocketServer {
    public typealias Handler = @Sendable (Data) -> Void
    private var fd: Int32 = -1
    private let path: String
    private let handler: Handler
    private var thread: Thread?
    public private(set) var isListening = false
    public private(set) var lastAcceptAt: Date?
    public private(set) var acceptedCount = 0

    public init(path: String, handler: @escaping Handler) { self.path = path; self.handler = handler }

    public func start() -> Bool {
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < 104 else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 104) { cp in
                for (i, b) in bytes.enumerated() { cp[i] = CChar(bitPattern: b) }
                cp[bytes.count] = 0
            }
        }
        let len = socklen_t(MemoryLayout<sa_family_t>.size + MemoryLayout<UInt8>.size + bytes.count + 1)
        let old = umask(0o177); defer { umask(old) }
        let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        guard rc == 0, listen(fd, 16) == 0 else { close(fd); fd = -1; return false }
        chmod(path, 0o600)
        isListening = true
        let t = Thread { [weak self] in self?.loop() }
        t.name = "com.onelineai.larm.hooksocket"
        t.qualityOfService = .utility
        thread = t; t.start()
        return true
    }

    private func loop() {
        while isListening {
            let c = accept(fd, nil, nil)
            if c < 0 { if !isListening { break }; usleep(50_000); continue }
            var tv = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var buf = [UInt8](repeating: 0, count: 65536)
            var data = Data()
            while data.count < 1_000_000 {
                let n = read(c, &buf, buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
                if buf[n - 1] == 0x0A { break }
            }
            var ack: UInt8 = 0x06
            _ = write(c, &ack, 1)
            close(c)
            lastAcceptAt = Date(); acceptedCount += 1
            if !data.isEmpty { handler(data) }
        }
    }

    public func stop() {
        isListening = false
        if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd); fd = -1 }
        unlink(path)
    }

    deinit { stop() }
}
