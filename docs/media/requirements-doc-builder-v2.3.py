# v2.3 빌더: v2.2 결과(build.py 산출) 위에 (1) 게임이론 장 (2) 요건별 화면 (3) 윤문 을 적용한다.
import copy, re, os, sys
from docx import Document
from docx.shared import Emu, Inches, Pt
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
from docx.text.paragraph import Paragraph

DATE='2026-09-27'; VER='0.7.0'
SHOTS='/private/tmp/claude-501/-Users-f1-Documents-AIops/81aa2374-4948-4307-849a-adb3553e90c5/scratchpad/shots/'
d=Document('LARM_업무요건정의서_v2.2_SLC_현행화.docx')

def find_para(startswith, style=None):
    for p in d.paragraphs:
        if p.text.startswith(startswith) and (style is None or p.style.name==style): return p
    raise KeyError(startswith)
def para_after(p):
    n=p._p.getnext(); return Paragraph(n,p._parent if p._parent is not None else d._body) if n is not None and n.tag==qn('w:p') else None
def clone_para_after(anchor, text, bold_prefix=None, style_from=None):
    new=copy.deepcopy((style_from or anchor)._p)
    for r in new.findall(qn('w:r')): new.remove(r)
    for h in new.findall(qn('w:hyperlink')): new.remove(h)
    anchor._p.addnext(new); p=Paragraph(new, anchor._parent if anchor._parent is not None else d._body)
    if bold_prefix: r=p.add_run(bold_prefix); r.bold=True
    if text: p.add_run(text)
    return p
TEMPLATE=[t for t in d.tables if t.rows[0].cells[0].text.strip().startswith('시험')][0]
def new_table_after(para, header, rows, widths):
    t=d.add_table(rows=1+len(rows), cols=len(header))
    t._tbl.remove(t._tbl.tblPr); t._tbl.insert(0, copy.deepcopy(TEMPLATE._tbl.tblPr))
    grid=t._tbl.find(qn('w:tblGrid'))
    for gc,w in zip(grid.findall(qn('w:gridCol')),widths): gc.set(qn('w:w'),str(w))
    tw=t._tbl.tblPr.find(qn('w:tblW')); tw.set(qn('w:w'),str(sum(widths))); tw.set(qn('w:type'),'dxa')
    hdr=TEMPLATE.rows[0].cells[0]._tc; body=TEMPLATE.rows[1].cells[0]._tc
    for ri,row in enumerate([header]+rows):
        if ri==0: t.rows[0]._tr.get_or_add_trPr().append(OxmlElement('w:tblHeader'))
        for ci,val in enumerate(row):
            c=t.rows[ri].cells[ci]; src=hdr if ri==0 else body
            old=c._tc.find(qn('w:tcPr'));
            if old is not None: c._tc.remove(old)
            tcPr=copy.deepcopy(src.find(qn('w:tcPr'))); c._tc.insert(0,tcPr); tcPr.find(qn('w:tcW')).set(qn('w:w'),str(widths[ci]))
            p=c.paragraphs[0]; sp=src.find(qn('w:p')); spPr=sp.find(qn('w:pPr'))
            if spPr is not None:
                op=p._p.find(qn('w:pPr'))
                if op is not None: p._p.remove(op)
                p._p.insert(0,copy.deepcopy(spPr))
            r=p.add_run(val)
            if ri==0:
                sr=sp.find(qn('w:r'))
                if sr is not None and sr.find(qn('w:rPr')) is not None: r._r.insert(0,copy.deepcopy(sr.find(qn('w:rPr'))))
    para._p.addnext(t._tbl); return t
CAPTION_STYLE=None
def add_figure(anchor, img, caption, width_in=5.6):
    """anchor 뒤에 그림 + 캡션 문단."""
    if not os.path.exists(img): return anchor
    p=clone_para_after(anchor, None); r=p.add_run(); r.add_picture(img, width=Inches(width_in))
    p.alignment=1
    c=clone_para_after(p, caption); c.alignment=1
    for r in c.runs: r.font.size=Pt(9); r.italic=False
    return c

