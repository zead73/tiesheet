#!/bin/sh
# Cross-compiles the Windows 64-bit version into build/win/tiesheet.exe
#
# Needs fpc with the win64 units (Arch's fpc package ships them).  Nothing is linked against SDL: the
# program loads SDL2.dll and SDL2_ttf.dll at run time; run ./fetch-windows-dlls.sh to put the official
# ones next to tiesheet.exe.  The fonts folder is copied alongside.
set -e
cd "$(dirname "$0")"
mkdir -p build/units-win build/win
fpc -Twin64 -Px86_64 -Mobjfpc -Sh -O2 -Xs -FUbuild/units-win -Fusrc -FEbuild/win -otiesheet.exe src/tiesheet.lpr
rm -rf build/win/fonts
cp -r fonts build/win/fonts
echo "Built: build/win/tiesheet.exe  (run ./fetch-windows-dlls.sh for SDL2.dll and SDL2_ttf.dll)"
