import Testing
import Foundation
@testable import LARMCore

@Suite struct DecisionTests {
    @Test func inspectionIntervalBoundsAndRandomness() {
        for p in [0.0, 0.3, 0.7, 1.0] {
            let t = InspectionPolicy.nextInterval(changeSoon: p, random: 1.0)
            #expect(t >= 10 * 60 && t <= 60 * 60)
        }
        #expect(InspectionPolicy.nextInterval(changeSoon: 0.9, random: 1) < InspectionPolicy.nextInterval(changeSoon: 0.1, random: 1))
        let lo = InspectionPolicy.nextInterval(changeSoon: 0.5, random: 0.7), hi = InspectionPolicy.nextInterval(changeSoon: 0.5, random: 1.3)
        #expect(lo < hi)
    }

    @Test func alertGateSendsOnlyWhenValuable() {
        #expect(AlertGate.shouldSend(actionNeeded: 0.85, willRespond: 0.6, weight: 1).send)
        #expect(!AlertGate.shouldSend(actionNeeded: 0.45, willRespond: 0.15, weight: 1).send)
    }

    @Test func heuristicLayerIsBoundedAndExplained() {
        let l = HeuristicDecisionLayer()
        var i = DecisionInput(); i.recentEventCount15m = 3
        let e = l.estimate(.changeSoon, subject: "x", input: i, context: [:])
        #expect(e.p > 0.5 && e.p <= 1 && !e.basis.isEmpty && e.model == "rule-1")
        let q = l.estimate(.willRespond, subject: "x", input: { var j = DecisionInput(); j.quietHours = true; return j }(), context: [:])
        #expect(q.p < 0.3)
    }

    @Test func estimatesRecordOutcomesAndBrier() throws {
        let db = try Fx.tempDB()
        for k in 0..<6 {
            try EstimateRepo.record(db, Estimate(question: .evasion, subject: "s\(k)", p: 0.8, basis: "t", model: "rule-1"))
            try EstimateRepo.outcome(db, question: .evasion, subject: "s\(k)", value: 1)
        }
        let b = try #require(try EstimateRepo.brier(db, question: .evasion))
        #expect(b.n == 6 && abs(b.score - 0.04) < 1e-9)
        #expect(try EstimateRepo.brier(db, question: .changeSoon) == nil)
    }

    func rte(_ id: String, session: String, tool: String = "Bash", flags: [String] = [], sev: String? = nil, scope: String? = "sc1") -> RuntimeEvent {
        RuntimeEvent(eventID: id, sourceEventID: id, phase: "request", hookEventName: "PreToolUse", toolName: tool, targetKind: tool == "Bash" ? "command" : "file", targetAlias: "", scopeID: scope, outsideScope: scope == nil, commandBasename: nil, argc: 1, argFingerprint: "", flags: flags, sessionRef: session, processRef: "1@0", observedAt: Clock.nowUTC(), receivedAt: Clock.nowUTC(), seq: 0, delivery: "socket", resultPresent: false, riskRule: sev == nil ? nil : "RR01", riskOutcome: sev == nil ? nil : "flagged", riskSeverity: sev, riskSummary: nil, riskLimits: nil, riskNext: nil, ackState: "observed", duplicateCount: 0)
    }

    @Test func sessionSignalsRankSuspiciousFirst() {
        let evs = [rte("a", session: "calm"), rte("b", session: "calm"),
                   rte("c", session: "odd", flags: ["base64_decode", "pipe_to_shell"], sev: "high"), rte("d", session: "odd", flags: ["sensitive_path"])]
        let s = PlayerGames.sessionSignals(events: evs)
        #expect(s.first?.sessionRef == "odd" && s.first!.p > s.last!.p && s.last!.basis == "특이 표시 없음")
    }

    @Test func delegationCountsMatchingRequests() {
        let evs = (0..<6).map { rte("e\($0)", session: "s\($0 % 3)") } + [rte("w", session: "s0", tool: "Write")]
        let d = PlayerGames.delegation(breadth: "full_shell", scopeID: "sc1", events: evs)
        #expect(d.matched30d == 6 && d.sessions30d == 3 && d.perSession == 2 && d.recommendNarrow)
        #expect(PlayerGames.delegation(breadth: "broad_write", scopeID: "sc1", events: evs).matched30d == 1)
        #expect(!PlayerGames.delegation(breadth: "full_shell", scopeID: "other", events: evs).recommendNarrow)
    }

    @Test func baselineSuggestionOnlyWhenSafe() {
        #expect(PlayerGames.baselineSuggestion(hasBaseline: false, baselineAt: nil, diffCount: 0, openHigh: 0, lastScanAt: "x") != nil)
        #expect(PlayerGames.baselineSuggestion(hasBaseline: false, baselineAt: nil, diffCount: 0, openHigh: 1, lastScanAt: "x") == nil)
        let old = Clock.utc(Date().addingTimeInterval(-8 * 86400))
        #expect(PlayerGames.baselineSuggestion(hasBaseline: true, baselineAt: old, diffCount: 2, openHigh: 0, lastScanAt: "x") != nil)
        #expect(PlayerGames.baselineSuggestion(hasBaseline: true, baselineAt: Clock.nowUTC(), diffCount: 2, openHigh: 0, lastScanAt: "x") == nil)
    }
}