# =============== 1. 게임이론 장 (5장 끝 '요건 밖 추가 구현 항목' 앞에 삽입) ===============
h6=find_para('5 요건 밖 추가 구현 항목','Heading 1')
prev=Paragraph(h6._p.getprevious(), h6._parent)
H=lambda a,t: clone_para_after(a, t, style_from=h6)
H2=lambda a,t: clone_para_after(a, t, style_from=find_para('요약','Heading 2'))
P=lambda a,t,b=None: clone_para_after(a, t, bold_prefix=b, style_from=find_para('아래 수치는 개발 목표이며'))

a=H(prev,'5 게임이론 결정 층: 개념, 적용, 요건 연계 (0.7.0)')
a=P(a,'이 장은 0.7.0에 들어간 게임이론 결정 층을 처음 보는 사람도 따라갈 수 있게 설명한다. 순서는 "게임이론이 무엇인가 → LARM의 상황을 왜 게임으로 보는가 → 다섯 게임과 일곱 전략 → 각 전략이 어느 요건에 어떻게 붙는가 → 무엇을 바꾸지 않는가"이다. 상세 설계는 docs/game-jev-design.html(10장), 적용 현황은 docs/game-jev-applied.html에 있다.')
a=H2(a,'5.1 게임이론이 무엇인가')
a=P(a,'게임이론은 목표가 서로 다른 둘 이상이 상대의 선택을 보고 자기 선택을 정하는 상황을 다루는 도구다. 체스나 도박만이 아니라 "내가 이렇게 하면 상대는 어떻게 할까"가 있는 모든 상황이 게임이다. 게임을 기술하려면 플레이어, 각 플레이어가 고를 수 있는 선택, 선택의 조합마다 각자가 얻는 보수(payoff), 그리고 누가 무엇을 아는가(정보)를 정한다. 그 위에서 "상대가 합리적으로 움직인다면 나는 무엇을 해야 하는가"를 따진 결과가 전략이고, 누구도 혼자 선택을 바꿔서 더 나아질 수 없는 상태가 균형이다.')
t=new_table_after(a, ['개념','쉬운 뜻','LARM에서의 모습','연결 전략 / 요건'], [
 ['플레이어와 보수','선택하는 주체와, 선택 조합마다 얻는 이득·손해','사용자(일은 끝내되 위험은 줄이고 싶음)와 AI 도구(일을 빨리 끝내려 넓은 권한과 지름길을 택함). LARM은 플레이어가 아니라 심판','모든 게임의 출발점 · 3.1 역할'],
 ['정보 비대칭','한쪽만 아는 것이 있음','사용자는 AI 도구가 정상인지 조종당했는지 볼 수 없고 행동만 본다','게임 2 · F39, F44'],
 ['주인·대리인 문제','일을 맡긴 쪽(주인)과 맡은 쪽(대리인)의 목표가 달라 대리인이 편한 쪽을 택함(도덕적 해이)','사용자가 허용 범위를 넓게 주면 AI 도구는 그 범위를 끝까지 쓴다','게임 1 · F08, F19'],
 ['반복 게임과 팃포탯','같은 상대를 여러 번 만나면 지난 행동을 기억해 다음 선택에 반영할 수 있음','세션이 끝나도 프로젝트별 이력이 남아야 "지난번에 어겼으면 이번엔 더 본다"가 가능','게임 3 · F16, F18'],
 ['혼합 전략','상대가 내 행동을 예측하지 못하게 무작위를 섞음','검사 시각이 예측되면 그 사이에 설정을 바꿀 수 있으므로 대조 간격에 무작위를 섞는다','게임 4 · F29, F38'],
 ['균형과 늑대소년','알림이 잦으면 무시하는 것이 최선이 되는 나쁜 균형에 빠짐','알림 하나의 가치가 낮으면 보내지 않아야 알림의 무게가 유지된다','게임 5 · F24, F36'],
 ['약속 장치','미리 손을 묶어 나중의 유혹을 막는 장치','예외 기한과 반복 안내(사용자), 훅 등록으로 "기록된다"는 사실 전달(AI 도구)','G5 · F21, F39'],
 ['보정된 확률','"70%"라고 말한 일이 실제로 10번 중 7번 일어나는 확률','대조 간격·알림 게이트·정렬이 쓰는 입력. 지금은 규칙 기반 추정, 나중에 Jev','G7 · N10, N11'],
], [1500,2400,3900,2424])
a=Paragraph(t._tbl.getnext(), a._parent) if t._tbl.getnext() is not None and t._tbl.getnext().tag==qn('w:p') else a
a=P(t._tbl.getnext() and Paragraph(t._tbl.getnext(),None) or a,'') if False else a
# 표 다음에 문단을 넣기 위한 앵커: 표 뒤에 빈 문단이 없으면 만든다
def after_table(t):
    n=t._tbl.getnext()
    if n is None or n.tag!=qn('w:p'):
        np=copy.deepcopy(find_para('아래 수치는 개발 목표이며')._p)
        for r in np.findall(qn('w:r')): np.remove(r)
        t._tbl.addnext(np); n=np
    return Paragraph(n, d._body)
