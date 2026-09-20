#!/bin/bash
# swift test 래퍼. Xcode 없이 Command Line Tools만 있는 환경에서는 Testing.framework 경로를 직접 지정해야 한다.
set -euo pipefail
cd "$(dirname "$0")"
SCRATCH="${LARM_SCRATCH:-${TMPDIR:-/tmp}/larm-build-dbg}"
CLT=/Library/Developer/CommandLineTools/Library/Developer
F="$CLT/Frameworks"; L="$CLT/usr/lib"
exec swift test --scratch-path "$SCRATCH" \
  -Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
