import SwiftUI
import AppKit
import Combine
import LARMCore

/// 옵시디언형 근거 그래프.
struct GraphView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var vm = GraphViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if vm.graph == nil {
                Text("점검 결과가 없습니다. 먼저 점검하세요.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.tableMode {
                tableView
            } else {
                HSplitView {
                    ZStack(alignment: .bottomTrailing) {
                        GraphCanvasView(vm: vm)
                        HStack(spacing: 4) {
                            Button { vm.requestZoom(1.25) } label: { Image(systemName: "plus.magnifyingglass") }.help("확대 (+)")
                            Button { vm.requestZoom(0.8) } label: { Image(systemName: "minus.magnifyingglass") }.help("축소 (-)")
                            Button { vm.fitToView() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }.help("화면에 맞춤 (0)")
                            Toggle(isOn: $vm.showLegend) { Image(systemName: "list.bullet.rectangle") }.toggleStyle(.button).help("범례")
                        }.buttonStyle(.bordered).controlSize(.small).padding(8)
                        if vm.showLegend { legend.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
                    }.frame(minWidth: 360)
                    detailPanel.frame(minWidth: 240, idealWidth: 320)
                }
            }
            footer
        }
        .onAppear { vm.load(state: state) }
        .onChange(of: state.lastScan?.scanID) { _ in vm.load(state: state) }
        .onChange(of: state.diff) { _ in vm.applyDiff(state.diff) }
    }

    var toolbar: some View {
        VStack(spacing: 6) {
            HStack {
                Picker("보기", selection: $vm.mode) { Text("전체").tag(GraphViewModel.Mode.full); Text("주변").tag(GraphViewModel.Mode.neighborhood); Text("변경").tag(GraphViewModel.Mode.changes) }
                    .pickerStyle(.segmented).frame(width: 180)
                if vm.mode == .neighborhood { Picker("깊이", selection: $vm.depth) { Text("1").tag(1); Text("2").tag(2) }.frame(width: 90) }
                TextField("검색", text: $vm.query).textFieldStyle(.roundedBorder).frame(width: 160)
                    .onSubmit { vm.selectFirstMatch() }
                Toggle("표로 보기", isOn: $vm.tableMode)
                Button("배치 초기화") { vm.resetLayout() }
                Spacer()
                savedViewsMenu
            }
            HStack {
                Menu("타입 (\(vm.typeFilter.count)/\(Ontology.NodeType.allCases.count))") {
                    ForEach(Ontology.NodeType.allCases, id: \.self) { t in
                        Toggle(t.rawValue, isOn: Binding(get: { vm.typeFilter.contains(t) }, set: { on in if on { vm.typeFilter.insert(t) } else { vm.typeFilter.remove(t) }; vm.rebuild() }))
                    }
                }.fixedSize()
                Picker("심각도", selection: $vm.severityFilter) { Text("전체").tag("all"); Text("높음").tag("high"); Text("중간").tag("medium") }.fixedSize()
                Picker("상태", selection: $vm.stateFilter) { Text("전체").tag("all"); Text("열림").tag("open"); Text("조치 중").tag("in_progress"); Text("예외").tag("excepted") }.fixedSize()
                Text("표시 \(vm.visibleNodes.count)개 / 전체 \(vm.graph?.nodes.count ?? 0)개\(vm.hiddenByCap > 0 ? " · 상한 초과로 \(vm.hiddenByCap)개 숨김 (표로 보기 권장)" : "")")
                    .font(AppFont.footnote).foregroundStyle(vm.hiddenByCap > 0 ? .orange : .secondary).lineLimit(1).frame(minWidth: 0)
                Spacer()
            }
        }.padding(8)
    }

    var savedViewsMenu: some View {
        Menu("저장 보기 (\(vm.savedViews.count)/5)") {
            ForEach(vm.savedViews) { v in Button(v.name) { vm.restore(v) } }
            if !vm.savedViews.isEmpty { Divider() }
            Button("현재 보기 저장…") { vm.showSaveSheet = true }.disabled(vm.savedViews.count >= 5)
            if !vm.savedViews.isEmpty { Menu("삭제") { ForEach(vm.savedViews) { v in Button(v.name) { vm.delete(v) } } } }
        }.fixedSize()
        .sheet(isPresented: $vm.showSaveSheet) {
            VStack(spacing: 12) {
                Text("보기 이름").font(AppFont.headline)
                TextField("예: 매일 확인 (AIops)", text: $vm.saveName).textFieldStyle(.roundedBorder).frame(width: 300)
                HStack { Button("취소") { vm.showSaveSheet = false }; Button("저장") { vm.saveCurrent(); vm.showSaveSheet = false }.keyboardShortcut(.defaultAction) }
            }.padding(20)
        }
    }

    var footer: some View {
        Text("스크롤·핀치: 확대  ·  빈 곳 드래그 또는 Shift+스크롤: 이동  ·  노드 드래그: 위치 고정 (더블클릭으로 해제)  ·  실선은 파일에서 확인한 관계, 점선은 추론한 관계")
            .font(AppFont.footnote).foregroundStyle(.secondary).padding(6)
    }

    var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach([Ontology.NodeType.agent, .project, .configuration, .mcpServer, .endpoint, .secretCandidate, .permissionRule, .hook, .instructionFile, .finding], id: \.self) { t in
                HStack(spacing: 6) {
                    Circle().fill(Color(nsColor: GraphNSView.color(t))).frame(width: 9, height: 9)
                    Text(Self.typeName(t)).font(AppFont.caption)
                }
            }
            Text("빨간 테두리: 높은 위험 · 크기: 연결 수").font(AppFont.caption2).foregroundStyle(.secondary)
        }
        .padding(8).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 6))
    }

    static func typeName(_ t: Ontology.NodeType) -> String {
        switch t {
        case .agent: return "AI 도구"; case .project: return "프로젝트"; case .configuration: return "설정 파일"; case .mcpServer: return "MCP 서버"
        case .endpoint: return "주소"; case .secretCandidate: return "비밀정보 후보"; case .permissionRule: return "허용 규칙"; case .hook: return "훅"
        case .instructionFile: return "지시 파일"; case .finding: return "발견 사항"; case .rule: return "룰"; case .file: return "파일"; default: return t.rawValue
        }
    }

    var tableView: some View {
        Table(vm.visibleNodes, selection: Binding(get: { vm.selected }, set: { vm.selected = $0 })) {
            TableColumn("타입") { (n: GraphNode) in Text(n.type.rawValue) }.width(120)
            TableColumn("이름") { (n: GraphNode) in Text(n.label) }
            TableColumn("범위") { (n: GraphNode) in Text(state.scopeAlias(n.scopeID)) }.width(100)
            TableColumn("심각도") { (n: GraphNode) in Text(n.severity ?? "") }.width(70)
            TableColumn("상태") { (n: GraphNode) in Text(n.state ?? "") }.width(90)
            TableColumn("변경") { (n: GraphNode) in Text(vm.change(for: n.id) ?? "") }.width(70)
        }
    }

    var detailPanel: some View {
        ScrollView {
            if let id = vm.selected, let n = vm.node(id) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(n.label).font(AppFont.headline)
                    LabeledContent("타입", value: n.type.rawValue)
                    LabeledContent("범위", value: state.scopeAlias(n.scopeID))
                    LabeledContent("ID", value: n.id).font(AppFont.footnote)
                    if let c = vm.change(for: n.id) { LabeledContent("기준점 대비", value: c) }
                    if let sev = n.severity { LabeledContent("심각도 / 상태", value: "\(sev) / \(n.state ?? "")") }
                    LabeledContent("확인 시각", value: state.lastScan.map { Fmt.local($0.endedAt) } ?? "-")
                    HStack {
                        Button(vm.pinned[n.id] == nil ? "고정" : "고정 해제") { vm.togglePin(n.id) }
                        Button("주변 보기") { vm.mode = .neighborhood; vm.rebuild() }
                        if n.type == .finding, let fid = n.id.split(separator: ":").last.map(String.init), state.findings.contains(where: { $0.findingID == fid }) {
                            Button("근거와 조치 보기") { state.selectedFindingID = fid; state.section = .findings }
                        }
                        if n.type != .finding, n.type != .rule, let f = state.findings.first(where: { $0.objectID == n.id && $0.state != .resolvedByRescan }) {
                            Button("발견 사항 열기") { state.selectedFindingID = f.findingID; state.section = .findings }
                        }
                        Button("이 범위 재점검") { state.runScan(kind: "rescan", onlyScopeIDs: [n.scopeID]) }.disabled(state.scanning)
                    }
                    if !n.attrs.isEmpty {
                        GroupBox("확인한 값") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(n.attrs.keys.sorted(), id: \.self) { k in
                                    HStack(alignment: .top) { Text(k).font(.system(.caption, design: .monospaced)).frame(width: 150, alignment: .leading); Text(n.attrs[k] ?? "").font(AppFont.caption).textSelection(.enabled) }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GroupBox("관계 (\(vm.edges(of: n.id).count))") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(vm.edges(of: n.id)) { e in
                                let other = e.from == n.id ? e.to : e.from
                                Button {
                                    vm.selected = other
                                } label: {
                                    HStack(alignment: .top) {
                                        Text(e.from == n.id ? "→" : "←").frame(width: 14)
                                        VStack(alignment: .leading) {
                                            Text("\(e.type.rawValue) \(vm.node(other)?.label ?? other)").font(AppFont.caption)
                                            Text("\(e.epistemic == .observed ? "직접 확인" : e.epistemic == .derived ? "추론" : "사용자 확인") · 근거 \(e.evidenceRef.count)건 · \(Self.edgeMeaning(e.type))").font(AppFont.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }.buttonStyle(.plain)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("노드를 클릭하면 상세가 열립니다.").foregroundStyle(.secondary)
                    Text("마우스를 올리면 연결된 노드만 밝게 보입니다. 확대할수록 라벨이 더 많이 보입니다.").font(AppFont.footnote).foregroundStyle(.secondary)
                }.padding()
            }
        }
    }

    static func edgeMeaning(_ t: Ontology.EdgeType) -> String {
        switch t {
        case .hasConfiguration: return "에이전트용 설정 선언 (실행, 적용 아님)"
        case .scopedTo: return "점검 범위"
        case .declaresMCP: return "정적 정의 (실제 가동, 접속 아님)"
        case .pointsTo: return "설정이 가리키는 주소 (실제 통신은 확인 안 됨)"
        case .hasCandidate: return "비밀정보 후보 위치 (유효성, 유출 미확인)"
        case .hasFinding: return "대상을 평가한 발견 사항"
        case .evaluatedBy: return "판단에 쓴 룰 버전"
        case .declaresRule, .declaresHook: return "설정에 선언됨"
        case .hasInstruction: return "지시 파일 존재 (내용 미해석)"
        case .storedIn: return "저장 파일"
        default: return t.rawValue
        }
    }
}

struct SavedGraphView: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var mode: String
    var depth: Int
    var center: String?
    var types: [String]
    var severity: String
    var state: String
    var query: String
    var pins: [String: LayoutPoint]
}

@MainActor
final class GraphViewModel: ObservableObject {
    enum Mode: String { case full, neighborhood, changes }
    @Published var graph: Graph?
    @Published var mode: Mode = .full { didSet { rebuild() } }
    @Published var depth = 1 { didSet { rebuild() } }
    @Published var query = "" { didSet { rebuild() } }
    @Published var typeFilter: Set<Ontology.NodeType> = Set(Ontology.NodeType.allCases).subtracting([.rule, .file])
    @Published var severityFilter = "all" { didSet { rebuild() } }
    @Published var stateFilter = "all" { didSet { rebuild() } }
    @Published var tableMode = false
    @Published var selected: String? { didSet { if mode == .neighborhood { rebuild() } } }
    @Published var visibleNodes: [GraphNode] = []
    @Published var visibleEdges: [GraphEdge] = []
    @Published var positions: [String: LayoutPoint] = [:]
    private var sim: ForceSimulation?
    private var ticker: Timer?
    @Published var pinned: [String: LayoutPoint] = [:]
    @Published var hiddenByCap = 0
    @Published var savedViews: [SavedGraphView] = []
    @Published var showSaveSheet = false
    @Published var saveName = ""
    @Published var hover: String?
    @Published var fitRequest = 0
    @Published var showLegend = true
    @Published var zoomSeq = 0
    var zoomFactor: CGFloat = 1
    func requestZoom(_ f: CGFloat) { zoomFactor = f; zoomSeq += 1 }
    private(set) var degree: [String: Int] = [:]
    private var changes: [String: String] = [:]
    private weak var state: AppState?
    static let cap = 200
    let canvas = ForceLayout.Options()

    func load(state: AppState) {
        self.state = state
        guard let db = state.db, let s = state.lastScan ?? (try? ScanRepo.latestCompletedOrPartial(db)) else { graph = nil; return }
        let obs = (try? ScanRepo.observations(db, scanID: s.scanID)) ?? []
        graph = GraphBuilder().build(observations: obs, findings: state.findings, scopes: state.scopes, scanID: s.scanID)
        if let d = Settings.get(db, "graph_pins"), let p = try? JSONDecoder().decode([String: LayoutPoint].self, from: Data(d.utf8)) { pinned = p }
        if let d = Settings.get(db, "saved_views"), let v = try? JSONDecoder().decode([SavedGraphView].self, from: Data(d.utf8)) { savedViews = v }
        applyDiff(state.diff)
        rebuild()
    }

    func applyDiff(_ diff: [DiffEntry]) {
        var m: [String: String] = [:]
        for d in diff {
            let label = d.change == .added ? "추가" : d.change == .removed ? "삭제" : d.change == .modified ? "수정" : "비교 불가"
            if let ex = m[d.objectID], ex == "비교 불가" || (ex == "수정" && label != "비교 불가") { continue }
            m[d.objectID] = label
        }
        changes = m
        if mode == .changes { rebuild() }
    }

    func change(for id: String) -> String? { changes[id] }
    func node(_ id: String) -> GraphNode? { graph?.nodes.first { $0.id == id } }
    func edges(of id: String) -> [GraphEdge] { graph?.edges.filter { $0.from == id || $0.to == id } ?? [] }

    func rebuild() {
        guard let g = graph else { return }
        var nodes = g.nodes.filter { typeFilter.contains($0.type) }
        if severityFilter != "all" { let ids = Set(nodes.filter { $0.severity == severityFilter }.map { $0.id }); nodes = nodes.filter { ids.contains($0.id) || $0.type != .finding } }
        if stateFilter != "all" { nodes = nodes.filter { $0.type != .finding || $0.state == stateFilter } }
        if !query.isEmpty { let q = query.lowercased(); nodes = nodes.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) || $0.type.rawValue.lowercased().contains(q) } }
        let pairs = g.edges.map { ($0.from, $0.to) }
        if mode == .neighborhood, let s = selected {
            let keep = ForceLayout.neighborhood(of: s, edges: pairs, depth: depth)
            nodes = g.nodes.filter { keep.contains($0.id) }
        } else if mode == .changes {
            let changed = Set(changes.keys)
            let keep = changed.union(changed.flatMap { ForceLayout.neighborhood(of: $0, edges: pairs, depth: 1) })
            nodes = g.nodes.filter { keep.contains($0.id) }
        }
        hiddenByCap = max(0, nodes.count - Self.cap)
        if nodes.count > Self.cap {
            nodes.sort { ($0.severity == "high" ? 0 : $0.severity != nil ? 1 : 2, $0.id) < ($1.severity == "high" ? 0 : $1.severity != nil ? 1 : 2, $1.id) }
            nodes = Array(nodes.prefix(Self.cap))
        }
        let ids = Set(nodes.map { $0.id })
        visibleNodes = nodes
        visibleEdges = g.edges.filter { ids.contains($0.from) && ids.contains($0.to) }
        var deg: [String: Int] = [:]
        for e in visibleEdges { deg[e.from, default: 0] += 1; deg[e.to, default: 0] += 1 }
        degree = deg
        let pins = pinned.filter { ids.contains($0.key) }
        let s = ForceSimulation(nodeIDs: nodes.map { $0.id }, edges: visibleEdges.map { ($0.from, $0.to) }, pinned: pins, options: canvas)
        s.run(maxTicks: 400)
        sim = s
        positions = s.positions
        fitRequest += 1
        startTicking()
    }

    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let s = self.sim else { t.invalidate(); return }
                for _ in 0..<2 { s.tick() }
                self.positions = s.positions
                if s.isSettled { t.invalidate(); self.ticker = nil }
            }
        }
    }

    func reheat() {
        sim?.reheat()
        if ticker == nil { startTicking() }
    }

    func resetLayout() { pinned = [:]; persistPins(); rebuild() }
    func fitToView() { fitRequest += 1 }

    func togglePin(_ id: String) {
        if pinned[id] != nil { pinned.removeValue(forKey: id); sim?.unpin(id) }
        else if let p = positions[id] { pinned[id] = p; sim?.pin(id, at: p) }
        persistPins(); reheat()
    }
    func pin(_ id: String, at p: LayoutPoint) { pinned[id] = p; positions[id] = p; sim?.pin(id, at: p); reheat() }
    func persistPins() {
        guard let db = state?.db, let d = try? JSONEncoder().encode(pinned) else { return }
        try? Settings.set(db, "graph_pins", String(decoding: d, as: UTF8.self))
    }

    func selectFirstMatch() { selected = visibleNodes.first?.id }

    func saveCurrent() {
        guard savedViews.count < 5 else { return }
        let v = SavedGraphView(id: Ids.new("view"), name: saveName.isEmpty ? "보기 \(savedViews.count + 1)" : saveName, mode: mode.rawValue, depth: depth, center: selected,
                               types: typeFilter.map { $0.rawValue }.sorted(), severity: severityFilter, state: stateFilter, query: query, pins: pinned)
        savedViews.append(v); saveName = ""; persistViews()
    }
    func restore(_ v: SavedGraphView) {
        typeFilter = Set(v.types.compactMap { Ontology.NodeType(rawValue: $0) }); severityFilter = v.severity; stateFilter = v.state; query = v.query
        depth = v.depth; pinned = v.pins; selected = v.center; mode = Mode(rawValue: v.mode) ?? .full
        rebuild()
    }
    func delete(_ v: SavedGraphView) { savedViews.removeAll { $0.id == v.id }; persistViews() }
    func persistViews() {
        guard let db = state?.db, let d = try? JSONEncoder().encode(savedViews) else { return }
        try? Settings.set(db, "saved_views", String(decoding: d, as: UTF8.self))
    }
}