a=after_table(t)
a=H2(a,'5.2 LARM의 상황을 왜 게임으로 보는가')
a=P(a,'규칙(R01~R08, RR01~RR02)은 "이 설정은 위험하다"를 판정한다. 그러나 언제 다시 볼지, 무엇을 먼저 알릴지, 얼마나 두고 볼지는 상대의 행동에 달려 있다. AI 도구는 악의가 없어도 넓은 권한을 원하고, 주입된 지시에 조종당하면 목표가 바뀐다. 사용자는 확인 요청이 귀찮으면 "전부 허용"으로 기울고, 알림이 잦으면 무시한다. 이 두 성향이 맞물리는 지점이 규칙이 아니라 전략의 문제이고, 게임이론이 다루는 영역이다.')
a=P(a,'LARM은 플레이어가 아니라 심판이다. 무엇을 기록하고, 무엇을 보여 주고, 어떤 기본값을 둘지 정해 두 플레이어가 받는 정보와 보수를 바꾼다. 막지 않는 관측 모드 안에서도 행동을 바꿀 수 있는 이유가 여기 있다. 조종당한 AI 도구는 별도 플레이어가 아니라 AI 도구의 한 "유형"으로 다루며, 유형을 겉으로 구별할 수 없다는 사실이 게임 2의 출발점이다.')
a=H2(a,'5.3 다섯 게임과 일곱 전략')
t=new_table_after(a, ['게임','사용자의 선택','AI 도구의 선택','문제','LARM(심판)의 개입','전략'], [
 ['1 권한 위임','허용 범위를 넓힐지 좁힐지','주어진 범위를 끝까지 씀','도덕적 해이: 넓은 허용이 관례로 누적','넓은 규칙마다 "좁히면 늘어날 확인 요청"을 실제 활동 기록으로 계산해 보여 줌. 좁힐지는 사용자','게임 1 계산'],
 ['2 신호 읽기','계속 맡길지, 살펴볼지','행동 자체가 신호','유형을 겉으로 구별 못 함','숨김·우회형 명령, 높은 위험 판정, 민감 경로, 범위 밖 접근 수로 세션 점수를 매겨 살펴볼 순서를 제시. 판정은 사람','G4'],
 ['3 기억 있는 신뢰','프로젝트마다 얼마나 믿을지','안전한 변경만 할지, 위험한 변경을 할지','기억이 없으면 어긴 뒤에도 같은 신뢰','범위별 30일 이력(새 발견·반복·미조치 높음)으로 안정/주의/살펴볼 필요 표시, 기준 상태 저장 권장','G3'],
 ['4 검사','언제 다시 확인할지','언제 설정을 바꿀지','확인 시점이 예측되면 그 사이가 틈','대조 간격을 변경 확률로 정하고 무작위 곱을 섞음. 작업 중 촘촘히, 유휴에 드물게','G1'],
 ['5 주의 배분','알림에 반응할지 무시할지','사건을 얼마든지 만듦','주의는 유한, 사건은 무한','알림 가치가 낮으면 배지로만, 높은 위험은 항상. 오늘 항목을 조치 필요 순으로 정렬','G2, G6'],
 ['약속 장치','예외를 얼마나 둘지','기록됨을 알고 행동','승인 피로, 되풀이 예외','예외 반복 안내와 7일 권장, 훅 등록 사실 전달','G5'],
 ['검증','추정을 믿을지','해당 없음','근거 없는 확률은 감','추정과 나중 결과를 저장해 브라이어 점수로 검증','G7'],
], [1150,1500,1500,1700,2874,1500])
a=after_table(t)
a=H2(a,'5.4 전략별 계산과 요건 연계')
a=P(a,'아래 표는 전략마다 입력, 계산, 제품에서 바뀌는 것, 연계 요건, 시험을 적는다. 확률(p)은 규칙 기반 추정(rule-1)이 내며 그 근거 문장이 화면에 함께 표시된다. Jev가 연결되면 같은 자리에 보정된 확률이 들어가고 계산은 바뀌지 않는다.')
t=new_table_after(a, ['전략','입력','계산','제품에서 바뀌는 것','연계 요건','시험'], [
 ['G1 무작위 대조 간격','최근 15분 활동 수, 마지막 변경 경과','p = 0.70(활동 있음) / 0.45(60분 내 변경) / 0.12. interval = clamp(30분 / (1 + 2.5p), 10분, 60분) × U(0.7, 1.3)','F29의 30분 고정 대조가 작업 중 10~15분, 유휴 30~60분 무작위로. 개요·한눈에 보기에 다음 대조 시각과 근거','F29, F38, F40','DecisionTests.inspectionInterval'],
 ['G2 알림 가치 게이트','발견 위험도·재탐지 수(a), 조용한 시간·30일 반응률(b)','V = a · b · L − 0.1. V > 0.25면 전송, 아니면 배지. 높은 위험·감시 장애는 게이트 없음','F24의 중간 위험·감시 공백 알림 수 감소. 알림 후 24시간 내 앱 열기를 반응률로 기록','F24, F36, F40','DecisionTests.alertGate'],
 ['G3 기준 상태 권장','미조치 높음 수, 기준 유무·나이, 바뀐 설정 수','높음 0이고 (기준 없음 또는 7일 넘게 변화 유지)면 권장','F16 기준 지정이 "언제 해야 하는지" 안내와 버튼으로','F16, F15','DecisionTests.baselineSuggestion'],
 ['G4 회피 신호 우선','세션별 표시(flag) 수','p = 0.05 + 0.2·숨김우회(≤3) + 0.15·높음(≤2) + 0.05·민감경로(≤3) + 0.03·범위밖(≤5)','F44 판정을 세션 단위 순서로 묶어 "먼저 살펴볼 세션" 제시. 살펴봄 결과가 Q4 실제값','F39, F44','DecisionTests.sessionSignals'],
 ['G5 예외 반복 안내','같은 발견 사항의 예외 결정 수','2회 이상이면 경고와 7일·사유 권장','F21 예외 화면에 안내 문구. 기본 기한 자동 축소는 미구현','F21','수동 확인'],
 ['G6 오늘 항목 정렬','위험도, 재점검 확인 여부, 재탐지 수, 최초 시각','위험도 → 확인됨 → 재탐지 많음 → 오래됨','F36 오늘 할 일 상위 3과 "확인하면 알 수 있는 것"','F36, F22','수동 확인'],
 ['G7 추정 기록·검증','모든 추정과 나중 결과','브라이어 = 평균 (p − 결과)²(표본 5건부터)','"사용자와 AI 도구" 하단에 질문별 점수. 0.25 초과 시 자동 끄기는 미구현','N10, N11','DecisionTests.brier'],
 ['게임 1 위임 계산','R02 breadth, 최근 30일 요청·세션 수','좁혔을 때 덮였을 요청 수 ÷ 세션 수. 2회 이내면 권장','F08 상세와 "사용자와 AI 도구"에 세션당 확인 횟수','F08, F19','DecisionTests.delegation'],
], [1300,1650,2450,2300,1000,1524])
a=after_table(t)
a=H2(a,'5.5 무엇을 바꾸지 않는가')
a=P(a,'결정 층은 위험 판정(R01~R08, RR01~RR02)과 그 심각도를 바꾸지 않는다. 허용·차단 결정(F42·F43)을 하지 않는다. 설정 파일을 고치지 않는다. 증빙 보고서(F25)에는 판정과 근거만 들어가고 추정값은 들어가지 않는다. 추정값은 항상 "참고"로 표시되고 근거 문장이 붙으며, 표본이 모이면 브라이어 점수로 맞았는지 검증된다. 추정이 나빠지거나 Jev가 없으면 규칙만으로 후퇴한다. 이 원칙은 4.3 신뢰 경계와 11.1 출시 차단 결함을 그대로 따른다.')
add_figure(a, SHOTS+'games.png', '그림 5-1. "사용자와 AI 도구" 화면. 다섯 게임과 전략별 계산 결과, 결정 근거와 검증 점수를 한 곳에 모아 보여 준다.')

