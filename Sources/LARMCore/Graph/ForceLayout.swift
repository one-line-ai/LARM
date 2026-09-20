import Foundation

public struct LayoutPoint: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// 노드 ID 해시로 초기 위치를 정하는 force-directed 시뮬레이션.
public final class ForceSimulation {
    public struct Options: Sendable {
        public var width: Double = 1000
        public var height: Double = 700
        public var idealEdge: Double = 140
        public var repulsion: Double = 0.6
        public var gravity: Double = 0.06
        public var velocityDecay: Double = 0.55
        public var alphaDecay: Double = 0.02
        public var alphaMin: Double = 0.003
        public init() {}
    }

    public let ids: [String]
    public private(set) var x: [Double]
    public private(set) var y: [Double]
    private var vx: [Double]
    private var vy: [Double]
    private var fixed: [Bool]
    private let edges: [(Int, Int)]
    private let index: [String: Int]
    private let degree: [Int]
    public private(set) var alpha: Double = 1
    public let options: Options
    private let k: Double

    public init(nodeIDs: [String], edges: [(String, String)], pinned: [String: LayoutPoint] = [:], options: Options = Options()) {
        self.ids = nodeIDs
        self.options = options
        let n = nodeIDs.count
        let idx = Dictionary(uniqueKeysWithValues: nodeIDs.enumerated().map { ($1, $0) })
        index = idx
        var px = [Double](repeating: 0, count: n), py = px
        var fx = [Bool](repeating: false, count: n)
        for (i, id) in nodeIDs.enumerated() {
            let p = pinned[id] ?? ForceSimulation.seed(id, options)
            px[i] = p.x; py[i] = p.y; fx[i] = pinned[id] != nil
        }
        x = px; y = py; vx = [Double](repeating: 0, count: n); vy = vx; fixed = fx
        let es: [(Int, Int)] = edges.compactMap { a, b in
            guard let i = idx[a], let j = idx[b], i != j else { return nil }
            return (i, j)
        }
        self.edges = es
        var deg = [Int](repeating: 0, count: n)
        for (i, j) in es { deg[i] += 1; deg[j] += 1 }
        degree = deg
        let area = options.width * options.height
        k = n > 0 ? max(40, min(options.idealEdge, sqrt(area / Double(n)) * 0.9)) : options.idealEdge
    }

    static func seed(_ id: String, _ o: Options) -> LayoutPoint {
        let h = Hashing.sha256Hex(id)
        let a = Double(UInt32(h.prefix(8), radix: 16) ?? 0) / Double(UInt32.max)
        let b = Double(UInt32(h.dropFirst(8).prefix(8), radix: 16) ?? 0) / Double(UInt32.max)
        return LayoutPoint(x: o.width * (0.2 + 0.6 * a), y: o.height * (0.2 + 0.6 * b))
    }

    public var isSettled: Bool { alpha < options.alphaMin }
    public func reheat(_ a: Double = 0.4) { alpha = max(alpha, a) }

    public func position(of id: String) -> LayoutPoint? {
        guard let i = index[id] else { return nil }
        return LayoutPoint(x: x[i], y: y[i])
    }
    public var positions: [String: LayoutPoint] {
        var out: [String: LayoutPoint] = [:]
        for (i, id) in ids.enumerated() { out[id] = LayoutPoint(x: x[i], y: y[i]) }
        return out
    }

    public func pin(_ id: String, at p: LayoutPoint) {
        guard let i = index[id] else { return }
        x[i] = p.x; y[i] = p.y; vx[i] = 0; vy[i] = 0; fixed[i] = true
    }
    public func unpin(_ id: String) { if let i = index[id] { fixed[i] = false } }

    /// 한 단계 진행.
    public func tick() {
        let n = ids.count
        guard n > 0, alpha >= options.alphaMin else { return }
        var fx = [Double](repeating: 0, count: n), fy = fx
        let k2 = k * k * options.repulsion
        func repel(_ i: Int, _ j: Int) {
            var dx = x[i] - x[j], dy = y[i] - y[j]
            var d2 = dx * dx + dy * dy
            if d2 < 1 { dx = Double((i &* 31 &+ j) % 13) - 6; dy = Double((j &* 17 &+ i) % 11) - 5; d2 = dx * dx + dy * dy + 1 }
            let f = k2 / d2
            fx[i] += dx * f; fy[i] += dy * f
            fx[j] -= dx * f; fy[j] -= dy * f
        }
        if n <= 250 {
            for i in 0..<n { for j in (i + 1)..<n { repel(i, j) } }
        } else {
            let cell = k * 3
            let cols = Int(options.width / cell) + 2, rows = Int(options.height / cell) + 2
            var grid = [[Int]](repeating: [], count: cols * rows)
            for i in 0..<n { grid[min(rows - 1, max(0, Int(y[i] / cell))) * cols + min(cols - 1, max(0, Int(x[i] / cell)))].append(i) }
            for i in 0..<n {
                let cx = min(cols - 1, max(0, Int(x[i] / cell))), cy = min(rows - 1, max(0, Int(y[i] / cell)))
                for oy in -1...1 { for ox in -1...1 {
                    let gx = cx + ox, gy = cy + oy
                    guard gx >= 0, gy >= 0, gx < cols, gy < rows else { continue }
                    for j in grid[gy * cols + gx] where j > i { repel(i, j) }
                } }
            }
        }
        for (i, j) in edges {
            let dx = x[i] - x[j], dy = y[i] - y[j]
            let d = max(1, sqrt(dx * dx + dy * dy))
            let f = d / k
            fx[i] -= dx * f; fy[i] -= dy * f
            fx[j] += dx * f; fy[j] += dy * f
        }
        let cx = options.width / 2, cy = options.height / 2
        for i in 0..<n {
            let g = degree[i] == 0 ? options.gravity * 6 : options.gravity
            fx[i] += (cx - x[i]) * g
            fy[i] += (cy - y[i]) * g
        }
        let cap = k * 2
        for i in 0..<n where !fixed[i] {
            var ax = fx[i] * alpha, ay = fy[i] * alpha
            let m = sqrt(ax * ax + ay * ay)
            if m > cap { ax *= cap / m; ay *= cap / m }
            vx[i] = (vx[i] + ax) * options.velocityDecay
            vy[i] = (vy[i] + ay) * options.velocityDecay
            x[i] += vx[i]
            y[i] += vy[i]
        }
        alpha *= (1 - options.alphaDecay)
    }

    public func run(maxTicks: Int = 400) {
        var t = 0
        while !isSettled && t < maxTicks { tick(); t += 1 }
    }
}

public enum ForceLayout {
    public typealias Options = ForceSimulation.Options

    public static func layout(nodeIDs: [String], edges: [(String, String)], pinned: [String: LayoutPoint] = [:], options: Options = Options()) -> [String: LayoutPoint] {
        let sim = ForceSimulation(nodeIDs: nodeIDs, edges: edges, pinned: pinned, options: options)
        sim.run()
        return sim.positions
    }

    public static func neighborhood(of id: String, edges: [(String, String)], depth: Int) -> Set<String> {
        var adj: [String: Set<String>] = [:]
        for (a, b) in edges { adj[a, default: []].insert(b); adj[b, default: []].insert(a) }
        var seen: Set<String> = [id]
        var frontier: Set<String> = [id]
        for _ in 0..<max(0, depth) {
            var next = Set<String>()
            for f in frontier { for nb in adj[f] ?? [] where !seen.contains(nb) { next.insert(nb) } }
            seen.formUnion(next); frontier = next
            if frontier.isEmpty { break }
        }
        return seen
    }
}
