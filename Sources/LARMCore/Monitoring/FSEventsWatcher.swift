import Foundation
import CoreServices

/// 디렉터리 변경 감시.
/// 유실 플래그(MustScanSubDirs/KernelDropped/UserDropped)는 공백으로 보고한다.
public final class FSEventsWatcher {
    public enum Signal: Sendable, Equatable { case changed(paths: [String]), overflow(reason: String) }
    public typealias Handler = @Sendable (Signal) -> Void

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.onelineai.larm.fsevents")
    public private(set) var paths: [String]
    private let handler: Handler
    public private(set) var isRunning = false
    public private(set) var lastEventAt: Date?

    public init(paths: [String], latency: TimeInterval = 1.0, handler: @escaping Handler) {
        self.paths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        self.handler = handler
        self.latency = latency
    }
    private let latency: TimeInterval

    public func start() -> Bool {
        guard stream == nil, !paths.isEmpty else { return !paths.isEmpty }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let me = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let arr = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            var changed: [String] = []
            var overflow: String? = nil
            for i in 0..<count {
                let f = eventFlags[i]
                if f & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 { overflow = "MustScanSubDirs" }
                if f & UInt32(kFSEventStreamEventFlagKernelDropped) != 0 { overflow = "KernelDropped" }
                if f & UInt32(kFSEventStreamEventFlagUserDropped) != 0 { overflow = "UserDropped" }
                if i < arr.count { changed.append(arr[i]) }
            }
            me.lastEventAt = Date()
            if let overflow { me.handler(.overflow(reason: overflow)) }
            if !changed.isEmpty { me.handler(.changed(paths: changed)) }
        }
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, callback, &ctx, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return false }
        FSEventStreamSetDispatchQueue(s, queue)
        guard FSEventStreamStart(s) else { FSEventStreamInvalidate(s); FSEventStreamRelease(s); return false }
        stream = s
        isRunning = true
        return true
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        stream = nil; isRunning = false
    }

    deinit { stop() }
}

/// 개별 파일 stat 폴링 (기본 60초).
public final class PathPoller {
    public struct Sig: Equatable, Sendable { let exists: Bool; let inode: UInt64; let size: Int; let mtime: Double }
    public private(set) var files: [String]
    private var last: [String: Sig] = [:]
    public init(files: [String]) { self.files = files; for f in files { last[f] = Self.sig(f) } }

    public static func sig(_ p: String) -> Sig {
        if let st = try? SafeFile.lstat(p) { return Sig(exists: true, inode: st.inode, size: st.size, mtime: st.mtime) }
        return Sig(exists: false, inode: 0, size: 0, mtime: 0)
    }

    /// 변경된 파일 목록을 돌려주고 기준을 갱신한다.
    public func poll() -> [String] {
        var changed: [String] = []
        for f in files {
            let s = Self.sig(f)
            if s != last[f] { changed.append(f); last[f] = s }
        }
        return changed
    }

    public func reset(files: [String]) { self.files = files; last = [:]; for f in files { last[f] = Self.sig(f) } }
}

/// 감시 표면 상태
public enum SurfaceStatus: String, Sendable, Codable {
    case watching, partial, paused, failed, unsupported, notConnected = "not_connected"
    public var label: String {
        switch self { case .watching: return "감시 중"; case .partial: return "부분 감시"; case .paused: return "잠시 멈춤"; case .failed: return "장애"
        case .unsupported: return "미지원"; case .notConnected: return "연결 안 됨" }
    }
}

public struct HealthSnapshot: Sendable, Equatable {
    public var configWatch: SurfaceStatus
    public var activity: SurfaceStatus
    public var lastOKAt: Date?
    public var lastCheckAt: Date?
    public var lastReconcileAt: Date?
    public var detail: String
    public init(configWatch: SurfaceStatus = .failed, activity: SurfaceStatus = .notConnected, lastOKAt: Date? = nil, lastCheckAt: Date? = nil, lastReconcileAt: Date? = nil, detail: String = "") {
        self.configWatch = configWatch; self.activity = activity; self.lastOKAt = lastOKAt; self.lastCheckAt = lastCheckAt; self.lastReconcileAt = lastReconcileAt; self.detail = detail
    }
    public var overall: SurfaceStatus {
        if configWatch == .paused { return .paused }
        if configWatch == .failed { return .failed }
        if configWatch == .partial || activity == .failed { return .partial }
        return .watching
    }
}
