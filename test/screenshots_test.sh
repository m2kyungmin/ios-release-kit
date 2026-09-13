#!/usr/bin/env bash
# sips 리사이즈 부분만 검증(시뮬레이터 불필요). 1000x2000 PNG → 1320x2868.
set -euo pipefail
T=$(mktemp -d); python3 - "$T/in.png" <<'PY'
import sys,zlib,struct
w,h=1000,2000; raw=b''.join(b'\x00'+b'\xff\xff\xff'*w for _ in range(h))
def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
open(sys.argv[1],'wb').write(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
PY
sips -z 2868 1320 "$T/in.png" --out "$T/out.png" >/dev/null
W=$(sips -g pixelWidth "$T/out.png" | awk '/pixelWidth/{print $2}'); H=$(sips -g pixelHeight "$T/out.png" | awk '/pixelHeight/{print $2}')
[ "$W" = "1320" ] && [ "$H" = "2868" ] && echo "OK 1320x2868" || { echo "FAIL ${W}x${H}"; exit 1; }
