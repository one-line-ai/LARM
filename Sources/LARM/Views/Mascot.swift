import SwiftUI

/// 단순한 캐릭터 "라미". 도형만으로 그려 듀오톤 팔레트를 따른다.
struct Mascot: View {
    enum Mood { case watching, paused, risk, clear, empty }
    var mood: Mood
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().fill(Theme.indigo)
            Circle().fill(Theme.surface).scaleEffect(0.86)
            face
        }
        .frame(width: size, height: size)
        .accessibilityLabel(label)
    }

    var label: String {
        switch mood { case .watching: return "지켜보는 중"; case .paused: return "쉬는 중"; case .risk: return "확인 필요"; case .clear: return "이상 없음"; case .empty: return "기록 없음" }
    }

    @ViewBuilder var face: some View {
        let s = size
        switch mood {
        case .watching:
            HStack(spacing: s * 0.16) { eye(open: true); eye(open: true) }.offset(y: -s * 0.05)
            mouth(curve: 0.15).offset(y: s * 0.2)
        case .paused:
            HStack(spacing: s * 0.16) { eye(open: false); eye(open: false) }.offset(y: -s * 0.05)
            mouth(curve: 0.05).offset(y: s * 0.2)
            Text("z").font(AppFont.font(s * 0.28, .bold)).foregroundStyle(Theme.indigoSoft).offset(x: s * 0.3, y: -s * 0.32)
        case .risk:
            HStack(spacing: s * 0.16) { eye(open: true); eye(open: true) }.offset(y: -s * 0.05)
            mouth(curve: -0.15).offset(y: s * 0.22)
            Text("!").font(AppFont.font(s * 0.34, .bold)).foregroundStyle(Theme.accent).offset(x: s * 0.33, y: -s * 0.33)
        case .clear:
            HStack(spacing: s * 0.16) { happyEye; happyEye }.offset(y: -s * 0.05)
            mouth(curve: 0.3).offset(y: s * 0.18)
        case .empty:
            HStack(spacing: s * 0.16) { eye(open: true); eye(open: true) }.offset(y: -s * 0.05)
            Circle().fill(Theme.indigo).frame(width: s * 0.1, height: s * 0.1).offset(y: s * 0.22)
        }
    }

    func eye(open: Bool) -> some View {
        Group {
            if open { Circle().fill(Theme.indigo).frame(width: size * 0.12, height: size * 0.12) }
            else { Capsule().fill(Theme.indigo).frame(width: size * 0.16, height: size * 0.04) }
        }
    }
    var happyEye: some View {
        Arc(curve: 0.5).stroke(Theme.indigo, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round)).frame(width: size * 0.16, height: size * 0.1)
    }
    func mouth(curve: CGFloat) -> some View {
        Arc(curve: curve).stroke(Theme.indigo, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round)).frame(width: size * 0.3, height: size * 0.12)
    }
}

/// 위로(양수) 또는 아래로(음수) 휘는 호.
struct Arc: Shape {
    var curve: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.midY + r.height * curve * 4))
        return p
    }
}

/// 캐릭터와 한 줄 안내를 함께 보여 주는 빈 상태.
struct FriendlyEmpty: View {
    var mood: Mascot.Mood
    var title: String
    var note: String? = nil
    var body: some View {
        VStack(spacing: 10) {
            Mascot(mood: mood, size: 72)
            Text(title).font(AppFont.headline)
            if let n = note { Text(n).font(AppFont.callout).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center).frame(maxWidth: 420) }
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}