# =============== 2. 요건별 화면 ===============
IMG={
 'F01':('overview.png','개요 화면. 감시 상태, 다음 대조 시각, 위험 타일, 마지막 점검, 자동 감시 상태, 지원 도구'),
 'F02':('overview.png','개요 화면의 지원 도구·점검 대상 폴더 상자 (프로젝트 추가·제외·삭제)'),
 'F03':('overview.png','개요 화면의 지원 도구 상자 (설치·설정 잔존·미설치, 버전)'),
 'F04':('finding-detail.png','발견 사항 상세의 "확인한 값"에 출처(위치 별칭·우선순위·해석·읽기 모듈)가 붙는다'),
 'F05':('graph-2d.png','2D 지도에서 외부 도구 연결(MCP)과 주소 노드'),
 'F06':('finding-detail.png','R01 상세: approval_mode never와 sandbox danger-full-access 교차 판정'),
 'F07':('finding-detail.png','R01 상세의 확인한 값과 한계 문장'),
 'F08':('findings.png','발견 사항 목록: R02 광범위 도구 허용(Bash(*), allowedTools)'),
 'F09':('findings.png','발견 사항 목록의 R06 연결 주소 확인 필요 항목 (상세에서 host·scheme·port 검토 기록)'),
 'F10':('findings.png','R03 평문 비밀정보 후보: 원문 대신 "[제거됨: 평문 후보, 길이 n]"로 표시'),
 'F11':('findings.png','R04 민감 파일 접근 범위: posix_mode 0644 등 권한 관측값'),
 'F12':('changes.png','프로젝트 추가 뒤 관측값(hook·지시 파일은 digest만). 코드 실행 없음'),
 'F13':('overview.png','개요의 마지막 점검 상자: 상태(완료/부분/실패/취소)·확인한 값·확인 못 한 구간'),
 'F14':('changes.png','바뀐 설정: 비밀값 후보는 "[제거됨]"과 "비밀값 변경(원문 미표시)"로만 비교'),
 'F15':('changes.png','바뀐 설정 화면: 추가·삭제·수정·비교 불가 필터와 이전/이후 값'),
 'F16':('changes.png','바뀐 설정 상단의 기준 상태 상자와 "마지막 점검을 기준 상태로 지정"'),
 'F17':('findings.png','같은 입력에 같은 판정: 재탐지 4회 카운트가 같은 카드에 누적'),
 'F18':('finding-detail.png','상태 배지(미조치)와 최초/최근·재탐지 횟수, 이력'),
 'F19':('finding-detail.png','상세의 "다음 단계"와 "수동 조치 안내"'),
 'F20':('finding-detail.png','재점검 결과에 따라 해결·확인 못 함·범위 제거됨으로 갈리는 상세'),
 'F21':('finding-detail.png','상세의 "예외와 검토" 상자 (기한 7·14·30일, 사유 필수, 반복 안내)'),
 'F22':('graph.png','한눈에 보기: 캐릭터 상태, 숫자 타일, 오늘 확인할 항목, 갤럭시 지도'),
 'F23':('finding-detail.png','상세: 확인한 값·출처·한계·다음 단계·수동 조치 안내·이력'),
 'F24':('evidence.png','보고서와 설정의 알림 상자 (macOS 알림, 조용한 시간)와 메뉴바 상태'),
 'F25':('evidence.png','보고서 내보내기: 미리보기(범위·건수·파일 목록)와 ZIP 내보내기'),
 'F26':('cli-verify.png','larm-verify 오프라인 검증 출력'),
 'F27':('evidence.png','보고서와 설정의 점검 규칙 갱신 (서명 패키지 적용)'),
 'F28':('evidence.png','보존과 삭제: 보존 기간, 만료 기록 정리, 전체 초기화'),
 'F29':('overview.png','자동 감시 상자: 폴더 감시·60초 폴링·주기 대조·다음 대조 시각'),
 'F30':('overview.png','개요 하단 용어 안내와 상태 복구 문구, 캐릭터 말풍선'),
 'F31':('graph-2d.png','2D 지도: 타입별 범례와 실선(확인)/점선(추론) 관계'),
 'F32':('galaxy-focus.png','갤럭시 지도에서 별을 눌러 이웃을 밝힌 상태와 상세 패널'),
 'F33':('galaxy-focus.png','갤럭시 상세 패널의 연결된 별 목록과 "발견 사항 열기"'),
 'F34':('graph-2d.png','2D 지도의 변경 보기(추가·수정 라벨)'),
 'F35':('graph-2d.png','2D 지도의 저장 보기·검색·필터'),
 'F36':('graph.png','한눈에 보기의 오늘 확인할 항목 (조치 필요 추정 순)'),
 'F37':('menubar.png','메뉴바 메뉴: 캐릭터 상태, 감시 상태, 지금 점검, 잠시 멈춤, 감시 종료'),
 'F38':('overview.png','자동 감시 상자: 설정 폴더 감시와 루트 파일 60초 폴링'),
 'F39':('activity.png','AI 도구 활동: 연동 상태와 활동 기록(종류·대상 별칭·판단·처리)'),
 'F40':('overview.png','자동 감시 상자의 확인 못 한 구간(활동 연동 끊김)과 복구 안내'),
 'F41':('menubar.png','메뉴바의 감시 잠시 멈춤(15분·1시간·수동)'),
 'F42':(None,None),'F43':(None,None),
 'F44':('activity.png','활동 기록의 RR01 high·RR01 medium·RR02 보류 판정'),
 'N01':('cli-tests.png','자체 시험 실행 결과 (상한·symlink·canary 포함 40건)'),
 'N02':('changes.png','비밀값은 저장면 어디에도 원문이 없고 "[제거됨]"만 남는다'),
 'N03':('evidence.png','설치 키(Keychain)·전체 초기화 안내'),
 'N04':('cli-status.png','LARM --status 헤드리스 출력 (네트워크 호출 없음)'),
 'N05':('cli-tests.png','자체 시험 결과(PerfTests는 LARM_PERF=1로 별도 실행)'),
 'N06':('evidence.png','로그인 시 자동 시작 토글과 서명 안내'),
 'N07':('overview.png','마지막 점검 상태와 부분 결과 표시'),
 'N08':('games.png','한국어 쉬운 말·명사형 문구, Pretendard, 색 외 농도·굵기·텍스트로 구분'),
 'N09':('overview.png','지원 도구 상자: 지원/제한 지원/미지원 표시'),
 'N10':('cli-tests.png','자체 시험 40건 통과 (독립 검증 아님)'),
 'N11':('finding-detail.png','상세 이력의 UTC 기반 시각과 사용자·엔진 기록'),
 'N12':(None,None),
 'N13':('overview.png','자동 감시 상자: 변화 없는 대조는 저장 생략'),
 'N14':('hook-plan.png','Claude Code 연결 등록: 변경 전후 diff 확인 시트'),
 'N15':(None,None),
}
cnt=0
for p in list(d.paragraphs):
    m=re.match(r'LARM-(F\d\d|N\d\d)\s', p.text)
    if m and p.style.name=='Heading 2':
        rid=m.group(1); q=para_after(p); last=None
        while q is not None and q.style.name=='Normal' and q.text.strip():
            last=q; q=para_after(q)
        img,cap=IMG.get(rid,(None,None))
        if img:
            add_figure(last, SHOTS+img, f'그림 {rid}. {cap}', width_in=5.4); cnt+=1
