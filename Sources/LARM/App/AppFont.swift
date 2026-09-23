import SwiftUI
import AppKit
import CoreText

/// Pretendard를 번들에서 등록하고 화면 서체를 한 곳에서 정한다. 등록에 실패하면 시스템 서체로 자연스럽게 대체된다.
enum AppFont {
    static let family = "Pretendard"
    private(set) static var available = false

    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "otf" {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
        available = NSFont(name: "Pretendard-Regular", size: 12) != nil
    }

    static func name(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Pretendard-Bold"
        case .semibold: return "Pretendard-SemiBold"
        case .medium: return "Pretendard-Medium"
        default: return "Pretendard-Regular"
        }
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        available ? .custom(name(weight), size: size, relativeTo: style) : .system(size: size, weight: weight)
    }

    static var largeTitle: Font { font(26, .bold, relativeTo: .largeTitle) }
    static var title2: Font { font(20, .semibold, relativeTo: .title2) }
    static var title3: Font { font(16, .semibold, relativeTo: .title3) }
    static var headline: Font { font(13, .semibold, relativeTo: .headline) }
    static var body: Font { font(13, .regular, relativeTo: .body) }
    static var callout: Font { font(12.5, .regular, relativeTo: .callout) }
    static var footnote: Font { font(11.5, .regular, relativeTo: .footnote) }
    static var caption: Font { font(11, .regular, relativeTo: .caption) }
    static var caption2: Font { font(10, .regular, relativeTo: .caption2) }
    static var mono: Font { .system(.callout, design: .monospaced) }

    static func nsFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let n = weight == .bold ? "Pretendard-Bold" : weight == .semibold ? "Pretendard-SemiBold" : weight == .medium ? "Pretendard-Medium" : "Pretendard-Regular"
        return NSFont(name: n, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}
