#!/bin/sh
# Drives the real program headlessly with scripted keystrokes and compares what it ends up with
# (the whole sheet as a TieSheet file) with tests/expected/.  Needs SDL2 and SDL2_ttf.
# Use "update" as the first argument to rewrite the expected files after checking the new output by hand,
# or "win" to run the cross-compiled Windows build under wine (build/win/tiesheet.exe, with its DLLs).
cd "$(dirname "$0")/.."
rm -rf build/test-out
mkdir -p build/test-out
export HOME="$PWD/build/home" XDG_CONFIG_HOME="$PWD/build/home/.config" SDL_VIDEODRIVER=dummy
RUN="./build/tiesheet"
if [ "$1" = win ]; then
  RUN="wine build/win/tiesheet.exe"
  export WINEPREFIX="$PWD/build/wine-prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" SDL_RENDER_DRIVER=software
  unset WAYLAND_DISPLAY
fi
fail=0
for s in tests/scripts/*.txt; do
  name=$(basename "$s" .txt)
  rm -rf build/home; mkdir -p build/home      # every script starts with a clean configuration
  timeout 120 $RUN --script "$s" || { echo "FAIL: $name did not run"; fail=1; }
done
if [ "$1" = update ]; then
  UPDATE=1
  rm -f build/test-out/diff.txt
  cp build/test-out/*.* tests/expected/ 2>/dev/null
  mkdir -p tests/expected/pk; cp build/test-out/pk/*.tsh tests/expected/pk/
  echo "expected files updated"
  exit 0
fi
for f in tests/expected/*; do
  [ -f "$f" ] || continue
  b=$(basename "$f")
  if [ ! -f "build/test-out/$b" ]; then echo "FAIL: $b was not written"; fail=1
  elif ! diff -u "$f" "build/test-out/$b" > build/test-out/diff.txt; then echo "FAIL: $b differs"; cat build/test-out/diff.txt; fail=1; fi
done
# the second half of quit.txt must not run: the program ends when N is answered
[ -e build/test-out/quit_b.txt ] && { echo "FAIL: quit_b.txt was written, the program did not quit"; fail=1; }
# things the picker made: a folder, and files saved into it
[ -d build/test-out/pk ] || { echo "FAIL: the picker did not make build/test-out/pk"; fail=1; }
for f in tests/expected/pk/*; do
  b=$(basename "$f")
  if [ ! -f "build/test-out/pk/$b" ]; then echo "FAIL: build/test-out/pk/$b was not saved"; fail=1
  elif ! cmp -s "build/test-out/pk/$b" "$f"; then echo "FAIL: pk/$b differs"; diff -u "$f" "build/test-out/pk/$b"; fail=1; fi
done
[ $fail = 0 ] && echo "gui tests passed"
exit $fail