print('figures',cnt)
# 3.4 화면 전체 갤러리
p34=[p for p in d.paragraphs if '실제 사이드바는 네 묶음' in p.text][0]
c=add_figure(p34, SHOTS+'graph.png','그림 3-1. 한눈에 보기 (첫 화면)')
c=add_figure(c, SHOTS+'galaxy-focus.png','그림 3-2. 갤럭시 지도에서 별을 선택한 상태')
c=add_figure(c, SHOTS+'findings.png','그림 3-3. 발견 사항 목록')
c=add_figure(c, SHOTS+'activity.png','그림 3-4. AI 도구 활동')
c=add_figure(c, SHOTS+'menubar.png','그림 3-5. 메뉴바 메뉴', width_in=3.6)

# =============== 3. 윤문 ===============
# (a) 제목 번호 체계 통일, (b) 긴 줄표 제거, (c) 어색한 표현
title_fix={
 '5 기능 요건 37부터 40까지':'5. 기능 요건 (37~40/44)','5 기능 요건 41부터 44까지':'5. 기능 요건 (41~44/44)',
 '6 비기능 요건 13부터 15까지':'6. 비기능 요건 (13~15/15)','7 활동 위험 룰과 감시 상태':'7. 활동 위험 룰과 감시 상태 (RR01~RR02)',
 '10 수용 시험 49부터 54까지':'10. 수용 시험 (49~54/59)','10 수용 시험 55부터 59까지':'10. 수용 시험 (55~59/59)',
 '5 요건 밖 추가 구현 항목 (0.7.0)':'5. 요건 밖 추가 구현 항목 (0.7.0)','5 게임이론 결정 층: 개념, 적용, 요건 연계 (0.7.0)':'5. 게임이론 결정 층: 개념, 적용, 요건 연계 (0.7.0)',
}
phr={
 '시험 상태 NOT_RUN.':'시험 상태: NOT_RUN.','–':'~','—':', ','−':'-',
 '지원 활동':'지원되는 도구 활동','상시 관측':'상시 감시','재점검 해소':'재점검으로 해소','허위 정상':'거짓 정상','허위 차단':'거짓 차단','허위 완료':'거짓 완료',
 '수용 기준  ':'수용 기준: ','담당 ':'담당: ',
}
def fix_runs(p):
    for r in p.runs:
        t=r.text; o=t
        for a_,b_ in phr.items(): t=t.replace(a_,b_)
        if t!=o: r.text=t
    if p.style.name=='Heading 1' and p.text in title_fix:
        p.runs[0].text=title_fix[p.text]
        for r in p.runs[1:]: r.text=''
