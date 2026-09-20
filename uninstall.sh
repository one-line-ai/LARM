#!/bin/bash
# LARM 제거. LARM 소유 항목만 제거한다 (N14). 사용자가 내보낸 증빙 파일은 건드리지 않는다.
# 옵션: --purge  앱 데이터(DB·spool)와 Keychain 키까지 삭제 (F28 전체 초기화).
set -euo pipefail
PURGE=0; [[ "${1:-}" == "--purge" ]] && PURGE=1

# LARM 소유 hook 항목 제거 (앱이 아직 있을 때 실행)
for d in /Applications "$HOME/Applications"; do
  if [[ -x "$d/LARM.app/Contents/MacOS/LARM" ]]; then
    "$d/LARM.app/Contents/MacOS/LARM" --uninstall-hook --yes >/dev/null 2>&1 && echo "Claude Code hook의 LARM 항목을 제거했습니다." || true
    break
  fi
done
if pgrep -x LARM >/dev/null 2>&1; then
  osascript -e 'tell application "LARM" to quit' >/dev/null 2>&1 || pkill -x LARM || true
  sleep 1
fi
for d in /Applications "$HOME/Applications"; do
  [[ -d "$d/LARM.app" ]] && { rm -rf "$d/LARM.app"; echo "제거: $d/LARM.app"; }
done
if [[ $PURGE == 1 ]]; then
  rm -rf "$HOME/Library/Application Support/LARM"
  security delete-generic-password -s com.onelineai.larm -a install-hmac-key >/dev/null 2>&1 || true
  echo "앱 데이터와 Keychain 키를 삭제했습니다. SSD·백업·클라우드 사본의 물리적 삭제는 보장하지 않습니다."
else
  echo "앱 데이터는 남겨 두었습니다: ~/Library/Application Support/LARM (삭제하려면 --purge)"
fi
rm -f "$HOME/Library/Application Support/LARM/hook.sock" 2>/dev/null || true
