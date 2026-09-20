import Foundation
import ServiceManagement

/// 로그인 시 자동 시작.
enum LoginItem {
    static var status: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requires_approval"
        case .notRegistered: return "not_registered"
        case .notFound: return "not_found"
        @unknown default: return "unknown"
        }
    }
    static var statusLabel: String {
        switch status {
        case "enabled": return "자동 시작 켜짐"
        case "requires_approval": return "시스템 설정에서 승인 필요 (로그인 항목)"
        case "not_registered": return "자동 시작 꺼짐"
        case "not_found": return "앱 위치, 서명 확인 필요 (재설치 후 다시 켜세요)"
        default: return "알 수 없음"
        }
    }
    static func setEnabled(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch { return "\(error.localizedDescription)" }
    }
}
