import Foundation

/// 점검 상한.
public struct Limits: Sendable {
    public var maxFileBytes: Int = 2 * 1024 * 1024
    public var maxFiles: Int = 2000
    public var maxProjects: Int = 20
    public var maxTotalBytes: Int = 200 * 1024 * 1024
    public var maxDepth: Int = 10
    public init() {}
}

public final class ScanBudget {
    public private(set) var files = 0
    public private(set) var bytes = 0
    public let limits: Limits
    public init(limits: Limits) { self.limits = limits }
    func charge(_ n: Int) -> Bool {
        if files + 1 > limits.maxFiles || bytes + n > limits.maxTotalBytes { return false }
        files += 1; bytes += n; return true
    }
}

public enum SafeFileError: Error, Sendable {
    case absent, denied, oversize(Int), symlinkEscape, tocTou, notRegular, budget, unreadable(String)
}

/// 파일 안전 읽기: lstat 우선, 범위 밖 심볼릭 링크 거부, 크기 상한, O_NOFOLLOW, 읽은 뒤 inode/size 재확인 (TOCTOU).
public enum SafeFile {
    public struct Stat: Sendable {
        public let mode: UInt16
        public let uid: UInt32
        public let size: Int
        public let inode: UInt64
        public let mtime: Double
        public let isSymlink: Bool
        public let isRegular: Bool
    }

    public static func lstat(_ path: String) throws -> Stat {
        var st = Darwin.stat()
        guard Darwin.lstat(path, &st) == 0 else {
            switch errno { case ENOENT, ENOTDIR: throw SafeFileError.absent; case EACCES, EPERM: throw SafeFileError.denied
            default: throw SafeFileError.unreadable("lstat errno \(errno)") }
        }
        let fmt = st.st_mode & S_IFMT
        return Stat(mode: UInt16(st.st_mode & 0o7777), uid: st.st_uid, size: Int(st.st_size), inode: st.st_ino,
                    mtime: Double(st.st_mtimespec.tv_sec), isSymlink: fmt == S_IFLNK, isRegular: fmt == S_IFREG)
    }

    /// 심볼릭 링크면 해석 결과가 scopeRoot 안인지 확인한다.
    public static func resolveWithinScope(_ path: String, scopeRoot: String) throws -> String {
        let st = try lstat(path)
        if !st.isSymlink { return path }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let root = URL(fileURLWithPath: scopeRoot).resolvingSymlinksInPath().path
        guard resolved == root || resolved.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { throw SafeFileError.symlinkEscape }
        return resolved
    }

    public static func read(_ path: String, scopeRoot: String, budget: ScanBudget) throws -> (Data, Stat) {
        let real = try resolveWithinScope(path, scopeRoot: scopeRoot)
        let st = try lstat(real)
        guard st.isRegular else { throw SafeFileError.notRegular }
        guard st.size <= budget.limits.maxFileBytes else { throw SafeFileError.oversize(st.size) }
        guard budget.charge(st.size) else { throw SafeFileError.budget }
        let fd = open(real, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == EACCES || errno == EPERM { throw SafeFileError.denied }
            if errno == ENOENT { throw SafeFileError.absent }
            throw SafeFileError.unreadable("open errno \(errno)")
        }
        defer { close(fd) }
        var fst = Darwin.stat()
        guard fstat(fd, &fst) == 0, fst.st_ino == st.inode, Int(fst.st_size) == st.size else { throw SafeFileError.tocTou }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let data = handle.readDataToEndOfFile()
        guard data.count == st.size else { throw SafeFileError.tocTou }
        return (data, st)
    }

    /// 파일 존재·크기·해시만 (지시 파일용).
    public static func digest(_ path: String, scopeRoot: String, budget: ScanBudget) throws -> (sha256: String, stat: Stat) {
        let (d, st) = try read(path, scopeRoot: scopeRoot, budget: budget)
        return (Hashing.sha256Hex(d), st)
    }

    public static func coverageStatus(for error: Error) -> (CoverageStatus, String) {
        guard let e = error as? SafeFileError else { return (.error, "\(error)") }
        switch e {
        case .absent: return (.absent, "파일 없음")
        case .denied: return (.denied, "접근 거절")
        case .oversize(let n): return (.oversize, "크기 초과 \(n) bytes")
        case .symlinkEscape: return (.denied, "범위 밖 심볼릭 링크")
        case .tocTou: return (.error, "읽는 중 파일 변경")
        case .notRegular: return (.unsupported, "일반 파일 아님")
        case .budget: return (.oversize, "점검 상한 초과")
        case .unreadable(let s): return (.error, s)
        }
    }
}
