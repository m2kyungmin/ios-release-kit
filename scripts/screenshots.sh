#!/usr/bin/env bash
# 시뮬레이터 스크린샷: 상태바 정리 → 캡처 → 6.9인치(1320x2868) 리사이즈.
# 사용: scripts/screenshots.sh <시뮬레이터 UDID|booted> <출력폴더> <파일이름(확장자 없이)>
set -euo pipefail
UDID="${1:?udid}"; OUT="${2:?출력폴더}"; NAME="${3:?이름}"
mkdir -p "$OUT"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --operatorName "" >/dev/null 2>&1 || true
xcrun simctl io "$UDID" screenshot "$OUT/$NAME.png" >/dev/null
W=$(sips -g pixelWidth "$OUT/$NAME.png" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$OUT/$NAME.png" | awk '/pixelHeight/{print $2}')
if [ "$W" != "1320" ] || [ "$H" != "2868" ]; then
  sips -z 2868 1320 "$OUT/$NAME.png" --out "$OUT/$NAME.png" >/dev/null
fi
echo "$OUT/$NAME.png ${W}x${H} → 1320x2868"
