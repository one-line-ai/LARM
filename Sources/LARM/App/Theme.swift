import SwiftUI
import AppKit
import LARMCore

/// 남색·흰색·연한 회청색 바탕에 금색 강조. 토큰 이름은 이전 것을 그대로 두고 값만 바꿈.
enum Theme {
    static let indigo = Color(light: 0x1F2B48, dark: 0xD6DEEE)        // 남색 (제목, 강한 글자)
    static let indigoSoft = Color(light: 0x3A4A6E, dark: 0xAEBBD9)    // 옅은 남색 (소제목, 보조 강조)
    static let indigoFaint = Color(light: 0xD5DAE6, dark: 0x3A4460)   // 테두리, 옅은 선
    static let sand = Color(light: 0xF4F5F9, dark: 0x141926)          // 화면 바탕 (연한 회청색)
    static let sandDeep = Color(light: 0xE9ECF3, dark: 0x222A3C)      // 배지 바탕, 구분 면
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C2333)       // 카드 면
    static let ink = Color(light: 0x1F2B48, dark: 0xE8ECF4)
    static let inkSoft = Color(light: 0x6E7891, dark: 0xA8B2C8)
    static let mute = Color(light: 0x9AA3B5, dark: 0x7C8699)
    static let accent = Color(light: 0xC9A23F, dark: 0xD9B85A)        // 금색 (미해결, 보류, 높은 위험)
    static let sidebar = Color(light: 0xFFFFFF, dark: 0x1C2333)
    static let sidebarText = Color(light: 0x1F2B48, dark: 0xE8ECF4)
    static let sidebarSelected = Color(light: 0x2B3A5C, dark: 0x3A4A6E)
    static let sidebarSelectedText = Color(light: 0xFFFFFF, dark: 0xFFFFFF)

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

/// 흰 카드에 옅은 테두리, 남색 제목.
struct DuoPanel: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label.font(AppFont.font(12, .semibold)).foregroundStyle(Theme.indigoSoft).textCase(nil)
            configuration.content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.indigoFaint, lineWidth: 1))
    }
}

/// 위험도 배지: 높음 = 금색 채움, 중간 = 남색 테두리, 낮음·점검 필요 = 회색 글자.
struct SeverityBadge: View {
    let severity: Severity
    var body: some View {
        Text(severity.label)
            .font(AppFont.font(11, severity == .high ? .bold : .medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(severity == .high ? Theme.accent : Color.clear)
            .foregroundStyle(severity == .high ? Color.white : severity == .medium ? Theme.indigo : Theme.mute)
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
