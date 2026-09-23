#!/bin/bash
# LARM 배포용 DMG 생성 (FlashFind make-dist.sh 승계). arm64 + x86_64 유니버설 시도, 실패 시 arm64 전용.
# ad-hoc 서명이며 Developer ID 공증은 아니다 (N06은 LG5 항목). 배포 파일 해시를 dist/SHA256SUMS 에 남긴다.
set -euo pipefail
cd "$(dirname "$0")"
SCRATCH="${LARM_SCRATCH:-${TMPDIR:-/tmp}/larm-build-dist}"
VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
STAGE="$(mktemp -d)"; APP="$STAGE/LARM.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist

build_arch() { for p in LARM larm-hook larm-verify; do swift build -c release --scratch-path "$SCRATCH-$1" --triple "$1-apple-macosx13.0" --product "$p" >/dev/null || return 1; done; }
bin_dir() { swift build -c release --scratch-path "$SCRATCH-$1" --triple "$1-apple-macosx13.0" --show-bin-path; }
echo "==> arm64 빌드"; build_arch arm64; ARM_BIN="$(bin_dir arm64)"
UNIVERSAL=1
echo "==> x86_64 빌드 (실패 시 arm64 전용)"; build_arch x86_64 && X86_BIN="$(bin_dir x86_64)" || UNIVERSAL=0
for b in LARM larm-hook larm-verify; do
  if [[ $UNIVERSAL == 1 ]]; then lipo -create "$ARM_BIN/$b" "$X86_BIN/$b" -output "$APP/Contents/MacOS/$b"
  else cp "$ARM_BIN/$b" "$APP/Contents/MacOS/$b"; fi
done
cp -R "$ARM_BIN/LARM_LARMCore.bundle" "$APP/Contents/Resources/LARM_LARMCore.bundle"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Fonts" && cp assets/fonts/*.otf assets/fonts/LICENSE-Pretendard.txt "$APP/Contents/Resources/Fonts/"
if [[ -f assets/icon.png ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do sips -z "$s" "$s" assets/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null; d=$((s*2)); sips -z "$d" "$d" assets/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null; done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/설치 방법.txt" <<TXT
LARM $VER (ad-hoc 서명, 공증 없음)
1. LARM.app 을 Applications 폴더로 끌어 넣습니다.
2. 처음 열 때 "확인되지 않은 개발자" 경고가 나오면 터미널에서:
   xattr -dr com.apple.quarantine /Applications/LARM.app
3. 첫 실행 시 Keychain 접근 허용을 묻습니다 (설치별 비밀정보 지문 키). 허용해야 점검·감시가 시작됩니다.
4. 제거: 앱을 휴지통으로 옮기고, 필요하면 ~/Library/Application Support/LARM 을 삭제합니다.
   Claude Code hook 을 등록했다면 앱의 'AI 활동' 화면에서 먼저 제거하세요.
배포 파일 해시: dist/SHA256SUMS
TXT
DMG="dist/LARM-$VER.dmg"; rm -f "$DMG"
hdiutil create -volname "LARM $VER" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
( cd dist && shasum -a 256 "LARM-$VER.dmg" > SHA256SUMS )
echo "==> $DMG ($([[ $UNIVERSAL == 1 ]] && echo universal || echo arm64))"; cat dist/SHA256SUMS