/// AppKit 캔버스. 스크롤·핀치로 커서 기준 확대, 빈 곳 드래그로 이동, 노드 드래그로 위치 고정, 호버로 이웃 강조.
struct GraphCanvasView: NSViewRepresentable {
    @ObservedObject var vm: GraphViewModel

    func makeNSView(context: Context) -> GraphNSView {
        let v = GraphNSView(vm: vm)
        context.coordinator.bind(v)
        return v
    }
    func updateNSView(_ nsView: GraphNSView, context: Context) { nsView.needsDisplay = true }
    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    final class Coordinator {
        let vm: GraphViewModel
        var cancellable: AnyCancellable?
        init(vm: GraphViewModel) { self.vm = vm }
        func bind(_ view: GraphNSView) {
            cancellable = vm.objectWillChange.receive(on: RunLoop.main).sink { [weak view] _ in view?.needsDisplay = true }
        }
    }
}

final class GraphNSView: NSView {
    let vm: GraphViewModel
    private var scale: CGFloat = 1
    private var offset = CGPoint.zero
    private var fitted = false
    private var lastFitRequest = 0
    private var lastZoomSeq = 0
    private var dragNode: String?
    private var dragStart = CGPoint.zero
    private var moved = false
    private var trackingArea: NSTrackingArea?

