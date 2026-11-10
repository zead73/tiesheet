#!/bin/sh
# Drives the real program headlessly with scripted keystrokes and compares what it ends up with
# (the whole sheet as a TieSheet file) with tests/expected/.  Needs SDL2 and SDL2_ttf.
# Use "update" as the first argument to rewrite the expected files after checking the new output by hand,
# or "win" to run the cross-compiled Windows build under wine (build/win/tiesheet.exe, with its DLLs).
cd "$(dirname "$0")/.."
mkdir -p build/test-out
rm -f build/test-out/*
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
  rm -f build/test-out/diff.txt
  cp build/test-out/* tests/expected/
  echo "expected files updated"
  exit 0
fi
for f in tests/expected/*; do
  b=$(basename "$f")
  if [ ! -f "build/test-out/$b" ]; then echo "FAIL: $b was not written"; fail=1
  elif ! diff -u "$f" "build/test-out/$b" > build/test-out/diff.txt; then echo "FAIL: $b differs"; cat build/test-out/diff.txt; fail=1; fi
done
# the second half of quit.txt must not run: the program ends when N is answered
[ -e build/test-out/quit_b.txt ] && { echo "FAIL: quit_b.txt was written, the program did not quit"; fail=1; }
[ $fail = 0 ] && echo "gui tests passed"
exit $fail
