# LARM (Local Agent Risk Monitor)

내 Mac의 AI 코딩 도구(Claude Code, Codex CLI, Cursor MCP) 설정을 점검하고, 위험 신호를 조치한 뒤 재점검과 증빙으로 결과를 확인하는 macOS 앱.
요건: `LARM_업무요건정의서_v2.1_SLC_수정.docx` (59개 요건 F01~F44, N01~N15).

## 현재 마일스톤

| 단계 | 상태 | 내용 |
|---|---|---|
| M0 뼈대 | 완료 | SwiftPM 4타깃, 수작업 .app 번들, ad-hoc 서명, SQLite(0600)/Keychain 키, 메뉴바 상주 |
| M1 정적 점검 | 완료 | 3개 어댑터, R01~R08, 발견 사항·상세·수동 조치 안내·재점검, 점검 공백 |
| M2 기준점·증빙 | 완료 | 스냅샷·diff·기준점·기한 예외·엔드포인트 검토·보존·증빙 ZIP(larm-evidence/1.1)·larm-verify·그래프 모델 |
| M3 상주 감시 | 완료 | 로그인 항목·FSEvents(설정 폴더)+60초 폴링(루트 파일)·30분 대조·10초 건강 확인·공백 기록·일시중지·알림(24시간 묶음·조용한 시간) |
| M4 활동 수집 | 완료 | Claude Code hook 연동(관측 전용, 사용자 확인 후 등록)·Unix 소켓+spool·RR01/RR02·활동 화면·증빙 events.json |
| M5 그래프·편의 | 완료 | Canvas 근거 그래프(전체/주변/변경, 200노드 상한, pin, 표 전환)·저장 보기 5개·검색·오늘 할 일·조용한 시간 |
| M6 강화 | 1차 완료 | 상한 fixture·전 저장면 canary·진단 파일·서명 룰 갱신(Ed25519)·SBOM·make-dist·수용 시험 추적표. 성능 실측(N05)·72시간(N13)·공증(N06)·독립 검증(N10)은 미실행 |

조건부 요건 F42/F43/N15(실행 전 확인·정책 집행)는 구현하지 않으며 관측 모드로 제한한다 (요건 11.1).

## 빌드 없이 설치 (DMG)

1. https://github.com/one-line-ai/AIops/raw/main/products/larm/dist/LARM-0.6.1.dmg 를 내려받는다 (해시: `dist/SHA256SUMS`).
2. DMG를 열고 LARM.app을 Applications 폴더로 끌어 넣는다.
3. ad-hoc 서명이라 처음 열 때 경고가 나오면 터미널에서 `xattr -dr com.apple.quarantine /Applications/LARM.app` 을 실행한 뒤 다시 연다.
4. 첫 실행 때 Keychain 접근 허용을 묻는다. 허용해야 점검과 감시가 시작된다.

## 빌드·설치 (macOS, Xcode 없이 Command Line Tools만으로)

```bash
cd products/larm
./install.sh          # swift build -c release → /Applications/LARM.app (ad-hoc 서명) → 실행
./test.sh             # swift test (Testing.framework 경로 지정 래퍼)
./uninstall.sh        # 앱 제거. --purge 를 붙이면 앱 데이터·Keychain 키까지 삭제
```

- 빌드 산출물은 `$TMPDIR/larm-build`에 둔다. 저장소가 `~/Documents` 아래면 SwiftPM 빌드 DB가 disk I/O 오류를 내기 때문이다.
- Developer ID 서명·공증(N06)은 이 PC에서 불가하며 출시 게이트 LG5 항목으로 유보한다.
- 설치 시 번들 파일 해시를 `dist/LARM-<버전>-installed.sha256`에 남긴다.
- ad-hoc 서명은 빌드마다 바뀌므로 재설치 후 첫 실행에 macOS가 Keychain 접근 허용을 묻는다. 허용할 때까지 앱은 점검·감시를 시작하지 않는다(약한 임시 키로 대체하지 않음, N03). Developer ID 서명(LG5)에서는 사라진다.

## 헤드리스 점검 (진단·시험 증빙)

```bash
/Applications/LARM.app/Contents/MacOS/LARM --scan [--add-project <폴더>] [--remove-project <폴더>]
/Applications/LARM.app/Contents/MacOS/LARM --status
/Applications/LARM.app/Contents/MacOS/LARM --baseline "<사유>"      # 마지막 점검을 기준점으로
/Applications/LARM.app/Contents/MacOS/LARM --export <out.zip>       # 증빙 묶음
/Applications/LARM.app/Contents/MacOS/larm-verify <out.zip> [--expect-manifest-sha256 <hex>]
/Applications/LARM.app/Contents/MacOS/LARM --install-hook [--yes]   # ~/.claude/settings.json 변경 전후를 보여주고 --yes 일 때만 적용
/Applications/LARM.app/Contents/MacOS/LARM --uninstall-hook [--yes]
/Applications/LARM.app/Contents/MacOS/larm-hook --test               # 시험 이벤트
```

## 데이터 위치와 원칙

- `~/Library/Application Support/LARM/` (0700): `larm.sqlite` (0600), `spool/`
- 원문 토큰·비밀값은 저장하지 않는다. 설치별 Keychain 키로 만든 HMAC 지문만 로컬에 둔다 (증빙에는 제외).
- 발견한 실행 파일·hook·MCP 서버·URL을 실행/호출하지 않는다. 네트워크 요청 0건.
- LARM은 설정·파일·프로세스·네트워크를 자동 변경하지 않는다. 조치는 사용자가 벤더 설정에서 한다.

## 읽는 위치 (발견 후보)

| 도구 | 사용자 | 프로젝트 |
|---|---|---|
| Claude Code | `~/.claude/settings.json`, `~/.claude.json`(mcpServers·projects[*].mcpServers/allowedTools만), `/Library/Application Support/ClaudeCode/managed-settings.json` | `.claude/settings.json`, `.claude/settings.local.json`, `.mcp.json`, `CLAUDE.md`, `.claude/{skills,agents,commands,hooks}` |
| Codex CLI | `~/.codex/config.toml`, `~/.codex/AGENTS.md` | `.codex/config.toml`, `AGENTS.md` |
| Cursor | `~/.cursor/mcp.json` | `.cursor/mcp.json` |

자격증명 저장 위치(`~/.claude/.credentials.json`, `~/.codex/auth.json`)는 권한만 확인하고 내용을 읽지 않는다.

## 구조

```
Sources/LARMCore   결정론 엔진 (어댑터·안전 파서·비밀정보 제거·룰·저장소). AppKit 미포함
Sources/LARM       SwiftUI 앱 (창 + 메뉴바, 단일 상주 프로세스)
Sources/larm-hook  Claude Code hook 수신기 (M4)
Sources/larm-verify 오프라인 증빙 검증기 (M2)
Tests/LARMCoreTests fixture 기반 골든·생명주기·canary 시험
docs/acceptance.md  T01~T59 추적표
```
