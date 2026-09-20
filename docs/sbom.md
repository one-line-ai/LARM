# SBOM·라이선스 검토 (N12)

릴리스 0.6.0 (2026-09-20)

| 구성요소 | 버전 | 출처 | 라이선스 | 비고 |
|---|---|---|---|---|
| LARMCore / LARM / larm-hook / larm-verify | 0.6.0 | 이 저장소 `products/larm` | 사내 | 외부 Swift 패키지 의존성 0 (Package.swift에 dependencies 없음) |
| Foundation, AppKit, SwiftUI, Combine | macOS SDK (CLT 26.5) | Apple | Apple SDK | 시스템 프레임워크 |
| CoreServices (FSEvents), UserNotifications, ServiceManagement, Security, CryptoKit | macOS SDK | Apple | Apple SDK | 시스템 프레임워크 |
| libsqlite3 | 시스템 동봉 | Apple/SQLite | Public domain | `linkerSettings: linkedLibrary("sqlite3")` |
| Testing.framework (시험 전용) | CLT 동봉 | Apple/Swift | Apache-2.0 | 배포 번들에 포함되지 않음 |

- 룰·안내 리소스는 데이터(JSON/Markdown)이며 실행 코드가 아니다. 서명된 갱신 패키지만 받는다 (F27).
- 외부 탐지 도구(gitleaks 등, S9)는 채택하지 않았다. 비밀정보 패턴은 자체 구현.
- 빌드 출처: `install.sh`가 설치 번들 해시를 `dist/*.sha256`에, `make-dist.sh`가 DMG 해시를 `dist/SHA256SUMS`에 남긴다.
- 고위험 취약점 검토: 외부 의존성이 없어 해당 없음. SDK 취약점은 OS 업데이트로 관리.