    init(vm: GraphViewModel) {
        self.vm = vm
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
        super.updateTrackingAreas()
    }

    // MARK: 좌표

    func toView(_ p: LayoutPoint) -> CGPoint { CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y) }
    func toWorld(_ v: CGPoint) -> LayoutPoint { LayoutPoint(x: (v.x - offset.x) / scale, y: (v.y - offset.y) / scale) }

    func fit() {
        let ps = vm.positions.values
        guard !ps.isEmpty, bounds.width > 10 else { return }
        let minX = ps.map { $0.x }.min()! - 60, maxX = ps.map { $0.x }.max()! + 60
        let minY = ps.map { $0.y }.min()! - 60, maxY = ps.map { $0.y }.max()! + 60
        let bw = max(200, maxX - minX), bh = max(200, maxY - minY)
        let usableH = bounds.height - 44
        scale = min(bounds.width / bw, usableH / bh)
        offset = CGPoint(x: (bounds.width - bw * scale) / 2 - minX * scale, y: (usableH - bh * scale) / 2 - minY * scale + 4)
        fitted = true
    }

    func zoom(by factor: CGFloat, around v: CGPoint) {
        let newScale = min(8, max(0.05, scale * factor))
        let f = newScale / scale
        offset = CGPoint(x: v.x - (v.x - offset.x) * f, y: v.y - (v.y - offset.y) * f)
        scale = newScale
        needsDisplay = true
    }

    // MARK: 입력

    func hit(_ v: CGPoint) -> String? {
        var best: (String, CGFloat)?
        for n in vm.visibleNodes {
            guard let p = vm.positions[n.id] else { continue }
            let c = toView(p)
            let d = hypot(c.x - v.x, c.y - v.y)
            if d <= radius(n) + 5, best == nil || d < best!.1 { best = (n.id, d) }
        }
        return best?.0
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let v = convert(event.locationInWindow, from: nil)
        dragStart = v; moved = false
        dragNode = hit(v)
        if event.clickCount == 2, let id = dragNode { vm.togglePin(id); dragNode = nil }
    }
    override func mouseDragged(with event: NSEvent) {
        let v = convert(event.locationInWindow, from: nil)
        if hypot(v.x - dragStart.x, v.y - dragStart.y) > 2 { moved = true }
        if let id = dragNode { vm.pin(id, at: toWorld(v)) }
        else { offset.x += event.deltaX; offset.y += event.deltaY; needsDisplay = true }
    }
    override func mouseUp(with event: NSEvent) {
        let v = convert(event.locationInWindow, from: nil)
        if !moved { vm.selected = hit(v) } else if dragNode != nil { vm.persistPins() }
        dragNode = nil
    }
    override func mouseMoved(with event: NSEvent) {
        let h = hit(convert(event.locationInWindow, from: nil))
        if h != vm.hover { vm.hover = h }
    }
    override func mouseExited(with event: NSEvent) { if vm.hover != nil { vm.hover = nil } }
    override func scrollWheel(with event: NSEvent) {
        let v = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
            offset.x += event.scrollingDeltaX; offset.y += event.scrollingDeltaY; needsDisplay = true
            return
        }
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 4
        zoom(by: pow(1.0035, dy), around: v)
    }
    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, around: convert(event.locationInWindow, from: nil))
    }
    override func keyDown(with event: NSEvent) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        switch event.charactersIgnoringModifiers {
        case "=", "+": zoom(by: 1.25, around: center)
        case "-": zoom(by: 0.8, around: center)
        case "0": fit(); needsDisplay = true
        case "\u{1B}": vm.selected = nil
        default: super.keyDown(with: event)
        }
    }

    // MARK: 그리기

    func radius(_ n: GraphNode) -> CGFloat {
        let d = CGFloat(vm.degree[n.id] ?? 0)
        let base: CGFloat = n.type == .agent || n.type == .project ? 7 : n.type == .finding ? 6 : 5
        return (base + min(9, sqrt(d) * 1.6)) * max(0.6, min(1.6, scale))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if vm.fitRequest != lastFitRequest || !fitted { lastFitRequest = vm.fitRequest; fit() }
        if vm.zoomSeq != lastZoomSeq { lastZoomSeq = vm.zoomSeq; zoom(by: vm.zoomFactor, around: CGPoint(x: bounds.midX, y: bounds.midY)) }
        NSColor.textBackgroundColor.setFill(); ctx.fill(bounds)
        let focus = vm.hover ?? vm.selected
        let related: Set<String> = focus.map { f in Set(vm.visibleEdges.filter { $0.from == f || $0.to == f }.flatMap { [$0.from, $0.to] }).union([f]) } ?? []
        let dim = focus != nil

        for e in vm.visibleEdges {
            guard let a = vm.positions[e.from], let b = vm.positions[e.to] else { continue }
            let hot = related.contains(e.from) && related.contains(e.to) && (e.from == focus || e.to == focus)
            let change = vm.change(for: e.to) ?? vm.change(for: e.from)
            var color: NSColor = change == "추가" ? .systemGreen : change == "삭제" ? .systemRed : change == "비교 불가" ? .systemOrange : .tertiaryLabelColor
            color = color.withAlphaComponent(hot ? 0.95 : dim ? 0.12 : 0.45)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(hot ? 2 : 1)
            if e.epistemic == .derived || change == "비교 불가" { ctx.setLineDash(phase: 0, lengths: [4, 3]) } else { ctx.setLineDash(phase: 0, lengths: []) }
            ctx.move(to: toView(a)); ctx.addLine(to: toView(b)); ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])

        let showAllLabels = scale > 1.6 || vm.visibleNodes.count <= 30
        let font = AppFont.nsFont(max(9, min(13, 11 * scale)))
        for n in vm.visibleNodes {
            guard let p = vm.positions[n.id] else { continue }
            let c = toView(p), r = radius(n)
            let faded = dim && !related.contains(n.id)
            let fill = GraphNSView.color(n.type).withAlphaComponent(faded ? 0.25 : 1)
            ctx.setFillColor(fill.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            if n.severity == "high" { ctx.setStrokeColor(NSColor.systemRed.withAlphaComponent(faded ? 0.3 : 1).cgColor); ctx.setLineWidth(2); ctx.strokeEllipse(in: CGRect(x: c.x - r - 3, y: c.y - r - 3, width: r * 2 + 6, height: r * 2 + 6)) }
            if vm.pinned[n.id] != nil { ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(faded ? 0.3 : 0.9).cgColor); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: CGRect(x: c.x - r - 1.5, y: c.y - r - 1.5, width: r * 2 + 3, height: r * 2 + 3)) }
            if vm.selected == n.id { ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(2.5); ctx.strokeEllipse(in: CGRect(x: c.x - r - 5, y: c.y - r - 5, width: r * 2 + 10, height: r * 2 + 10)) }
            let wantLabel = showAllLabels || related.contains(n.id) || vm.pinned[n.id] != nil || n.type == .agent || n.type == .project || n.severity == "high"
            if wantLabel && !faded {
                let text = n.label.count > 32 ? String(n.label.prefix(31)) + "…" : n.label
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(related.contains(n.id) || !dim ? 0.9 : 0.5)]
                let str = NSAttributedString(string: text, attributes: attrs)
                let size = str.size()
                let origin = CGPoint(x: c.x - size.width / 2, y: c.y + r + 3)
                let bg = CGRect(x: origin.x - 3, y: origin.y - 1, width: size.width + 6, height: size.height + 2)
                ctx.setFillColor(NSColor.textBackgroundColor.withAlphaComponent(0.7).cgColor)
                ctx.fill(bg)
                str.draw(at: origin)
            }
            if let ch = vm.change(for: n.id), !faded {
                let a: [NSAttributedString.Key: Any] = [.font: AppFont.nsFont(9, .medium), .foregroundColor: ch == "추가" ? NSColor.systemGreen : ch == "삭제" ? NSColor.systemRed : NSColor.systemOrange]
                let str = NSAttributedString(string: ch, attributes: a)
                str.draw(at: CGPoint(x: c.x - str.size().width / 2, y: c.y - r - 13))
            }
        }
    }

    static func color(_ t: Ontology.NodeType) -> NSColor {
        switch t {
        case .agent: return .systemBlue; case .configuration: return .systemTeal; case .mcpServer: return .systemIndigo; case .endpoint: return .systemPurple
        case .secretCandidate: return .systemRed; case .finding: return .systemOrange; case .rule: return .systemGray; case .permissionRule: return .systemCyan
        case .hook: return .systemBrown; case .instructionFile: return .systemMint; case .file: return .systemGray; case .project: return .systemGreen; case .device: return .labelColor
        default: return .secondaryLabelColor
        }
    }
}