n=0
for p in d.paragraphs: fix_runs(p)
for t in d.tables:
    for row in t.rows:
        for c in row.cells:
            for p in c.paragraphs: fix_runs(p)
# 목차 항목 갱신
for p in d.paragraphs:
    if p.text=='5 요건 밖 추가 구현 항목 (0.7.0)' and p.style.name=='Normal': p.runs[-1].text='5. 요건 밖 추가 구현 항목 (0.7.0)'
toc5=find_para('5. 기능 요건')
if toc5.style.name=='Normal': clone_para_after(toc5,'5. 게임이론 결정 층: 개념, 적용, 요건 연계 (0.7.0)')
# 부제·바닥글
sub=find_para('Local Agent Risk Monitor SLC 출시 요건')
sub.runs[0].text='Local Agent Risk Monitor SLC 출시 요건 · v2.3 구현 현황·화면·게임이론 반영'
for r in d.sections[0].footer.paragraphs[0].runs:
    if 'v2.2' in r.text: r.text=r.text.replace('v2.2','v2.3')
# 개정 이력 문단 보강
h=find_para('개정 이력과 구현 현황 요약 (v2.2)','Heading 2'); h.runs[0].text='개정 이력과 구현 현황 요약 (v2.3)'
pp=para_after(h)
clone_para_after(pp, f'v2.3({DATE})는 v2.2에 세 가지를 더했다. ① 5장 앞에 게임이론 결정 층 장을 신설해 개념부터 전략별 계산과 요건 연계까지 설명한다. ② 요건마다 실제 앱 화면(0.7.0, fixture 데이터로 격리 실행한 캡처)을 붙였다. ③ 제목 번호 체계와 표현을 통일하는 윤문(긴 줄표 제거, "허위"→"거짓", "수용 기준"·"담당" 표기 통일, 조건부 항목 표기)을 했다. 화면의 경로·이름은 시험용 fixture(shop-api, data-pipeline)이며 실제 사용자 데이터가 아니다.', bold_prefix='v2.3 변경  ')
d.save('LARM_업무요건정의서_v2.3_SLC_현행화.docx'); print('saved v2.3')
