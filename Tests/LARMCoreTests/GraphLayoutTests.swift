import Testing
import Foundation
@testable import LARMCore

@Suite struct GraphLayoutTests {
    @Test func connectedNodesEndUpCloserThanUnconnected() {
        let ids = (0..<30).map { "n\($0)" }
        let edges = (0..<29).map { ("n\($0)", "n\($0 + 1)") }
        let p = ForceLayout.layout(nodeIDs: ids, edges: edges)
        func d(_ a: String, _ b: String) -> Double { hypot(p[a]!.x - p[b]!.x, p[a]!.y - p[b]!.y) }
        let linked = (0..<29).map { d("n\($0)", "n\($0 + 1)") }.reduce(0, +) / 29
        let far = d("n0", "n29")
        #expect(linked < far)
        #expect(linked < 250)
    }

    @Test func deterministicAndRespectsPins() {
        let ids = (0..<50).map { "n\($0)" }
        let edges = (0..<80).map { ("n\($0 % 50)", "n\(($0 * 7 + 3) % 50)") }
        let a = ForceLayout.layout(nodeIDs: ids, edges: edges)
        let b = ForceLayout.layout(nodeIDs: ids, edges: edges)
        #expect(a == b)
        let pin = LayoutPoint(x: 123, y: 456)
        let c = ForceLayout.layout(nodeIDs: ids, edges: edges, pinned: ["n3": pin])
        #expect(c["n3"] == pin)
        #expect(ForceLayout.neighborhood(of: "n0", edges: [("n0", "n1"), ("n1", "n2"), ("n5", "n6")], depth: 1) == ["n0", "n1"])
        #expect(ForceLayout.neighborhood(of: "n0", edges: [("n0", "n1"), ("n1", "n2"), ("n5", "n6")], depth: 2) == ["n0", "n1", "n2"])
    }

    @Test func fiveHundredNodesUnderTwoSeconds() {
        let ids = (0..<500).map { "n\($0)" }
        let edges = (0..<1000).map { ("n\($0 % 500)", "n\(($0 * 13 + 7) % 500)") }
        let t0 = Date()
        let p = ForceLayout.layout(nodeIDs: ids, edges: edges)
        let dt = Date().timeIntervalSince(t0)
        #expect(p.count == 500)
        #expect(dt < 2.0, "layout took \(dt)s")
    }
}
