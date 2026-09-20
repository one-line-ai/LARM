# 수용 시험 추적표 (T01~T59)

상태 값: NOT_RUN / PARTIAL(일부 구현·일부 시험) / PASS(자체)(개발자 자동 시험 통과) / FAIL / N/A(비적용, 사유 기록).
PASS(자체)는 개발자의 fixture 시험이며 N10의 독립 검증(LG2)이 아니다. 통과하지 않은 시험을 통과로 적지 않는다.

환경: macOS 26.6.2 (25G83) arm64 · 앱 0.6.0 · 룰 1.0.0 · 어댑터 claude-code/codex/cursor 1.0.0 · 실행 `./test.sh` · 갱신 2026-09-20

| 시험 | 요건 | 시나리오 | 상태 | 근거·증빙·미실행 사유 |
|---|---|---|---|---|
| T01 | F01 | 새 계정에서 첫 점검 | PARTIAL | 설치→첫 점검 흐름·시험 이벤트 확인 구현. 새 계정 5분 시험·자동 시작 실기 미실행 |
| T02 | F02 | 경로·동의 경계 | PARTIAL | 범위 밖 symlink 거부·제외 폴더 구현. 20개 프로젝트 재실행 복원 시험 미실행 |
| T03 | F03 | 위장 실행 파일·버전 불명 | PASS(자체) | RulesGoldenTests.noExecutionOfDiscoveredBinaries: 가짜 claude 실행 0, 버전 불명·설치 구분 |
| T04 | F04 | 우선순위·신뢰·중복 키 | PARTIAL | 중복 키 오류(ParserTests), profile 미해결→unknown. 관리 설정 충돌 fixture 미작성 |
| T05 | F05 | MCP 50개·민감 인자 | PARTIAL | 정의·env·header·URL 정규화, 외부 호출 0. 50개 fixture 미작성 |
| T06 | F06 | 승인과 sandbox 교차 4조합 | PARTIAL | never+full(high)·on-request+workspace(음성) 확인. never+read-only, on-request+full fixture 미작성 |
| T07 | F07 | 파일·통신 설정 3상태 | PARTIAL | 제한/확장/미관측 필드 존재. fixture 미작성 |
| T08 | F08 | allow/deny 충돌·낯선 문법 | PASS(자체) | Golden: Bash(*) high, Write/mcp__x medium, deny 제한, 해석 불가→unknown |
| T09 | F09 | 사내 프록시·OAuth·HTTP | PASS(자체) | 엔드포인트 검토 기록(host·scheme·port 단위)→medium 해소, 평문 HTTP high 유지 (baselineAndExceptions) |
| T10 | F10 | 합성 비밀정보·변수 참조 | PASS(자체) | secretCanarySet: 40/40 탐지, 음성 100 중 오탐 ≤5, ${VAR} 제외, live 검증 0 |
| T11 | F11 | 0600/0644/ACL/거절 | PARTIAL | 0644 auth.json high, ACL unknown. 타 소유자·거절 fixture 미작성 |
| T12 | F12 | 명령 포함 프로젝트 열기 전 점검 | PASS(자체) | project-risky: 임의 코드 실행 0, hook·지시 파일 digest만 보고 |
| T13 | F13 | 부분 오류·취소·오래된 결과 | PARTIAL | 거절→partial, 취소→cancelled 상태. 경과 시간 표시 있음. 취소 UI 시험 미실행 |
| T14 | F14 | 안정 지문·토큰 변경·키 교체 | PASS(자체) | EvidenceTests.stableDigestAndSecretChange: 내용 동일→digest 동일, 토큰 1자 변경→secret digest만 변경, 키 교체→지문 비교 불가 |
| T15 | F15 | 추가·삭제·범위 이탈 비교 | PASS(자체) | EvidenceTests.diffDistinguishesRemovedFromIncomparable: 파일 부재→삭제 확정, 권한 거절→비교 불가. 어댑터 버전은 digest에 포함 |
| T16 | F16 | 위험 설정을 기준점으로 지정 | PASS(자체) | EvidenceTests.baselineAndExceptions: 부분 점검 기준점 거절, 기준점 후 고위험 유지, R05 미검토만 해소 |
| T17 | F17 | 8룰 Golden/unknown 반복 실행 | PASS(자체) | deterministicAcrossRuns: 판정·target_fp 동일. 룰 로딩 실패→점검 불가 표시(코드) 시험 미작성 |
| T18 | F18 | 반복·재발·수동 완료 | PASS(자체) | LifecycleTests: 중복 카드 없음, 사용자 전환은 in_progress까지, 재점검 해소는 엔진만 |
| T19 | F19 | 수동 조치·복사·외부 링크 | PARTIAL | 안내·복사(비밀값 제거) 구현. 외부 링크 없음 |
| T20 | F20 | 실제 수정과 권한 거절 재점검 | PASS(자체) | LifecycleTests: 수정→resolved_by_rescan, 거절→open+unverifiable |
| T21 | F21 | 7/30일·만료·대상 변경 예외 | PASS(자체) | 기한 0일·31일 거부, 7일 예외→excepted, 만료 후 open 복귀. UI: 발견 사항 상세 |
| T22 | F22 | 0 finding+공백·1,000건 필터 | PARTIAL | '발견 0건/공백 있음→점검 필요' 표시. 1,000건 p95 시험 미실행 |
| T23 | F23 | 원문 없는 상세·근거 탐색 | PARTIAL | R03 상세에 '[제거됨: 평문 후보 …]·유효성 미확인' 표시. 두 번 이내 이동 검증은 사용자 확인 필요 |
| T24 | F24 | 알림 거절·반복·민감 경로 | PARTIAL | MonitoringTests.notificationDedupeAndQuietHours: 동일 사건 100회 억제·원천 건수 보존, 조용한 시간 기록만, 본문에 경로 없음. 실제 macOS 알림 전달·거부 상태 시험은 사용자 확인 필요 |
| T25 | F25 | 필터·미리보기·증빙 생성 | PASS(자체) | EvidenceTests.exportThenVerifyOK + 실기: 13파일 manifest 해시 일치(system unzip 대조), 원문 비밀·사용자명·실제 경로 없음 |
| T26 | F26 | 변조·누락·추가·ZIP 경로 공격 | PASS(자체) | tamperedMissingExtraAndPathAttacksFail: 변조·누락·추가·중복 경로·상위 이동·중복 JSON 키 실패, manifest 재작성은 기준 해시 있을 때만 검출 + 실기 tampered.zip 실패 |
| T27 | F27 | 서명 변조·구버전·schema 충돌 | PASS(자체) | HardeningTests.ruleUpdateSignatureAndCompatibility: 변조·다른 키·구버전·미지원 schema 거부, 원자적 전환·되돌리기. 배포 공개키는 개발용 자리표시자(릴리스 키로 교체 필요) |
| T28 | F28 | 보존 만료·초기화 | PARTIAL | Retention.apply: 7/30/90일, 기준점·최신 유지, cascade 삭제(시험 통과). 전체 초기화는 UI 구현, 실기 시험 미실행 |
| T29 | F29 | 종료·절전·동시 점검 | PARTIAL | 창 닫기 후 상주 유지(applicationShouldTerminateAfterLastWindowClosed=false), 절전/복귀·세션 비활성 훅 구현, 스캔 병합 큐. 실기 절전 시험 미실행 |
| T30 | F30 | 파서 실패 후 사용자 복구 | PARTIAL | 진단 파일 생성(버전·오류 코드·audit만, 홈 경로 제거) + canary 시험 통과. 파서 실패→coverage error→재시도 UI. 실기 사용자 복구 시험은 사용자 확인 필요 |
| T31 | N01 | 악성 입력·자원 상한 | PASS(자체) | HardeningTests.limitsOversizeDepthSymlinkAndCounts: 2MB 초과→oversize, 범위 밖 symlink→denied, 프로젝트 25개→상한 초과 5건 공백. canary 실행·네트워크 0 (코드상 호출 없음) |
| T32 | N02 | canary 전 저장면 검사 | PASS(자체) | HardeningTests.canaryAcrossAllStorageSurfaces: DB 바이트·증빙 ZIP·진단 텍스트·활동 사건·오류 문자열에서 canary 0 |
| T33 | N03 | 다른 계정·Keychain 실패 | PARTIAL | 0700/0600, Keychain 실패 시 약한 키 대체 없음(코드). 타 계정 시험 미실행 |
| T34 | N04 | 네트워크 차단 전체 여정 | NOT_RUN | 코드에 네트워크 호출 없음. 격리 네트워크 시험 미실행 |
| T35 | N05 | 기준 장비 20회 성능 | PARTIAL | PerfTests(LARM_PERF=1) 실측 2026-09-20, 이 Mac(macOS 26.6.2, Apple Silicon): 20프로젝트·약 1,900파일·50MCP 냉간 전체 점검 20회 p50 0.348s · p95 0.394s · max 0.442s (목표 60s), 시험 프로세스 RSS 118MB (목표 350MB). 변경 점검·취소 응답·유휴 CPU 15분 평균은 미측정 |
| T36 | N06 | 설치·공증·제거 | PARTIAL | install/uninstall(hook 항목 제거 포함)·make-dist.sh DMG 실기. Developer ID·공증 불가(유보). 연동 미선택 시 설정 바이트 보존(코드상 미접근) |
| T37 | N07 | 전원 중단·DB/업데이트 실패 | PARTIAL | WAL+트랜잭션. 강제 종료 시험 미실행 |
| T38 | N08 | 키보드·VoiceOver·확대 | NOT_RUN | M6 |
| T39 | N09 | 지원/미지원 버전 교차 | PARTIAL | docs/support-matrix.md 1개 OS 빌드. 2번째 빌드·미지원 키 unknown fixture 미작성 |
| T40 | N10 | 독립 challenge·추적성 | NOT_RUN | LG2 독립 검증자 몫. 현재 자체 시험 26개 통과 (./test.sh) |
| T41 | N11 | 시계 역행·타임존 변경 | PARTIAL | UTC ISO 8601 + tz 기록, 삭제·내보내기·예외 audit 기록. 시계 역행 fixture 미작성 |
| T42 | N12 | SBOM·릴리스 출처 검토 | PARTIAL | 외부 의존성 0 (Package.swift), 실행 플러그인·미서명 룰 없음. SBOM 문서 docs/sbom.md 작성, 릴리스별 보관 절차는 LG5 |
| T43 | F31 | 타입·동명 객체·근거 없는 간선 | PASS(자체) | graphRejectsInvalidEdgesAndKeepsSecretsOut (근거 없는 간선·타입 위반·다른 범위 연결 거부, 동명 MCP 미병합, 비밀 노드 값·지문 없음) |
| T44 | F32 | 전체/주변 탐색·대용량·키보드 | PARTIAL | GraphLayoutTests: 500노드/1000간선 배치 2초 미만(자동), 결정론·pin 존중. Canvas 첫 표시 p95·선택 200ms 실측은 기준 장비 UI 시험 필요. 200노드 상한·숨김 건수·표 전환 구현 |
| T45 | F33 | 노드/간선→근거→조치 | PARTIAL | 노드/간선 상세: 타입·관계 의미·출처(관측/도출)·근거 건수·발견 사항→근거·조치 열기(1~2회 이동). 사용자 UI 확인 필요 |
| T46 | F34 | 시점 diff·공백·레이아웃 보존 | PARTIAL | 변경 보기: 기준점 diff로 추가/삭제/수정/비교 불가 색·라벨, 비교 불가 점선. 고정 위치는 saved view·pins에 보존. 실기 확인 필요 |
| T47 | F35 | 저장 보기·빠른 재점검 | PARTIAL | 저장 보기 5개(필터·중심·깊이·pin) 설정 테이블 보존, ⌘F 검색, 이 범위 재점검(coverage 일치). 앱 재실행 복원 실기 확인 필요 |
| T48 | F36 | 처음 사용·오늘 할 일·조용한 시간 | PARTIAL | 첫 사용 안내·오늘 할 일 상위 3·조용한 시간·요약 알림 구현. 사용자 10명 목표는 LG4 |
| T49 | F37 | 자동 시작과 상주 서비스 | PARTIAL | SMAppService 로그인 항목 토글·상태 표시 구현. 재로그인·재부팅 10회 시험 미실행 (ad-hoc 서명 재설치 후 재등록 필요) |
| T50 | F38 | 설정 변화의 상시 감지 | PASS(자체) | MonitoringTests FSEvents 변경 수신 + 실기: 감시 프로젝트 settings.json 변경 → 2초 내 event 점검 → R02 high 생성. rename·부분 쓰기·권한 철회 fixture 미작성(PARTIAL 성격) |
| T51 | F39 | 지원 AI 활동 수집과 사건 기록 | PASS(자체) | ActivityTests: 양성(sudo/rm/curl|sh/민감경로)·음성(git status)·실패(미지원 schema 거절) fixture, 중복 재전송 카운트, 결과→요청 순서 역전 연결, PID+시작시각 process_ref. 결과 없음은 미확인 표시. 실기: 소켓 수신·spool 대체 확인 |
| T52 | F40 | 감시 건강 상태와 공백 | PARTIAL | 10초 건강 확인·last_alive 갱신 실기 확인, 미실행 구간→not_running 공백, 이벤트 유실 플래그→fs_overflow 공백+대조. kill·deadlock 주입 시험 미실행 |
| T53 | F41 | 기한 일시중지와 재개 | PARTIAL | 15분·1시간·수동 일시중지, 기한 만료 시 건강 확인→재개 실패면 공백 유지 (코드+PauseState 시험). 실기 UI 시험 사용자 확인 필요 |
| T54 | F42 | 지원 요청의 실행 전 확인 | N/A | 조건부 기능 미제공. 사유: 조건부 통제 미검증, 관측 모드로 제한 (요건 11.1, 사용자 결정 2026-09-20) |
| T55 | F43 | 등록 정책 집행과 결과 확인 | N/A | 조건부 기능 미제공. 사유 동일 |
| T56 | F44 | 활동 위험 규칙과 상태 구분 | PASS(자체) | activityRulesAndIngestLifecycle: 동일 입력 동일 판정, 정상·쉘·인코딩(unknown)·경로 변형(별칭)·범위 안/밖 분리. 문자열만으로 악성 확정 안 함 |
| T57 | N13 | 상주 안정성과 운영 비용 | NOT_RUN | 72시간 상주 시험 미실행. 변화 없는 대조는 저장 생략(DB 증가 억제) |
| T58 | N14 | 연동 설치와 권한 원복 | PARTIAL | hookInstallerCoexistsAndRemovesOnlyOwn: 기존 hook 공존, 사용자 변경값 보존, LARM 항목만 제거, 원자적 적용·동시 수정 거부. 실제 settings.json 등록은 사용자 확인 후(UI/--yes). 갱신·설치 실패 fixture 미작성 |
| T59 | N15 | 조건부 통제의 무결성 | N/A | 조건부 기능 미제공. 사유 동일 |

집계: N/A 3, NOT_RUN 4, PARTIAL 31, PASS(자체) 21
