#!/bin/bash
# LARM 빌드 + 설치 스크립트 (macOS 전용). FlashFind의 install.sh를 승계한다.
# 하는 일: swift build -c release 후 LARM.app 번들(주 실행파일 + larm-hook + larm-verify + 리소스 번들)을 만들어
# /Applications(권한 없으면 ~/Applications)에 넣고 ad-hoc 서명 후 실행한다. 네트워크·sudo 없음.
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname)" != "Darwin" ]]; then echo "macOS에서 실행하세요." >&2; exit 1; fi
if ! command -v swift >/dev/null 2>&1; then
  echo "Swift 컴파일러가 없습니다: xcode-select --install" >&2; exit 1
fi

# 저장소가 ~/Documents 아래면 SwiftPM 빌드 DB가 disk I/O error를 내므로 TMPDIR에 빌드한다.
SCRATCH="${LARM_SCRATCH:-${TMPDIR:-/tmp}/larm-build}"
echo "==> LARM 빌드 중 (swift build -c release, scratch: $SCRATCH)"
swift build -c release --scratch-path "$SCRATCH" --product LARM
swift build -c release --scratch-path "$SCRATCH" --product larm-hook
swift build -c release --scratch-path "$SCRATCH" --product larm-verify

BIN_DIR="$SCRATCH/release"
for b in LARM larm-hook larm-verify; do
  [[ -f "$BIN_DIR/$b" ]] || { echo "빌드 결과물이 없습니다: $BIN_DIR/$b" >&2; exit 1; }
done
RES_BUNDLE="$BIN_DIR/LARM_LARMCore.bundle"
[[ -d "$RES_BUNDLE" ]] || { echo "리소스 번들이 없습니다: $RES_BUNDLE" >&2; exit 1; }

DEST_DIR="/Applications"
if [[ ! -w "$DEST_DIR" ]]; then DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; fi
APP="$DEST_DIR/LARM.app"

# 실행 중이면 종료 (상주 프로세스)
if pgrep -x LARM >/dev/null 2>&1; then
  echo "==> 실행 중인 LARM 종료"
  osascript -e 'tell application "LARM" to quit' >/dev/null 2>&1 || pkill -x LARM || true
  sleep 1
fi

echo "==> 앱 번들 생성: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LARM" "$APP/Contents/MacOS/LARM"
cp "$BIN_DIR/larm-hook" "$APP/Contents/MacOS/larm-hook"
cp "$BIN_DIR/larm-verify" "$APP/Contents/MacOS/larm-verify"
cp -R "$RES_BUNDLE" "$APP/Contents/Resources/LARM_LARMCore.bundle"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Fonts" && cp assets/fonts/*.otf assets/fonts/LICENSE-Pretendard.txt "$APP/Contents/Resources/Fonts/"

if [[ -f assets/icon.png ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  echo "==> 앱 아이콘 생성"
  ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" assets/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2)); sips -z "$d" "$d" assets/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# 설치 증빙: 번들 파일 해시 (N06 로컬 범위)
mkdir -p dist
( cd "$APP" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 ) > "dist/LARM-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)-installed.sha256"

echo "==> 설치 완료: $APP"
echo "    설치 해시: dist/*.sha256"
[[ "${LARM_NO_OPEN:-0}" == "1" ]] || open "$APP"
