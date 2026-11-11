#!/bin/sh
# Regenerates every icon file from tiesheet.svg / tiesheet-small.svg.
# Needs rsvg-convert, ImageMagick, python3 and x86_64-w64-mingw32-windres.
# The results are committed, so building TiePaper itself needs none of these.
set -e
cd "$(dirname "$0")"
mkdir -p png
for n in 48 64 128 256 512; do rsvg-convert -w $n -h $n tiesheet.svg -o png/tiesheet-$n.png; done
# the simplified drawing reads better when it is tiny
for n in 16 24 32; do rsvg-convert -w $n -h $n tiesheet-small.svg -o png/tiesheet-$n.png; done
# an .ico whose entries are PNGs (Windows Vista and later), far smaller than the usual bitmaps
python3 - <<'PY'
import struct
sizes = [16, 24, 32, 48, 64, 128, 256]
pngs = [open('png/tiesheet-%d.png' % n, 'rb').read() for n in sizes]
out = struct.pack('<HHH', 0, 1, len(sizes))
off = 6 + 16 * len(sizes)
for n, p in zip(sizes, pngs):
    out += struct.pack('<BBBBHHII', n % 256, n % 256, 0, 0, 1, 32, len(p), off)
    off += len(p)
open('tiesheet.ico', 'wb').write(out + b''.join(pngs))
PY
# the window icon, as raw RGBA, is compiled into the program as a resource
magick png/tiesheet-128.png -depth 8 rgba:icon128.rgba
x86_64-w64-mingw32-windres -O res -i tiesheet.rc -o tiesheet.res
echo "Icons regenerated"
