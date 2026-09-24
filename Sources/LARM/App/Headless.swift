import Foundation
import LARMCore

/// `LARM --scan` : 창 없이 저장된 범위를 점검하고 요약을 출력한다 (진단·수용 시험 증빙용).
enum Headless {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.contains("--scan") || args.contains("--status") || args.contains("--baseline") || args.contains("--export") || args.contains("--install-hook") || args.contains("--uninstall-hook") else { return }
        do {
            try Paths.ensureDirs()
            let db = try SQLiteDB(url: Paths.dbURL)
            try Schema.migrate(db)
            if args.contains("--status") {
                printStatus(db); exit(0)
            }
            if args.contains("--install-hook") || args.contains("--uninstall-hook") {
                let path = NSHomeDirectory() + "/.claude/settings.json"
                let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                let plan = args.contains("--uninstall-hook") ? try HookInstaller.planRemove(settingsText: text)
                                                              : try HookInstaller.planInstall(settingsText: text, hookPath: "/Applications/LARM.app/Contents/MacOS/larm-hook")
                guard plan.changed else { print("변경 없음 (\(args.contains("--uninstall-hook") ? "LARM hook 없음" : "이미 등록됨"))"); exit(0) }
                print("--- ~/.claude/settings.json 변경 전후 ---\n\(plan.diff)")
                guard args.contains("--yes") else { print("적용하려면 --yes 를 붙이기 (사용자 확인 필요)."); exit(3) }
                try HookInstaller.apply(plan, to: path)
                try Audit.record(db, kind: args.contains("--uninstall-hook") ? "hook_removed" : "hook_installed", detail: ["via": "headless"])
                print("적용했음."); exit(0)
            }
            let material = try KeychainKey.loadOrCreate()
            _ = try InstallationStore.loadOrCreate(db: db, keyID: material.keyID, appVersion: AppInfo.version, osBuild: AppInfo.osBuild)
            let rules = try RuleLoader.loadBundled()
            try ScopeRepo.ensureUserRoot(db)
            if let i = args.firstIndex(of: "--add-project"), i + 1 < args.count {
                _ = try ScopeRepo.addProject(db, path: args[i + 1])
            }
            if let i = args.firstIndex(of: "--remove-project"), i + 1 < args.count {
                let std = URL(fileURLWithPath: args[i + 1]).standardizedFileURL.path
                for s in try ScopeRepo.all(db) where s.realPath == std { try ScopeRepo.remove(db, scopeID: s.scopeID) }
            }
            let scopes = try ScopeRepo.all(db)
            if let i = args.firstIndex(of: "--baseline") {
                let reason = i + 1 < args.count ? args[i + 1] : "headless"
                guard let last = try ScanRepo.latest(db) else { print("점검 기록 없음"); exit(1) }
                try DecisionRepo.setBaseline(db, scanID: last.scanID, reason: reason)
                print("baseline_set scan_id=\(last.scanID)"); exit(0)
            }
            if let i = args.firstIndex(of: "--export"), i + 1 < args.count {
                let out = URL(fileURLWithPath: args[i + 1])
                guard let s = try ScanRepo.latestCompletedOrPartial(db) else { print("점검 기록 없음"); exit(1) }
                let ids = try ScanRepo.scopeIDs(db, scanID: s.scanID)
                let baseline = try DecisionRepo.currentBaseline(db)
                var diff: [DiffEntry] = []
                if let b = baseline?.scanID, b != s.scanID {
                    diff = Differ.diff(from: try ScanRepo.observations(db, scanID: b), fromCoverage: try ScanRepo.coverage(db, scanID: b),
                                       to: try ScanRepo.observations(db, scanID: s.scanID), toCoverage: try ScanRepo.coverage(db, scanID: s.scanID),
                                       fromScopes: try ScanRepo.scopeIDs(db, scanID: b), toScopes: ids)
                }
                let input = ExportInput(scanID: s.scanID, scanSummary: s, scopes: scopes.filter { ids.contains($0.scopeID) }, coverage: try ScanRepo.coverage(db, scanID: s.scanID),
                                        observations: try ScanRepo.observations(db, scanID: s.scanID), findings: try FindingRepo.list(db), decisions: try DecisionRepo.all(db),
                                        diff: diff, baselineScanID: baseline?.scanID, versions: ["app": AppInfo.version, "os": AppInfo.osBuild, "rules": rules.version],
                                        filters: ["scan": "latest"], installationID: "headless", events: try EventIngest.list(db), gaps: try CoverageGapRepo.recent(db, limit: 500))
                let (zip, exportID, msha) = try Exporter.build(input)
                try zip.write(to: out, options: .atomic)
                try Audit.record(db, kind: "export", detail: ["export_id": exportID, "manifest_sha256": msha])
                print("exported \(out.path) export_id=\(exportID) manifest_sha256=\(msha) diff=\(diff.count)"); exit(0)
            }
            let ctx = Scanner.Context(baselineObservations: try DecisionRepo.currentBaseline(db)?.scanID.flatMap { try ScanRepo.observations(db, scanID: $0) },
                                      reviewedEndpoints: try DecisionRepo.reviewedEndpoints(db))
            let scanner = Scanner(rules: rules, redactor: Redactor(hmacKey: material.key))
            let result = scanner.run(scopes: scopes, context: ctx)
            let summary = try ScanRepo.store(db, result: result, kind: "headless", keyID: material.keyID)
            print("scan_id=\(summary.scanID) status=\(summary.status.rawValue) started=\(result.startedAt) ended=\(result.endedAt) rules=\(rules.version)")
            print("scopes=\(scopes.map { $0.alias }.joined(separator: ",")) observations=\(result.observations.count) coverage=\(result.coverage.count)")
            for c in result.coverage where c.status != .success { print("  gap \(c.adapter) \(c.itemAlias): \(c.status.rawValue) \(c.reason)") }
            let pos = result.verdicts.filter { $0.outcome == .positive }
            let byRule = Dictionary(grouping: pos, by: { $0.ruleID }).mapValues { $0.count }
            print("verdicts positive=\(pos.count) unknown=\(result.verdicts.filter { $0.outcome == .unknown }.count) byRule=\(byRule.sorted { $0.key < $1.key })")
            for v in pos.sorted(by: { ($0.severity.rank, $0.ruleID) > ($1.severity.rank, $1.ruleID) }) {
                print("  [\(v.severity.rawValue)] \(v.ruleID) \(v.objectID) @ \(v.locationAlias): \(Redactor.scrub(v.summary))")
            }
            printStatus(db)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("headless 실패: \(Redactor.scrub("\(error)"))\n".utf8))
            exit(1)
        }
    }

    static func printStatus(_ db: SQLiteDB) {
        let gaps = (try? CoverageGapRepo.recent(db, limit: 10)) ?? []
        let pause = PauseState.load(db)
        print("watch pause=\(pause.mode.rawValue) open_gaps=\((try? CoverageGapRepo.openGaps(db))?.count ?? 0) last_alive=\(Settings.get(db, "last_alive_at") ?? "-") autostart_setting=\(Settings.get(db, "autostart_enabled") ?? "false")")
        for g in gaps { print("  gap \(g.surface) \(g.reason) \(g.startedAt) ~ \(g.endedAt ?? "open") \(g.recoveryEvidence)") }
        let evs = (try? EventIngest.list(db, limit: 5)) ?? []
        let total = (try? db.scalar("SELECT COUNT(*) FROM runtime_event").int) ?? 0
        print("activity hook_installed=\(HookInstaller.isInstalled(settingsText: (try? String(contentsOfFile: NSHomeDirectory() + "/.claude/settings.json", encoding: .utf8)) ?? "")) events=\(total) verified_at=\(Settings.get(db, "activity_verified_at") ?? "-")")
        for e in evs { print("  event \(e.phase) \(e.toolName) \(e.targetAlias) risk=\(e.riskRule ?? "-")/\(e.riskSeverity ?? "-") delivery=\(e.delivery)") }
        let fs = (try? FindingRepo.list(db)) ?? []
        let counts = Dictionary(grouping: fs, by: { $0.state.rawValue }).mapValues { $0.count }
        print("findings total=\(fs.count) byState=\(counts.sorted { $0.key < $1.key }) high_open=\(fs.filter { $0.severity == .high && ($0.state == .open || $0.state == .inProgress) }.count)")
    }
}
