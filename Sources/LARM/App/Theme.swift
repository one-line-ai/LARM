import SwiftUI
import AppKit
import LARMCore

/// 듀오톤: 짙은 남보라와 모래색 두 계열만 씀. 위험도는 색 대신 농도와 굵기로 구분함.
enum Theme {
    static let indigo = Color(light: 0x2D2A5E, dark: 0xC9C6F2)
    static let indigoSoft = Color(light: 0x5A57A8, dark: 0x9C99E0)
    static let indigoFaint = Color(light: 0xB9B7DD, dark: 0x5E5B92)
    static let sand = Color(light: 0xEFE9DE, dark: 0x1B1940)
    static let sandDeep = Color(light: 0xE3DCCD, dark: 0x262358)
    static let surface = Color(light: 0xFFFFFF, dark: 0x25235A)
    static let ink = Color(light: 0x2D2A5E, dark: 0xEFE9DE)
    static let inkSoft = Color(light: 0x6B6A85, dark: 0xB8B5D6)
    static let mute = Color(light: 0x8C877A, dark: 0x8F8CB0)
    static let sidebar = Color(light: 0x2D2A5E, dark: 0x14123A)
    static let sidebarText = Color(light: 0xEFE9DE, dark: 0xE4E1F5)
    static let sidebarSelected = Color(light: 0x5A57A8, dark: 0x3F3C7E)

    static func nsColor(_ c: Color) -> NSColor { NSColor(c) }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(NSColor(name: nil) { app in
            let hex = app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// 흰 면에 남보라 제목. 테두리 없이 면으로만 구분함.
struct DuoPanel: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label.font(AppFont.font(12, .semibold)).foregroundStyle(Theme.indigoSoft).textCase(nil)
            configuration.content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// 위험도 배지: 높음 = 남보라 채움, 중간 = 남보라 테두리, 낮음·점검 필요 = 회색 글자.
struct SeverityBadge: View {
    let severity: Severity
    var body: some View {
        Text(severity.label)
            .font(AppFont.font(11, severity == .high ? .bold : .medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(severity == .high ? Theme.indigo : Color.clear)
            .foregroundStyle(severity == .high ? Theme.sand : severity == .medium ? Theme.indigo : Theme.mute)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(severity == .medium ? Theme.indigo : severity == .high ? Color.clear : Theme.indigoFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("위험도 \(severity.label)")
    }
}

struct StateBadge: View {
    let state: FindingState
    var body: some View {
        Text(state.label).font(AppFont.caption).foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.sandDeep).clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
