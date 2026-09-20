import Foundation

/// 룰·안내 리소스 위치.
public enum ResourceLocator {
    public static var bundle: Bundle {
        if let b = try? moduleBundle() { return b }
        return Bundle.main
    }

    private static func moduleBundle() throws -> Bundle {
        let name = "LARM_LARMCore.bundle"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
        ].compactMap { $0?.appendingPathComponent(name) }
        for c in candidates where FileManager.default.fileExists(atPath: c.path) {
            if let b = Bundle(url: c) { return b }
        }
        return Bundle.module
    }

    public static func url(_ relative: String) -> URL? {
        let parts = relative.split(separator: "/").map(String.init)
        guard let last = parts.last else { return nil }
        let sub = (["Resources"] + parts.dropLast()).joined(separator: "/")
        let ext = (last as NSString).pathExtension
        let base = (last as NSString).deletingPathExtension
        return bundle.url(forResource: base, withExtension: ext.isEmpty ? nil : ext, subdirectory: sub)
    }

    public static func data(_ relative: String) throws -> Data {
        guard let u = url(relative) else {
            throw NSError(domain: "LARM", code: 404, userInfo: [NSLocalizedDescriptionKey: "리소스를 찾을 수 없습니다: \(relative)"])
        }
        return try Data(contentsOf: u)
    }
}
